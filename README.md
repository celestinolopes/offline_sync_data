# offline_sync_data

**English** · [Português](README.md)

Offline-first synchronization engine for Flutter. Operations performed without
network access are persisted in SQLite and sent to the server automatically when
connectivity returns.

## Features

- Persistent local queue with `sqflite`, compatible with Android and iOS.
- Persistent local documents for offline reads and app restarts.
- Real internet detection with `internet_connection_checker_plus`.
- Connectivity stream with sync on reconnect and periodic checks for platform
  transitions that are not always delivered promptly.
- Decoupled API via `SyncApiAdapter`, with an optional REST adapter based on `dio`.
- Observable states per item (`pending`, `syncing`, `synced`, `failed`), global
  queue, online/offline connectivity, and multiple entities in one engine.
- Configurable retry with linear backoff (`retryCount * 2` seconds by default).
- Conflict resolution: local-wins, remote-wins, and last-write-wins.
- Ready entry point for optional `workmanager` integration.

The engine persists both **sync operations** and local JSON documents, so the app
can keep reading data after a restart with no connection.

## Architecture

![Offline-first architecture for offline_sync_data](doc/images/arquitetura.png)

The flow is local-first: `save()` persists the document and queue entry in SQLite
before any remote call. When the stream confirms internet is available,
`OfflineSyncManager` processes the queue through `SyncApiAdapter`; with
`DioSyncApiAdapter`, operations reach a REST API or the example `json-server`.
Without internet, items stay local with `pending` status.

## Installation

Add to your app `pubspec.yaml`:

```yaml
dependencies:
  offline_sync_data: ^0.1.0
  dio: ^5.8.0
```

For local development:

```yaml
dependencies:
  offline_sync_data:
    path: ../offline_sync_data # your repository folder name
```

## Quick start

Implement your API contract or use `DioSyncApiAdapter`:

```dart
final adapter = DioSyncApiAdapter(
  dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
);

final offlineSync = OfflineSyncEngine(
  apiAdapter: adapter,
  conflictResolver: const LastWriteWinsConflictResolver(),
  options: const OfflineSyncOptions(maxRetries: 3),
);

await offlineSync.initialize();
offlineSync.syncManager.startAutoSync();
```

Save locally before relying on the network:

```dart
await offlineSync.save(
  entity: 'tasks',
  id: task.id,
  data: task.toJson(),
  operation: SyncOperation.create,
);
```

The same method accepts `SyncOperation.update` and `SyncOperation.delete`.
A pending create that was never attempted, followed by an update, becomes a
single create with the new payload; followed by a delete, it is removed from the
queue. After an attempt, deletes are synced explicitly because the server may
have accepted the create before the response was lost.

Read local records, including offline:

```dart
final records = await offlineSync.getRecords('tasks');
final tasks = records.map((record) => Task.fromJson(record.data)).toList();

offlineSync.watchRecords('tasks').listen((records) {
  // Rebuild the UI from persisted local documents.
});
```

`create` and `update` write the local document and queue entry in one
transaction. `delete` removes the local document immediately and keeps a pending
operation for API deletion.

Force a sync manually:

```dart
await offlineSync.syncManager.syncNow();
```

## Sync state, connectivity, and pending data

The engine separates two concepts:

| Concept | What it represents | How to observe |
| ------- | ------------------ | -------------- |
| **Local document** | App data persisted for offline reads (`LocalRecord`) | `getRecords`, `watchRecords` |
| **Queue item** | Operation not yet reconciled with the server (`SyncQueueItem`) | `watchQueue`, `watchItemStatus` |

A record can exist locally **without** a queue entry: it is already synced (or
never needed sending). While a queue item exists with a status other than
`synced`, data is still pending reconciliation with the API.

### Per-operation states (`SyncStatus`)

| State | Typical UI meaning |
| ----- | ------------------ |
| `pending` | Waiting for network or the next sync run |
| `syncing` | Upload in progress |
| `synced` | Accepted by the API this run (kept in queue for observation) |
| `failed` | Last attempt failed; `lastError` has the reason; auto-retry when online |

