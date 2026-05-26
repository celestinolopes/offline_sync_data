import 'package:dio/dio.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:offline_sync_data/offline_sync_data.dart';

import '../config/api_config.dart';

/// Cria e inicializa o [OfflineSyncEngine] para o exemplo de tarefas.
class OfflineSyncBootstrap {
  static Future<OfflineSyncEngine> create() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: 300),
        sendTimeout: const Duration(milliseconds: 300),
        receiveTimeout: const Duration(milliseconds: 300),
      ),
    );

    final engine = OfflineSyncEngine(
      apiAdapter: DioSyncApiAdapter(dio: dio),
      connectivity: InternetConnectionMonitor(
        connection: InternetConnection.createInstance(
          useDefaultOptions: false,
          checkInterval: const Duration(milliseconds: 500),
          customCheckOptions: <InternetCheckOption>[
            InternetCheckOption(
              uri: Uri.parse(ApiConfig.tasksEndpoint),
              timeout: const Duration(milliseconds: 500),
              responseStatusFn: (response) =>
                  response.statusCode >= 200 && response.statusCode < 300,
            ),
          ],
        ),
      ),
      conflictResolver: const LastWriteWinsConflictResolver(),
      options: const OfflineSyncOptions(
        retryBaseDelay: Duration(milliseconds: 100),
        connectivityCheckInterval: Duration(milliseconds: 500),
        connectivityProbeMinIntervalWhileOnline: Duration(milliseconds: 500),
      ),
    );

    await engine.initialize();
    await engine.syncManager.startAutoSync();
    return engine;
  }
}
