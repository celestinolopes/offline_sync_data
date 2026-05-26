import 'dart:async';

import '../connectivity/connectivity_monitor.dart';
import '../conflict/conflict_resolver.dart';
import '../core/offline_sync_options.dart';
import '../database/sqflite_sync_queue_storage.dart';
import '../database/sync_queue_storage.dart';
import '../models/local_record.dart';
import '../models/sync_queue_item.dart';
import 'offline_sync_manager.dart';
import 'sync_api_adapter.dart';

/// High-level entry point for saving offline actions and observing their state.
class OfflineSyncEngine {
  factory OfflineSyncEngine({
    required SyncApiAdapter apiAdapter,
    SyncQueueStorage? storage,
    ConnectivityMonitor? connectivity,
    OfflineSyncOptions options = const OfflineSyncOptions(),
    ConflictResolver? conflictResolver,
  }) {
    return OfflineSyncEngine.withDependencies(
      apiAdapter: apiAdapter,
      storage: storage ?? SqfliteSyncQueueStorage(),
      connectivity: connectivity ??
          InternetConnectionMonitor(
            checkInterval: options.connectivityCheckInterval ??
                const Duration(milliseconds: 500),
          ),
      options: options,
      conflictResolver: conflictResolver,
    );
  }

  /// Constructor for explicitly sharing pre-built dependencies.
  ///
  /// Prefer this when injecting test implementations or a customized SQLite
  /// storage instance.
  OfflineSyncEngine.withDependencies({
    required SyncApiAdapter apiAdapter,
    required SyncQueueStorage storage,
    required ConnectivityMonitor connectivity,
    OfflineSyncOptions options = const OfflineSyncOptions(),
    ConflictResolver? conflictResolver,
  })  : _storage = storage,
        _options = options,
        syncManager = OfflineSyncManager(
          storage: storage,
          apiAdapter: apiAdapter,
          connectivity: connectivity,
          options: options,
          conflictResolver: conflictResolver,
        );

  final SyncQueueStorage _storage;
  final OfflineSyncOptions _options;
  final OfflineSyncManager syncManager;

  Future<void> initialize() => _storage.initialize();

  /// Records an operation locally before any attempt to contact the server.
  Future<void> save({
    required String entity,
    required String id,
    required Map<String, dynamic> data,
    required SyncOperation operation,
  }) async {
    await initialize();
    final previous = await _storage.find(entity, id);
    if (previous?.operationType == SyncOperation.create &&
        operation == SyncOperation.delete &&
        previous?.status == SyncStatus.pending &&
        previous?.retryCount == 0) {
      await _storage.discardPendingCreate(entity, id);
      return;
    }

    final now = DateTime.now().toUtc();
    final effectiveOperation =
        previous?.operationType == SyncOperation.create &&
                operation == SyncOperation.update &&
                previous?.status == SyncStatus.pending &&
                previous?.retryCount == 0
            ? SyncOperation.create
            : operation;
    final queued = SyncQueueItem(
      id: id,
      entityName: entity,
      operationType: effectiveOperation,
      payload: data,
      status: SyncStatus.pending,
      retryCount: 0,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    await _storage.persistLocalChange(queued);
    if (_options.syncAfterSave) unawaited(syncManager.syncNow());
  }

  /// Gets a locally persisted domain document, even without network access.
  Future<LocalRecord?> getRecord(String entity, String id) =>
      _storage.getRecord(entity, id);

  /// Gets all locally persisted domain documents for an entity collection.
  Future<List<LocalRecord>> getRecords(String entity) =>
      _storage.getRecords(entity);

  /// Watches persisted domain documents as local writes and sync results occur.
  Stream<List<LocalRecord>> watchRecords(String entity) =>
      _storage.watchRecords(entity);

  /// Watches whether a network is available while auto sync is enabled.
  Stream<bool> watchConnectivity() => syncManager.watchConnectivity();

  Stream<List<SyncQueueItem>> watchQueue() => _storage.watchQueue();

  Stream<SyncStatus> watchItemStatus(String id, {String? entity}) async* {
    await for (final queue in watchQueue()) {
      final matches = queue.where(
        (item) =>
            item.id == id && (entity == null || item.entityName == entity),
      );
      if (matches.isNotEmpty) yield matches.last.status;
    }
  }

  Future<void> clearSynced() => _storage.clearSynced();

  Future<void> dispose() async {
    await syncManager.dispose();
    await _storage.dispose();
  }
}
