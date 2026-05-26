import '../models/local_record.dart';
import '../models/sync_queue_item.dart';

/// Storage contract used by the engine for local documents and its sync queue.
///
/// Implement it to replace SQLite in tests or in applications with a
/// pre-existing database layer. [persistLocalChange] must persist the local
/// document mutation and its queue item atomically.
abstract class SyncQueueStorage {
  Future<void> initialize();

  Future<void> persistLocalChange(SyncQueueItem item);

  Future<void> discardPendingCreate(String entityName, String id);

  Future<LocalRecord?> getRecord(String entityName, String id);

  Future<List<LocalRecord>> getRecords(String entityName);

  Stream<List<LocalRecord>> watchRecords(String entityName);

  Future<void> upsert(SyncQueueItem item);

  Future<void> delete(String entityName, String id);

  Future<SyncQueueItem?> find(String entityName, String id);

  Future<List<SyncQueueItem>> getAll();

  /// Returns pending, failed, and interrupted syncing operations.
  /// [maxRetries] is applied by the manager per synchronization run;
  /// previously failed operations remain eligible when connectivity returns
  /// or a manual retry is requested.
  Future<List<SyncQueueItem>> getReadyToSync({required int maxRetries});

  Stream<List<SyncQueueItem>> watchQueue();

  /// Marks an operation as synchronized and stores an API representation when
  /// no newer local edit has replaced the syncing operation.
  Future<void> markSynced(
    SyncQueueItem syncing,
    SyncQueueItem synced, {
    Map<String, dynamic>? remoteData,
  });

  Future<void> clearSynced();

  Future<void> dispose();
}
