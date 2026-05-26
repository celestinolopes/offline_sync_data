import 'package:dio/dio.dart';

import 'sync_api_adapter.dart';

typedef ResourcePathBuilder = String Function(String entity, [String? id]);

/// A REST-oriented [SyncApiAdapter] using Dio.
///
/// Override [resourcePathBuilder] if the server does not expose endpoints as
/// `/<entity>` and `/<entity>/<id>`.
class DioSyncApiAdapter implements SyncApiAdapter {
  DioSyncApiAdapter({
    required Dio dio,
    ResourcePathBuilder? resourcePathBuilder,
  })  : _dio = dio,
        _resourcePathBuilder = resourcePathBuilder ?? _defaultResourcePath;

  final Dio _dio;
  final ResourcePathBuilder _resourcePathBuilder;

  static String _defaultResourcePath(String entity, [String? id]) {
    final base = '/${Uri.encodeComponent(entity)}';
    return id == null ? base : '$base/${Uri.encodeComponent(id)}';
  }

  @override
  Future<Map<String, dynamic>> create(
    String entity,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post<Object?>(
      _resourcePathBuilder(entity),
      data: data,
    );
    return _asMap(response.data);
  }

  @override
  Future<Map<String, dynamic>> update(
    String entity,
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.put<Object?>(
      _resourcePathBuilder(entity, id),
      data: data,
    );
    return _asMap(response.data);
  }

  @override
  Future<void> delete(String entity, String id) async {
    await _dio.delete<Object?>(_resourcePathBuilder(entity, id));
  }

  @override
  Future<Map<String, dynamic>?> fetchRemote(String entity, String id) async {
    try {
      final response = await _dio.get<Object?>(
        _resourcePathBuilder(entity, id),
      );
      return _asMap(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }
}