### Online vs offline

Call `startAutoSync()` on startup (as in quick start), then use
`watchConnectivity()`:

```dart
await offlineSync.syncManager.startAutoSync();

offlineSync.watchConnectivity().listen((online) {
  if (online) {
    // Reachable internet: auto-sync sends the queue
  } else {
    // Offline: save() still writes locally
  }
});
```

In `StreamBuilder`, `snapshot.data` is `null` until the first event (e.g. show
"Checking connection…"), as in `example/`.

The monitor checks **real internet** (HTTP), not just Wi‑Fi. For local
`DioSyncApiAdapter` development, point `InternetConnectionMonitor` at your API
(see Retry and conflicts).

### Full queue and per-record status

```dart
offlineSync.watchQueue().listen((List<SyncQueueItem> items) {
  final pending = items.where((i) => i.status != SyncStatus.synced);
  final synced = items.where((i) => i.status == SyncStatus.synced);
});

offlineSync.watchItemStatus(task.id, entity: 'tasks').listen((SyncStatus status) {
  switch (status) {
    case SyncStatus.pending:
    case SyncStatus.syncing:
    case SyncStatus.failed:
      // still pending
    case SyncStatus.synced:
      // reconciled with server
  }
});
```

### Pending vs synced in a list

Combine **local documents** with the **queue**:

```dart
StreamBuilder<List<LocalRecord>>(
  stream: offlineSync.watchRecords('tasks'),
  builder: (context, recordsSnapshot) {
    return StreamBuilder<List<SyncQueueItem>>(
      stream: offlineSync.watchQueue(),
      builder: (context, queueSnapshot) {
        final records = recordsSnapshot.data ?? [];
        final queue = queueSnapshot.data ?? [];

        for (final record in records) {
          final matches = queue.where(
            (i) => i.id == record.id && i.entityName == 'tasks',
          );
          final queueItem = matches.isEmpty ? null : matches.last;

          final isSynced = queueItem == null ||
              queueItem.status == SyncStatus.synced;

          // isSynced == true  -> show as "Synced"
          // isSynced == false -> show pending/syncing/failed
        }
        return const SizedBox.shrink();
      },
    );
  },
);
```

Summary:

- **Synced**: present in `watchRecords`, and no queue item **or** item is `synced`.
- **Pending**: queue item with `pending`, `syncing`, or `failed`.
- **Counters**: filter `watchQueue()` or merge records with the queue (see example).

One-off reads:

```dart
final records = await offlineSync.getRecords('tasks');
final one = await offlineSync.getRecord('tasks', taskId);
```

Prefer `watchItemStatus` or filter the latest `watchQueue()` snapshot by
`entityName` and `id`.

### Clear queue history

`synced` items stay in the queue so you can observe success:

```dart
await offlineSync.clearSynced();
```

## Multiple collections (data types)

Use the `entity` parameter for each data type. One `OfflineSyncEngine` and one
`SyncApiAdapter` handle every collection; each `(entity, id)` pair has its own
SQLite key (`entityName::id`).

### Same API, different routes

One server (`https://api.example.com`) with different paths. Set `baseUrl` on
`Dio` and use a different `entity` per type:

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

final offlineSync = OfflineSyncEngine(
  apiAdapter: DioSyncApiAdapter(dio: dio),
);

await offlineSync.save(
  entity: 'tasks',
  id: task.id,
  data: task.toJson(),
  operation: SyncOperation.create,
);

await offlineSync.save(
  entity: 'notes',
  id: note.id,
  data: note.toJson(),
  operation: SyncOperation.create,
);

