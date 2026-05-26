import 'dart:async';

import '../connectivity/connectivity_monitor.dart';
import '../conflict/conflict_resolver.dart';
import '../core/offline_sync_options.dart';
import '../database/sync_queue_storage.dart';
import '../models/sync_queue_item.dart';
import 'sync_api_adapter.dart';

typedef SyncDelay = Future<void> Function(Duration duration);
typedef SyncClock = DateTime Function();

class _OfflineDuringSync implements Exception {
  const _OfflineDuringSync();
}

/// Sends pending queue entries to a remote adapter when a network is present.
class OfflineSyncManager {
  OfflineSyncManager({
    required SyncQueueStorage storage,
    required SyncApiAdapter apiAdapter,
    required ConnectivityMonitor connectivity,
    this.options = const OfflineSyncOptions(),
    this.conflictResolver,
    SyncDelay? delay,
    SyncClock? clock,
  })  : _storage = storage,
        _apiAdapter = apiAdapter,
        _connectivity = connectivity,
        _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? _utcNow;

  final SyncQueueStorage _storage;
  final SyncApiAdapter _apiAdapter;
  final ConnectivityMonitor _connectivity;
  final SyncDelay _delay;
  final SyncClock _clock;
  final OfflineSyncOptions options;
  final ConflictResolver? conflictResolver;

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _connectivityTimer;
  final StreamController<bool> _connectivityStates =
      StreamController<bool>.broadcast();
  final StreamController<void> _retryWakeups =
      StreamController<void>.broadcast();
  bool? _lastConnectivity;
  DateTime? _lastConnectivityProbeAt;
  bool _refreshingConnectivity = false;
  bool _connectivityRefreshQueued = false;
  Future<void>? _runningSync;
  bool _syncRequested = false;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Processes all eligible operations. Concurrent calls share one run.
  Future<void> syncNow() {
    _syncRequested = true;
    final running = _runningSync;
    if (running != null) {
      _retryWakeups.add(null);
      return running;
    }
    final future = _drainSyncRequests();
    _runningSync = future;
    return future.whenComplete(() => _runningSync = null);
  }

  Future<void> _drainSyncRequests() async {
    while (_syncRequested) {
      _syncRequested = false;
      await _performSync();
    }
  }

  /// Emits the current network state and subsequent changes while auto sync
  /// observation is active.
  Stream<bool> watchConnectivity() async* {
    yield _lastConnectivity ?? await _connectivity.isConnected;
    yield* _connectivityStates.stream;
  }

