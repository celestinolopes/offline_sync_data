import 'dart:convert';

/// A domain record persisted locally for offline reads.
class LocalRecord {
  const LocalRecord({
    required this.id,
    required this.entityName,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String entityName;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get databaseKey => '$entityName::$id';

  Map<String, Object?> toDatabaseMap() => <String, Object?>{
        'recordKey': databaseKey,
        'id': id,
        'entityName': entityName,
        'data': jsonEncode(data),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory LocalRecord.fromDatabaseMap(Map<String, Object?> map) {
    return LocalRecord(
      id: map['id']! as String,
      entityName: map['entityName']! as String,
      data: (jsonDecode(map['data']! as String) as Map).cast<String, dynamic>(),
      createdAt: DateTime.parse(map['createdAt']! as String),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
    );
  }
}
