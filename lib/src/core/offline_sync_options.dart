/// Configuration for retries and queue behavior.
class OfflineSyncOptions {
  const OfflineSyncOptions({
    this.maxRetries = 3,
    this.retryBaseDelay = const Duration(seconds: 2),
    this.syncAfterSave = true,
    this.connectivityCheckInterval = const Duration(milliseconds: 500),
    this.connectivityProbeMinIntervalWhileOnline =
        const Duration(milliseconds: 800),
  }) : assert(maxRetries > 0, 'maxRetries must be greater than zero');

  /// Maximum number of attempts per queued action.
  final int maxRetries;

  /// The retry delay is `attemptInCurrentRun * retryBaseDelay`.
  ///
  /// [SyncQueueItem.retryCount] remains a historical failure count, while the
  /// delay restarts in a new synchronization run so recovery is responsive.
  final Duration retryBaseDelay;

  /// Triggers a best-effort synchronization immediately after `save`.
  final bool syncAfterSave;

  /// Periodically confirms connectivity while auto sync is enabled.
  ///
  /// This complements [ConnectivityMonitor.onConnectivityChanged], which can be
  /// delayed on some emulators. Set it to `null` to rely only on the monitor
  /// stream.
  final Duration? connectivityCheckInterval;

  /// Minimum time between full reachability probes while already online.
  ///
  /// Polling and sync still run on schedule, but expensive HTTP checks to
  /// external endpoints are skipped until this interval elapses. Probes always
  /// run immediately after an offline state or when connectivity is unknown.
  final Duration connectivityProbeMinIntervalWhileOnline;

  Duration delayForRetry(int retryCount) => retryBaseDelay * retryCount;
}