  /// Starts listening for network restoration and immediately checks once.
  ///
  /// [ConnectivityMonitor.onConnectivityChanged] is complemented by an optional
  /// periodic [ConnectivityMonitor.isConnected] poll when native events are
  /// delayed (for example on some simulators).
  Future<void> startAutoSync() async {
    if (_connectivitySubscription != null) return;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivity,
      onError: _connectivityStates.addError,
    );
    final interval = options.connectivityCheckInterval;
    if (interval != null) {
      _connectivityTimer = Timer.periodic(
        interval,
        (_) => unawaited(_refreshConnectivity()),
      );
    }
    await _refreshConnectivity();
  }

  Future<void> stopAutoSync() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
  }

  Future<void> _refreshConnectivity() async {
    if (_refreshingConnectivity) {
      _connectivityRefreshQueued = true;
      return;
    }
    _refreshingConnectivity = true;
    try {
      do {
        _connectivityRefreshQueued = false;
        _handleConnectivity(await _resolveConnectivityForPoll());
      } while (_connectivityRefreshQueued);
    } finally {
      _refreshingConnectivity = false;
    }
  }

  /// Reuses the last online result during polling to avoid repeated HTTP
  /// reachability probes on every interval while connectivity stays up.
  Future<bool> _resolveConnectivityForPoll() async {
    if (_lastConnectivity == true &&
        _lastConnectivityProbeAt != null &&
        _clock().difference(_lastConnectivityProbeAt!) <
            options.connectivityProbeMinIntervalWhileOnline) {
      return true;
    }
    return _probeConnectivity();
  }

  Future<bool> _probeConnectivity() async {
    final connected = await _connectivity.isConnected;
    _lastConnectivityProbeAt = _clock();
    return connected;
  }

  Future<bool> _isEffectivelyConnected({bool forceProbe = false}) async {
    if (!forceProbe) {
      if (_lastConnectivity == true) return true;
      if (_lastConnectivity == false) return false;
    }
    return _probeConnectivity();
  }

  void _handleConnectivity(bool connected) {
    final changed = connected != _lastConnectivity;
    _lastConnectivity = connected;
    if (!connected) _lastConnectivityProbeAt = null;
    if (changed) _connectivityStates.add(connected);
    // A network interface may remain reported as online while the API is
    // temporarily unreachable. Each online confirmation gives failed or
    // pending work another chance without requiring a second transition.
    if (connected) unawaited(syncNow());
  }

  Future<void> _performSync() async {
    final items = await _storage.getReadyToSync(maxRetries: options.maxRetries);
    for (final item in items) {
      if (!await _syncWithRetry(item)) return;
    }
  }

  /// Returns false when synchronization must stop until internet is restored.
  Future<bool> _syncWithRetry(SyncQueueItem firstItem) async {
    var item = firstItem;
    var attemptsThisRun = 0;
    while (attemptsThisRun < options.maxRetries) {
      attemptsThisRun++;
      if (!await _isEffectivelyConnected()) return false;
      final syncing = item.copyWith(
        status: SyncStatus.syncing,
        updatedAt: _clock(),
        clearLastError: true,
      );
      await _storage.upsert(syncing);
      try {
        final remoteData = await _send(syncing);
        await _storage.markSynced(
          syncing,
          syncing.copyWith(status: SyncStatus.synced, updatedAt: _clock()),
          remoteData: remoteData,
        );
        return true;
      } on _OfflineDuringSync {
        await _restorePending(syncing);
        return false;
      } catch (error) {
        if (!await _isEffectivelyConnected(forceProbe: true)) {
          await _restorePending(syncing);
          return false;
        }
        final failed = syncing.copyWith(
          status: SyncStatus.failed,
          retryCount: syncing.retryCount + 1,
          updatedAt: _clock(),
          lastError: error.toString(),
        );
        await _storage.upsert(failed);
        if (attemptsThisRun >= options.maxRetries) return true;
        await _waitForRetryOrNewSignal(
          options.delayForRetry(attemptsThisRun),
        );
        final current = await _storage.find(failed.entityName, failed.id);
        if (current?.updatedAt != failed.updatedAt) return true;
        item = failed;
      }
    }
    return true;
  }

  Future<void> _restorePending(SyncQueueItem item) {
    return _storage.upsert(
      item.copyWith(
        status: SyncStatus.pending,
        updatedAt: _clock(),
        clearLastError: true,
      ),
    );
  }

  Future<void> _requireConnectivity() async {
    if (!await _isEffectivelyConnected()) {
      throw const _OfflineDuringSync();
    }
  }

  Future<void> _waitForRetryOrNewSignal(Duration delay) async {
    final wakeup = Completer<void>();
    final subscription = _retryWakeups.stream.listen((_) {
      if (!wakeup.isCompleted) wakeup.complete();
    });
    try {
      await Future.any<void>(<Future<void>>[_delay(delay), wakeup.future]);
    } finally {
      await subscription.cancel();
    }
  }

  Future<Map<String, dynamic>?> _send(SyncQueueItem item) async {
    switch (item.operationType) {
      case SyncOperation.create:
        await _requireConnectivity();
        final remote = await _apiAdapter.fetchRemote(item.entityName, item.id);
        if (remote != null) {
          await _requireConnectivity();
          return _apiAdapter.update(item.entityName, item.id, item.payload);
        }
        await _requireConnectivity();
        return _apiAdapter.create(item.entityName, item.payload);
      case SyncOperation.update:
        var payload = item.payload;
        final resolver = conflictResolver;
        if (resolver != null) {
          await _requireConnectivity();
          final remote = await _apiAdapter.fetchRemote(
            item.entityName,
            item.id,
          );
          if (remote != null) {
            payload = await resolver.resolve(
              localData: payload,
              remoteData: remote,
            );
          }
        }
        await _requireConnectivity();
        return _apiAdapter.update(item.entityName, item.id, payload);
      case SyncOperation.delete:
        await _requireConnectivity();
        await _apiAdapter.delete(item.entityName, item.id);
        return null;
    }
  }

  Future<void> dispose() async {
    await stopAutoSync();
    await _connectivityStates.close();
    await _retryWakeups.close();
  }
}