await offlineSync.save(
  entity: 'customers',
  id: customer.id,
  data: customer.toJson(),
  operation: SyncOperation.update,
);
```

Default `DioSyncApiAdapter` routing:

| `entity` | create | update / delete | remote fetch (conflicts) |
| -------- | ------ | --------------- | ------------------------ |
| `tasks` | `POST /tasks` | `PUT` or `DELETE /tasks/:id` | `GET /tasks/:id` |
| `notes` | `POST /notes` | `PUT` or `DELETE /notes/:id` | `GET /notes/:id` |
| `customers` | `POST /customers` | `PUT` or `DELETE /customers/:id` | `GET /customers/:id` |

All calls share the same host (`Dio` `baseUrl`); only the path changes.

### Routes that are not `/<entity>/<id>`

Map each `entity` in `resourcePathBuilder`:

```dart
final adapter = DioSyncApiAdapter(
  dio: dio,
  resourcePathBuilder: (entity, [id]) => switch (entity) {
    'tasks' =>
      id == null ? '/api/v2/todos' : '/api/v2/todos/${Uri.encodeComponent(id)}',
    'notes' => id == null ? '/notes' : '/notes/${Uri.encodeComponent(id)}',
    'profile' => '/v1/me',
    _ => id == null
        ? '/${Uri.encodeComponent(entity)}'
        : '/${Uri.encodeComponent(entity)}/${Uri.encodeComponent(id)}',
  },
);

final offlineSync = OfflineSyncEngine(apiAdapter: adapter);
```

### Query-string routes (`tasks?id=2`)

Return the path **including the query** from `resourcePathBuilder`:

```dart
String pathWithQuery(String entity, [String? id]) {
  final base = '/${Uri.encodeComponent(entity)}';
  if (id == null) return base;
  return '$base?id=${Uri.encodeQueryComponent(id)}';
}

final adapter = DioSyncApiAdapter(
  dio: dio,
  resourcePathBuilder: (entity, [id]) => switch (entity) {
    'tasks' || 'notes' => pathWithQuery(entity, id),
    _ => id == null
        ? '/${Uri.encodeComponent(entity)}'
        : '/${Uri.encodeComponent(entity)}/${Uri.encodeComponent(id)}',
  },
);
```

With `entity: 'tasks'` and `id: '2'`:

| Operation | Method and URL (relative to `baseUrl`) |
| --------- | -------------------------------------- |
| create | `POST /tasks` (JSON body; no `id` in URL) |
| update | `PUT /tasks?id=2` |
| delete | `DELETE /tasks?id=2` |
| fetch | `GET /tasks?id=2` |

The `id` in `save()` and SQLite is unchanged; only the remote URL format differs.

### Local reads and queue per type

```dart
final tasks = await offlineSync.getRecords('tasks');
final notes = await offlineSync.getRecords('notes');

