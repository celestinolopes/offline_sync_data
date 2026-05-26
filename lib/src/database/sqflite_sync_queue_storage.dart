import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/local_record.dart';
import '../models/sync_queue_item.dart';
import 'sync_queue_storage.dart';

/// SQLite-backed queue storage suitable for Android and iOS applications.
class SqfliteSyncQueueStorage implements SyncQueueStorage {
  SqfliteSyncQueueStorage({
    this.databaseName = 'offline_sync_data.db',
    this.databasePath,
    DatabaseFactory? factory,
  }) : _databaseFactory = factory ?? databaseFactory;

  final String databaseName;
  final String? databasePath;
  final DatabaseFactory _databaseFactory;
  final StreamController<List<SyncQueueItem>> _changes =
      StreamController<List<SyncQueueItem>>.broadcast();
  final StreamController<String> _recordChanges =
      StreamController<String>.broadcast();

  Database? _database;

  @override
  Future<void> initialize() async {
    if (_database != null) return;
    final resolvedPath =
        databasePath ?? path.join(await getDatabasesPath(), databaseName);
    _database = await _databaseFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, version) async {
          await _createQueueTable(database);
          await _createRecordsTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createRecordsTable(database);
            await database.execute('''
              INSERT INTO local_records
                (recordKey, id, entityName, data, createdAt, updatedAt)
              SELECT queueKey, id, entityName, payload, createdAt, updatedAt
              FROM sync_queue
              WHERE operationType != 'delete'
            ''');
          }
        },
      ),
    );
  }

  Future<void> _createQueueTable(Database database) async {
    await database.execute('''
      CREATE TABLE sync_queue (
        queueKey TEXT PRIMARY KEY,
        id TEXT NOT NULL,
        entityName TEXT NOT NULL,
        operationType TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        retryCount INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        lastError TEXT
      )
    ''');
    await database.execute(
      'CREATE INDEX sync_queue_status_created '
      'ON sync_queue(status, createdAt)',
    );
  }

  Future<void> _createRecordsTable(Database database) async {
    await database.execute('''
      CREATE TABLE local_records (
        recordKey TEXT PRIMARY KEY,
        id TEXT NOT NULL,
        entityName TEXT NOT NULL,
        data TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX local_records_entity_updated '
      'ON local_records(entityName, updatedAt)',
    );
  }

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  @override
  Future<void> persistLocalChange(SyncQueueItem item) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert(
        'sync_queue',
        item.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (item.operationType == SyncOperation.delete) {
        await transaction.delete(
          'local_records',
          where: 'recordKey = ?',
          whereArgs: [item.databaseKey],
        );
        return;
      }
      final previous = await transaction.query(
        'local_records',
        where: 'recordKey = ?',
        whereArgs: [item.databaseKey],
        limit: 1,
      );
      final record = LocalRecord(
        id: item.id,
        entityName: item.entityName,
        data: item.payload,
        createdAt: previous.isEmpty
            ? item.createdAt
            : LocalRecord.fromDatabaseMap(previous.first).createdAt,
        updatedAt: item.updatedAt,
      );
      await transaction.insert(
        'local_records',
        record.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await _emitQueue();
    _emitRecords(item.entityName);
  }

  @override
  Future<void> discardPendingCreate(String entityName, String id) async {
    final database = await _db;
    final key = '$entityName::$id';
    await database.transaction((transaction) async {
      await transaction.delete(
        'sync_queue',
        where: 'queueKey = ?',
        whereArgs: [key],
      );
      await transaction.delete(
        'local_records',
        where: 'recordKey = ?',
        whereArgs: [key],
      );
    });
    await _emitQueue();
    _emitRecords(entityName);
  }

  @override
  Future<LocalRecord?> getRecord(String entityName, String id) async {
    final database = await _db;
    final records = await database.query(
      'local_records',
      where: 'recordKey = ?',
      whereArgs: ['$entityName::$id'],
      limit: 1,
    );
    return records.isEmpty ? null : LocalRecord.fromDatabaseMap(records.first);
  }

  @override
  Future<List<LocalRecord>> getRecords(String entityName) async {
    final database = await _db;
    final records = await database.query(
      'local_records',
      where: 'entityName = ?',
      whereArgs: [entityName],
      orderBy: 'updatedAt DESC',
    );
    return records.map(LocalRecord.fromDatabaseMap).toList(growable: false);
  }

  @override
  Stream<List<LocalRecord>> watchRecords(String entityName) async* {
    yield await getRecords(entityName);
    yield* _recordChanges.stream
        .where((changedEntity) => changedEntity == entityName)
        .asyncMap((_) => getRecords(entityName));
  }

  @override
  Future<void> upsert(SyncQueueItem item) async {
    final database = await _db;
    await database.insert(
      'sync_queue',
      item.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitQueue();
  }

  @override
  Future<void> delete(String entityName, String id) async {
    final database = await _db;
    await database.delete(
      'sync_queue',
      where: 'queueKey = ?',
      whereArgs: ['$entityName::$id'],
    );
    await _emitQueue();
  }

  @override
  Future<SyncQueueItem?> find(String entityName, String id) async {
    final database = await _db;
    final result = await database.query(
      'sync_queue',
      where: 'queueKey = ?',
      whereArgs: ['$entityName::$id'],
      limit: 1,
    );
    return result.isEmpty ? null : SyncQueueItem.fromDatabaseMap(result.first);
  }

  @override
  Future<List<SyncQueueItem>> getAll() async {
    final database = await _db;
    final records = await database.query(
      'sync_queue',
      orderBy: 'createdAt ASC',
    );
    return records.map(SyncQueueItem.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<List<SyncQueueItem>> getReadyToSync({required int maxRetries}) async {
    final database = await _db;
    final records = await database.query(
      'sync_queue',
      where: 'status = ? OR status = ? OR status = ?',
      whereArgs: [
        SyncStatus.pending.name,
        SyncStatus.failed.name,
        SyncStatus.syncing.name,
      ],
      orderBy: 'createdAt ASC',
    );
    return records.map(SyncQueueItem.fromDatabaseMap).toList(growable: false);
  }

  @override
  Stream<List<SyncQueueItem>> watchQueue() async* {
    yield await getAll();
    yield* _changes.stream;
  }

  @override
  Future<void> markSynced(
    SyncQueueItem syncing,
    SyncQueueItem synced, {
    Map<String, dynamic>? remoteData,
  }) async {
    final database = await _db;
    var recordChanged = false;
    await database.transaction((transaction) async {
      final currentRecords = await transaction.query(
        'sync_queue',
        where: 'queueKey = ?',
        whereArgs: [syncing.databaseKey],
        limit: 1,
      );
      if (currentRecords.isEmpty) return;
      final current = SyncQueueItem.fromDatabaseMap(currentRecords.first);
      if (current.updatedAt != syncing.updatedAt ||
          current.status != SyncStatus.syncing) {
        return;
      }
      await transaction.insert(
        'sync_queue',
        synced.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (remoteData == null || syncing.operationType == SyncOperation.delete) {
        return;
      }
      final records = await transaction.query(
        'local_records',
        where: 'recordKey = ?',
        whereArgs: [syncing.databaseKey],
        limit: 1,
      );
      if (records.isEmpty) return;
      final local = LocalRecord.fromDatabaseMap(records.first);
      await transaction.insert(
        'local_records',
        LocalRecord(
          id: local.id,
          entityName: local.entityName,
          data: remoteData,
          createdAt: local.createdAt,
          updatedAt: synced.updatedAt,
        ).toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      recordChanged = true;
    });
    await _emitQueue();
    if (recordChanged) _emitRecords(syncing.entityName);
  }

  @override
  Future<void> clearSynced() async {
    final database = await _db;
    await database.delete(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncStatus.synced.name],
    );
    await _emitQueue();
  }

  Future<void> _emitQueue() async {
    if (!_changes.isClosed) _changes.add(await getAll());
  }

  void _emitRecords(String entityName) {
    if (!_recordChanges.isClosed) _recordChanges.add(entityName);
  }

  @override
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
    await _changes.close();
    await _recordChanges.close();
  }
}
