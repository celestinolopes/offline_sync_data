/// Reconciles local pending data with a representation already on the server.
abstract class ConflictResolver {
  Future<Map<String, dynamic>> resolve({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  });
}

/// Always submits the local pending representation.
class LocalWinsConflictResolver implements ConflictResolver {
  const LocalWinsConflictResolver();

  @override
  Future<Map<String, dynamic>> resolve({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) async =>
      localData;
}

/// Discards local changes when a remote representation is present.
class RemoteWinsConflictResolver implements ConflictResolver {
  const RemoteWinsConflictResolver();

  @override
  Future<Map<String, dynamic>> resolve({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) async =>
      remoteData;
}

/// Selects the object with the latest `updatedAt` ISO-8601 timestamp.
///
/// If either timestamp is missing or invalid, local changes are preferred so
/// an offline user action is not silently discarded.
class LastWriteWinsConflictResolver implements ConflictResolver {
  const LastWriteWinsConflictResolver({this.updatedAtField = 'updatedAt'});

  final String updatedAtField;

  @override
  Future<Map<String, dynamic>> resolve({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) async {
    final localTimestamp = _parseTimestamp(localData[updatedAtField]);
    final remoteTimestamp = _parseTimestamp(remoteData[updatedAtField]);
    if (localTimestamp == null || remoteTimestamp == null) return localData;
    return remoteTimestamp.isAfter(localTimestamp) ? remoteData : localData;
  }

  DateTime? _parseTimestamp(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
