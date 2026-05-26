import '../sync/offline_sync_manager.dart';

/// Entry point that background-task integrations can invoke.
///
/// This package does not force a background execution plugin. Applications can
/// call [execute] from a Workmanager, background_fetch, or native task handler.
class BackgroundSyncScheduler {
  const BackgroundSyncScheduler(this.syncManager);

  static const String defaultTaskName = 'offlineSyncData.sync';

  final OfflineSyncManager syncManager;

  Future<void> execute() => syncManager.syncNow();
}
