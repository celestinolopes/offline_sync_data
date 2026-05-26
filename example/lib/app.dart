import 'package:flutter/material.dart';
import 'package:offline_sync_data/offline_sync_data.dart';

import 'screens/task_list_screen.dart';

class TaskExampleApp extends StatelessWidget {
  const TaskExampleApp({required this.offlineSync, super.key});

  final OfflineSyncEngine offlineSync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_sync_data — exemplo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: TaskListScreen(offlineSync: offlineSync),
    );
  }
}
