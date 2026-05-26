/// Bridge between the queue and an application's remote API.
abstract class SyncApiAdapter {
  Future<Map<String, dynamic>> create(String entity, Map<String, dynamic> data);

  Future<Map<String, dynamic>> update(
    String entity,
    String id,
    Map<String, dynamic> data,
  );

  Future<void> delete(String entity, String id);

  Future<Map<String, dynamic>?> fetchRemote(String entity, String id);
}
