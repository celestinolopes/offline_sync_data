import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_data/offline_sync_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('InternetConnectionMonitor', () {
    test('reports online from hasInternetAccess', () async {
      final monitor = InternetConnectionMonitor(
        hasInternetAccessOverride: () async => true,
      );

      expect(await monitor.isConnected, isTrue);
    });

    test('reports offline from hasInternetAccess', () async {
      final monitor = InternetConnectionMonitor(
        hasInternetAccessOverride: () async => false,
      );

      expect(await monitor.isConnected, isFalse);
    });

    test('maps status stream to connectivity booleans', () async {
      final status = StreamController<InternetStatus>();
      final monitor = InternetConnectionMonitor(
        statusChangesOverride: status.stream,
      );
      final states = <bool>[];
      final subscription = monitor.onConnectivityChanged.listen(states.add);

      status.add(InternetStatus.connected);
      status.add(InternetStatus.disconnected);
      status.add(InternetStatus.connected);
      await Future<void>.delayed(Duration.zero);

      expect(states, const <bool>[true, false, true]);

      await subscription.cancel();
      await status.close();
    });

    test('stays online when any custom endpoint succeeds', () async {
      final monitor = InternetConnectionMonitor(
        connection: InternetConnection.createInstance(
          useDefaultOptions: false,
          customCheckOptions: <InternetCheckOption>[
            InternetCheckOption(uri: Uri.parse('https://offline.test')),
            InternetCheckOption(uri: Uri.parse('https://online.test')),
          ],
          customConnectivityCheck: (option) async => InternetCheckResult(
            option: option,
            isSuccess: option.uri.host == 'online.test',
          ),
        ),
      );

      expect(await monitor.isConnected, isTrue);
    });
  });

  group('Conflict resolvers', () {
    final local = <String, dynamic>{
      'title': 'local',
      'updatedAt': '2026-01-02T00:00:00Z',
    };
    final remote = <String, dynamic>{
      'title': 'remote',
      'updatedAt': '2026-01-03T00:00:00Z',
    };

    test('local wins returns local data', () async {
      expect(
        await const LocalWinsConflictResolver().resolve(
          localData: local,
          remoteData: remote,
        ),
        local,
      );
    });

    test('remote wins returns remote data', () async {
      expect(
        await const RemoteWinsConflictResolver().resolve(
          localData: local,
          remoteData: remote,
        ),
        remote,
      );
    });

    test('last write wins compares updatedAt', () async {
      expect(
        await const LastWriteWinsConflictResolver().resolve(
          localData: local,
          remoteData: remote,
        ),
        remote,
      );
    });
  });

  group('OfflineSyncManager', () {
    test(
      'retries failed calls using configured backoff and marks synced',
      () async {
        final storage = MemoryQueueStorage();
        final adapter = FakeApiAdapter(failuresBeforeSuccess: 2);
        final delays = <Duration>[];
        await storage.upsert(_pending());
        final manager = OfflineSyncManager(
          storage: storage,
          apiAdapter: adapter,
          connectivity: FakeConnectivity(true),
          options: const OfflineSyncOptions(
            maxRetries: 3,
            retryBaseDelay: Duration(seconds: 2),
          ),
          delay: (duration) async => delays.add(duration),
        );

        await manager.syncNow();

        final item = await storage.find('tasks', 'task-1');
        expect(item?.status, SyncStatus.synced);
        expect(item?.retryCount, 2);
        expect(adapter.createCalls, 3);
        expect(delays, const [Duration(seconds: 2), Duration(seconds: 4)]);
      },
    );

    test('leaves action pending without connectivity', () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final adapter = FakeApiAdapter();
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: FakeConnectivity(false),
      );

      await manager.syncNow();

      expect(
        (await storage.find('tasks', 'task-1'))?.status,
        SyncStatus.pending,
      );
      expect(adapter.fetchCalls, 0);
      expect(adapter.createCalls, 0);
    });

    test('does not post if connectivity drops after checking remote data',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final connectivity = FakeConnectivity(true);
      final adapter = FakeApiAdapter(
        onFetch: () async => connectivity.setConnected(false),
      );
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
      );

      await manager.syncNow();

      final item = await storage.find('tasks', 'task-1');
      expect(adapter.fetchCalls, 1);
      expect(adapter.createCalls, 0);
      expect(item?.status, SyncStatus.pending);
      expect(item?.retryCount, 0);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('does not count a request failure after connectivity is lost',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final connectivity = FakeConnectivity(true);
      final adapter = FakeApiAdapter(
        onCreate: () async {
          connectivity.setConnected(false);
          throw Exception('network lost');
        },
      );
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
      );

      await manager.syncNow();

      final item = await storage.find('tasks', 'task-1');
      expect(adapter.createCalls, 1);
      expect(item?.status, SyncStatus.pending);
      expect(item?.retryCount, 0);
      expect(item?.lastError, isNull);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('retains failed action in queue after maximum retries', () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: FakeApiAdapter(failuresBeforeSuccess: 99),
        connectivity: FakeConnectivity(true),
        options: const OfflineSyncOptions(
          maxRetries: 2,
          retryBaseDelay: Duration.zero,
        ),
        delay: (_) async {},
      );

      await manager.syncNow();

      final item = await storage.find('tasks', 'task-1');
      expect(item?.status, SyncStatus.failed);
      expect(item?.retryCount, 2);
      expect(item?.lastError, contains('temporary'));
    });

    test('uses conflict resolution before sending update', () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(
        _pending(operation: SyncOperation.update, payload: {'value': 'local'}),
      );
      final adapter = FakeApiAdapter(remote: {'value': 'remote'});
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: FakeConnectivity(true),
        conflictResolver: const RemoteWinsConflictResolver(),
      );

      await manager.syncNow();

      expect(adapter.updatedData, {'value': 'remote'});
    });

    test('recovers an interrupted syncing operation', () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending().copyWith(status: SyncStatus.syncing));
      final adapter = FakeApiAdapter();
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: FakeConnectivity(true),
      );

      await manager.syncNow();

      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
      expect(adapter.createCalls, 1);
    });

    test('reconciles a previously accepted create without posting a duplicate',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(
        _pending(payload: const {'id': 'task-1', 'value': 'local'})
            .copyWith(status: SyncStatus.failed),
      );
      final adapter = FakeApiAdapter(remote: const {'id': 'task-1'});
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: FakeConnectivity(true),
      );

      await manager.syncNow();

      expect(adapter.createCalls, 0);
      expect(adapter.updatedData, const {'id': 'task-1', 'value': 'local'});
      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
    });

    test('syncs pending data when connectivity stream reports online',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final adapter = FakeApiAdapter();
      final connectivity = FakeConnectivity(false);
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
        options: const OfflineSyncOptions(connectivityCheckInterval: null),
      );
      final states = <bool>[];
      manager.startAutoSync();
      final subscription = manager.watchConnectivity().listen(states.add);
      await Future<void>.delayed(Duration.zero);

      connectivity.setConnected(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(states, containsAllInOrder(<bool>[false, true]));
      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
      expect(adapter.createCalls, 1);

      await subscription.cancel();
      await manager.dispose();
      await connectivity.dispose();
    });

    test('retries an exhausted failed item after network restoration',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(
        _pending().copyWith(
          status: SyncStatus.failed,
          retryCount: 3,
          lastError: 'offline',
        ),
      );
      final adapter = FakeApiAdapter();
      final connectivity = FakeConnectivity(false);
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
        options: const OfflineSyncOptions(
          maxRetries: 3,
          connectivityCheckInterval: null,
        ),
      );
      manager.startAutoSync();
      await Future<void>.delayed(Duration.zero);

      connectivity.setConnected(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final item = await storage.find('tasks', 'task-1');
      expect(item?.status, SyncStatus.synced);
      expect(item?.retryCount, 3);
      expect(adapter.createCalls, 1);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('polling detects restored connectivity without a platform event',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final adapter = FakeApiAdapter();
      final connectivity = FakeConnectivity(false);
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
        options: const OfflineSyncOptions(
          connectivityCheckInterval: Duration(milliseconds: 1),
        ),
      );
      manager.startAutoSync();
      await Future<void>.delayed(const Duration(milliseconds: 3));

      connectivity.connected = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
      expect(adapter.createCalls, 1);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('polling retries failed data while connectivity remains online',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final adapter = FakeApiAdapter(failuresBeforeSuccess: 1);
      final connectivity = FakeConnectivity(true);
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
        options: const OfflineSyncOptions(
          maxRetries: 1,
          retryBaseDelay: Duration.zero,
          connectivityCheckInterval: Duration(milliseconds: 1),
        ),
      );
      manager.startAutoSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
      expect(adapter.createCalls, 2);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('network restoration interrupts a retry wait immediately', () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(_pending());
      final adapter = FakeApiAdapter(failuresBeforeSuccess: 1);
      final connectivity = FakeConnectivity(true);
      final waitStarted = Completer<void>();
      final neverEndingDelay = Completer<void>();
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: connectivity,
        options: const OfflineSyncOptions(
          maxRetries: 2,
          retryBaseDelay: Duration(days: 1),
          connectivityCheckInterval: null,
        ),
        delay: (_) {
          waitStarted.complete();
          return neverEndingDelay.future;
        },
      );
      manager.startAutoSync();
      await waitStarted.future;

      connectivity.setConnected(false);
      connectivity.setConnected(true);
      await _waitFor(
        () => adapter.createCalls == 2,
      );

      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);

      await manager.dispose();
      await connectivity.dispose();
    });

    test('a new retry round does not wait using the historic retry count',
        () async {
      final storage = MemoryQueueStorage();
      await storage.upsert(
        _pending().copyWith(status: SyncStatus.failed, retryCount: 100),
      );
      final adapter = FakeApiAdapter(failuresBeforeSuccess: 1);
      final delays = <Duration>[];
      final manager = OfflineSyncManager(
        storage: storage,
        apiAdapter: adapter,
        connectivity: FakeConnectivity(true),
        options: const OfflineSyncOptions(
          maxRetries: 2,
          retryBaseDelay: Duration(seconds: 2),
        ),
        delay: (duration) async => delays.add(duration),
      );

      await manager.syncNow();

      expect(
          (await storage.find('tasks', 'task-1'))?.status, SyncStatus.synced);
      expect(delays, const <Duration>[Duration(seconds: 2)]);
    });
  });

  test(
    'create followed by delete while pending removes the operation',
    () async {
      final storage = MemoryQueueStorage();
      final engine = OfflineSyncEngine.withDependencies(
        apiAdapter: FakeApiAdapter(),
        storage: storage,
        connectivity: FakeConnectivity(false),
        options: const OfflineSyncOptions(syncAfterSave: false),
      );

      await engine.save(
        entity: 'tasks',
        id: 'task-1',
        data: const {'title': 'Draft'},
        operation: SyncOperation.create,
      );
      await engine.save(
        entity: 'tasks',
        id: 'task-1',
        data: const {'title': 'Draft'},
        operation: SyncOperation.delete,
      );

      expect(await storage.getAll(), isEmpty);
      expect(await storage.getRecords('tasks'), isEmpty);
    },
  );

  test('save persists records in SQLite across engine instances', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('offline_sync_');
    final databasePath = '${directory.path}/engine.db';
    final firstStorage = SqfliteSyncQueueStorage(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    final firstEngine = OfflineSyncEngine.withDependencies(
      apiAdapter: FakeApiAdapter(),
      storage: firstStorage,
      connectivity: FakeConnectivity(false),
      options: const OfflineSyncOptions(syncAfterSave: false),
    );

    await firstEngine.save(
      entity: 'tasks',
      id: 'persisted-task',
      data: const {'id': 'persisted-task', 'title': 'Saved offline'},
      operation: SyncOperation.create,
    );
    await firstEngine.dispose();

    final secondStorage = SqfliteSyncQueueStorage(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    final secondEngine = OfflineSyncEngine.withDependencies(
      apiAdapter: FakeApiAdapter(),
      storage: secondStorage,
      connectivity: FakeConnectivity(false),
    );
    final record = await secondEngine.getRecord('tasks', 'persisted-task');
    final queue = await secondEngine.watchQueue().first;

    expect(record?.data['title'], 'Saved offline');
    expect(queue.single.status, SyncStatus.pending);

    await secondEngine.dispose();
    await directory.delete(recursive: true);
  });

  test('database upgrade restores queued payloads as local records', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('offline_sync_v1_');
    final databasePath = '${directory.path}/engine.db';
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
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
          await database.insert('sync_queue', _pending().toDatabaseMap());
        },
      ),
    );
    await legacyDatabase.close();

    final storage = SqfliteSyncQueueStorage(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    final records = await storage.getRecords('tasks');

    expect(records.single.data['id'], 'task-1');

    await storage.dispose();
    await directory.delete(recursive: true);
  });

  test('Dio flow creates, updates and deletes data after reconnecting',
      () async {
    final server = await MockRestServer.start();
    final connectivity = FakeConnectivity(false);
    final engine = OfflineSyncEngine.withDependencies(
      apiAdapter: DioSyncApiAdapter(
        dio: Dio(BaseOptions(baseUrl: server.baseUrl)),
      ),
      storage: MemoryQueueStorage(),
      connectivity: connectivity,
      options: const OfflineSyncOptions(connectivityCheckInterval: null),
    );
    await engine.initialize();
    engine.syncManager.startAutoSync();

    await engine.save(
      entity: 'tasks',
      id: 'rest-task',
      data: const {'id': 'rest-task', 'title': 'offline', 'completed': false},
      operation: SyncOperation.create,
    );
    expect(server.tasks, isEmpty);

    connectivity.setConnected(true);
    await _waitFor(() => server.tasks.containsKey('rest-task'));
    expect(server.tasks['rest-task']?['title'], 'offline');

    await engine.save(
      entity: 'tasks',
      id: 'rest-task',
      data: const {'id': 'rest-task', 'title': 'updated', 'completed': true},
      operation: SyncOperation.update,
    );
    await _waitFor(() => server.tasks['rest-task']?['title'] == 'updated');

    await engine.save(
      entity: 'tasks',
      id: 'rest-task',
      data: const {'id': 'rest-task', 'title': 'updated', 'completed': true},
      operation: SyncOperation.delete,
    );
    await _waitFor(() => !server.tasks.containsKey('rest-task'));

    await engine.dispose();
    await connectivity.dispose();
    await server.close();
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for REST synchronization.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SyncQueueItem _pending({
  SyncOperation operation = SyncOperation.create,
  Map<String, dynamic> payload = const {'id': 'task-1'},
}) =>
    SyncQueueItem.pending(
      id: 'task-1',
      entityName: 'tasks',
      operationType: operation,
      payload: payload,
      now: DateTime.utc(2026),
    );

class FakeConnectivity implements ConnectivityMonitor {
  FakeConnectivity(this.connected);

  bool connected;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> get isConnected async => connected;

  @override
  Stream<bool> get onConnectivityChanged => _changes.stream;

  void setConnected(bool value) {
    connected = value;
    _changes.add(value);
  }

  Future<void> dispose() => _changes.close();
}

class FakeApiAdapter implements SyncApiAdapter {
  FakeApiAdapter({
    this.failuresBeforeSuccess = 0,
    this.remote,
    this.onFetch,
    this.onCreate,
  });

  int failuresBeforeSuccess;
  int createCalls = 0;
  int fetchCalls = 0;
  final Map<String, dynamic>? remote;
  final Future<void> Function()? onFetch;
  final Future<void> Function()? onCreate;
  Map<String, dynamic>? updatedData;

  @override
  Future<Map<String, dynamic>> create(
    String entity,
    Map<String, dynamic> data,
  ) async {
    createCalls++;
    await onCreate?.call();
    if (createCalls <= failuresBeforeSuccess) throw Exception('temporary');
    return data;
  }

  @override
  Future<void> delete(String entity, String id) async {}

  @override
  Future<Map<String, dynamic>?> fetchRemote(String entity, String id) async {
    fetchCalls++;
    await onFetch?.call();
    return remote;
  }

  @override
  Future<Map<String, dynamic>> update(
    String entity,
    String id,
    Map<String, dynamic> data,
  ) async {
    updatedData = data;
    return data;
  }
}

class MockRestServer {
  MockRestServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final Map<String, Map<String, dynamic>> tasks =
      <String, Map<String, dynamic>>{};

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<MockRestServer> start() async => MockRestServer._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    if (parts.isEmpty || parts.first != 'tasks') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final id = parts.length > 1 ? parts[1] : null;
    if (request.method == 'GET' && id != null) {
      final task = tasks[id];
      if (task == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        _writeJson(request.response, task);
      }
    } else if (request.method == 'POST') {
      final task = await _readJson(request);
      tasks[task['id']! as String] = task;
      _writeJson(request.response, task);
    } else if (request.method == 'PUT' && id != null) {
      final task = await _readJson(request);
      tasks[id] = task;
      _writeJson(request.response, task);
    } else if (request.method == 'DELETE' && id != null) {
      final removed = tasks.remove(id);
      _writeJson(request.response, removed ?? <String, dynamic>{});
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async =>
      (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();

  void _writeJson(HttpResponse response, Map<String, dynamic> data) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
  }
}

class MemoryQueueStorage implements SyncQueueStorage {
  final Map<String, SyncQueueItem> _items = <String, SyncQueueItem>{};
  final Map<String, LocalRecord> _records = <String, LocalRecord>{};
  final StreamController<List<SyncQueueItem>> _changes =
      StreamController<List<SyncQueueItem>>.broadcast();
  final StreamController<String> _recordChanges =
      StreamController<String>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persistLocalChange(SyncQueueItem item) async {
    await upsert(item);
    if (item.operationType == SyncOperation.delete) {
      _records.remove(item.databaseKey);
    } else {
      final previous = _records[item.databaseKey];
      _records[item.databaseKey] = LocalRecord(
        id: item.id,
        entityName: item.entityName,
        data: item.payload,
        createdAt: previous?.createdAt ?? item.createdAt,
        updatedAt: item.updatedAt,
      );
    }
    _recordChanges.add(item.entityName);
  }

  @override
  Future<void> discardPendingCreate(String entityName, String id) async {
    await delete(entityName, id);
    _records.remove('$entityName::$id');
    _recordChanges.add(entityName);
  }

  @override
  Future<LocalRecord?> getRecord(String entityName, String id) async =>
      _records['$entityName::$id'];

  @override
  Future<List<LocalRecord>> getRecords(String entityName) async =>
      _records.values
          .where((record) => record.entityName == entityName)
          .toList();

  @override
  Stream<List<LocalRecord>> watchRecords(String entityName) async* {
    yield await getRecords(entityName);
    yield* _recordChanges.stream
        .where((changedEntity) => changedEntity == entityName)
        .asyncMap((_) => getRecords(entityName));
  }

  @override
  Future<void> upsert(SyncQueueItem item) async {
    _items[item.databaseKey] = item;
    _changes.add(await getAll());
  }

  @override
  Future<void> delete(String entityName, String id) async {
    _items.remove('$entityName::$id');
    _changes.add(await getAll());
  }

  @override
  Future<SyncQueueItem?> find(String entityName, String id) async =>
      _items['$entityName::$id'];

  @override
  Future<List<SyncQueueItem>> getAll() async => _items.values.toList();

  @override
  Future<List<SyncQueueItem>> getReadyToSync({required int maxRetries}) async =>
      _items.values
          .where(
            (item) => (item.status == SyncStatus.pending ||
                item.status == SyncStatus.failed ||
                item.status == SyncStatus.syncing),
          )
          .toList();

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
    final current = _items[syncing.databaseKey];
    if (current?.status != SyncStatus.syncing ||
        current?.updatedAt != syncing.updatedAt) {
      return;
    }
    await upsert(synced);
    final record = _records[syncing.databaseKey];
    if (record != null &&
        remoteData != null &&
        syncing.operationType != SyncOperation.delete) {
      _records[syncing.databaseKey] = LocalRecord(
        id: record.id,
        entityName: record.entityName,
        data: remoteData,
        createdAt: record.createdAt,
        updatedAt: synced.updatedAt,
      );
      _recordChanges.add(syncing.entityName);
    }
  }

  @override
  Future<void> clearSynced() async {
    _items.removeWhere((key, item) => item.status == SyncStatus.synced);
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
    await _recordChanges.close();
  }
}
