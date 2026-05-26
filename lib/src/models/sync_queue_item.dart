import 'dart:convert';

/// The operation that must be applied to the remote API.
enum SyncOperation { create, update, delete }

/// The current lifecycle state of a queued operation.
enum SyncStatus { pending, syncing, synced, failed }

/// A persisted local action waiting to be reconciled with the remote API.
class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityName,
    required this.operationType,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  factory SyncQueueItem.pending({
    required String id,
    required String entityName,
    required SyncOperation operationType,
    required Map<String, dynamic> payload,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now().toUtc();
    return SyncQueueItem(
      id: id,
      entityName: entityName,
      operationType: operationType,
      payload: payload,
      status: SyncStatus.pending,
      retryCount: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// The record identifier understood by the API.
  final String id;

  /// The remote collection/resource name, for example `tasks`.
  final String entityName;
  final SyncOperation operationType;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;

  /// Internal stable key; IDs may repeat across different entity types.
  String get databaseKey => '$entityName::$id';

  SyncQueueItem copyWith({
    String? id,
    String? entityName,
    SyncOperation? operationType,
    Map<String, dynamic>? payload,
    SyncStatus? status,
    int? retryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityName: entityName ?? this.entityName,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, Object?> toDatabaseMap() => <String, Object?>{
        'queueKey': databaseKey,
        'id': id,
        'entityName': entityName,
        'operationType': operationType.name,
        'payload': jsonEncode(payload),
        'status': status.name,
        'retryCount': retryCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastError': lastError,
      };

  factory SyncQueueItem.fromDatabaseMap(Map<String, Object?> map) {
    return SyncQueueItem(
      id: map['id']! as String,
      entityName: map['entityName']! as String,
      operationType: SyncOperation.values.byName(
        map['operationType']! as String,
      ),
      payload: (jsonDecode(map['payload']! as String) as Map)
          .cast<String, dynamic>(),
      status: SyncStatus.values.byName(map['status']! as String),
      retryCount: map['retryCount']! as int,
      createdAt: DateTime.parse(map['createdAt']! as String),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
      lastError: map['lastError'] as String?,
    );
  }
}
