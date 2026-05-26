import 'package:flutter/material.dart';

import 'app.dart';
import 'sync/offline_sync_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final offlineSync = await OfflineSyncBootstrap.create();

  runApp(TaskExampleApp(offlineSync: offlineSync));
}