offlineSync.watchRecords('tasks').listen((_) { /* tasks UI */ });
offlineSync.watchRecords('notes').listen((_) { /* notes UI */ });
```

The sync queue is **global**. Filter in UI or business logic:

```dart
offlineSync.watchQueue().listen((items) {
  final taskQueue = items.where((i) => i.entityName == 'tasks');
  final noteQueue = items.where((i) => i.entityName == 'notes');
});
```

### Send order and storage

- **Storage:** `tasks` and `notes` do not collide (`entityName::id`).
- **Sync:** one item at a time, ordered by `createdAt`, no type priority.
- **Connectivity:** one probe endpoint (e.g. `GET /tasks`) usually covers the
  whole queue on the same host.

### APIs on different hosts

Implement a custom `SyncApiAdapter` that picks URL or HTTP client per `entity`
in `create`, `update`, `delete`, and `fetchRemote`.

## Custom adapter

The package does not fix URLs or backend shape:

```dart
class TasksApiAdapter implements SyncApiAdapter {
  @override
  Future<Map<String, dynamic>> create(
    String entity,
    Map<String, dynamic> data,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> update(
    String entity,
    String id,
    Map<String, dynamic> data,
  ) async => throw UnimplementedError();

  @override
  Future<void> delete(String entity, String id) async {}

  @override
  Future<Map<String, dynamic>?> fetchRemote(String entity, String id) async =>
      null;
}
```

`DioSyncApiAdapter` defaults to `POST /<entity>`, `PUT /<entity>/<id>`,
`DELETE /<entity>/<id>`, and `GET /<entity>/<id>`. Use `resourcePathBuilder` to
customize paths.

## Retry and conflicts

Failures set `failed`, store `lastError`, and increment `retryCount`. `maxRetries`
limits attempts per run; `failed` items retry when the network returns or on
`syncNow()`. Backoff restarts each run:

```text
delay = attemptInCurrentRun * retryBaseDelay
```

Default two-second base → 2 s, 4 s, … Configure:

```dart
const OfflineSyncOptions(
  maxRetries: 5,
  retryBaseDelay: Duration(seconds: 2),
  connectivityCheckInterval: Duration(milliseconds: 500),
);
```

`startAutoSync()` listens to `InternetConnectionMonitor.onConnectivityChanged`
([`internet_connection_checker_plus`](https://pub.dev/packages/internet_connection_checker_plus))
and optionally polls on `connectivityCheckInterval`. Set it to `null` to rely
only on the monitor stream. When internet returns, retry waits are interrupted
and sync runs immediately.

Before each remote call, connectivity is rechecked. If the link drops mid-request,
the item returns to `pending` without consuming an attempt.

Default probes hit global endpoints. To reflect **your API** availability:

```dart
OfflineSyncEngine.withDependencies(
  apiAdapter: adapter,
  storage: storage,
  connectivity: InternetConnectionMonitor(
    connection: InternetConnection.createInstance(
      useDefaultOptions: false,
      customCheckOptions: [
        InternetCheckOption(
          uri: Uri.parse('http://10.0.2.2:3000/tasks'),
          timeout: Duration(milliseconds: 500),
          responseStatusFn: (response) =>
              response.statusCode >= 200 && response.statusCode < 300,
        ),
      ],
    ),
  ),
);
```

`syncing` items at the start of a run are recovered (app killed mid-upload). On
`create`, `fetchRemote` runs before retry to avoid duplicate `POST` after a lost
response.

For updates with a `ConflictResolver`, the remote record is fetched first:

```dart
const LocalWinsConflictResolver();
const RemoteWinsConflictResolver();
const LastWriteWinsConflictResolver(); // compares updatedAt
```

## Background sync

No mandatory background dependency. Use `workmanager` (or similar) and call:

```dart
final scheduler = BackgroundSyncScheduler(offlineSync.syncManager);
await scheduler.execute();
```

The background callback must initialize Flutter and the engine first.

## Project layout

```text
lib/
  offline_sync_data.dart
  src/
    background/
    connectivity/
    conflict/
    core/
    database/
    models/
    sync/
example/
  lib/main.dart
test/
```

See `example/lib/` for `watchConnectivity()`, `watchRecords` + `watchQueue()`,
and multiple entities. Local API: `example/json-server` (`npm install` &&
`npm start`).

## Author

**Celestino Lopes**

<p align="left">
  <a href="https://github.com/celestinolopes" target="_blank" rel="noopener noreferrer" title="GitHub">
    <img
      src="https://github.com/celestinolopes.png?size=100"
      width="100"
      height="100"
      alt="Celestino Lopes on GitHub"
    />
  </a>
  &nbsp;&nbsp;
  <a href="https://www.linkedin.com/in/celestino-lopes-0817001a0/" target="_blank" rel="noopener noreferrer" title="LinkedIn">
    <img
      src="https://img.shields.io/badge/LinkedIn-Celestino_Lopes-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white"
      height="28"
      alt="LinkedIn — Celestino Lopes"
    />
  </a>
</p>

- GitHub: [github.com/celestinolopes](https://github.com/celestinolopes)
- LinkedIn: [linkedin.com/in/celestino-lopes-0817001a0](https://www.linkedin.com/in/celestino-lopes-0817001a0/)
