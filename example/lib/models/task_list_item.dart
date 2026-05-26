import 'package:offline_sync_data/offline_sync_data.dart';

import 'task.dart';

/// Une o documento local ([Task]) com o estado na fila de sincronização.
class TaskListItem {
  const TaskListItem({required this.task, this.queueItem});

  final Task task;
  final SyncQueueItem? queueItem;

  bool get isSynced =>
      queueItem == null || queueItem!.status == SyncStatus.synced;

  SyncStatus? get syncStatus => queueItem?.status;

  String? get lastError => queueItem?.lastError;

  /// Documentos locais + fila global → lista para a UI.
  static List<TaskListItem> merge({
    required List<LocalRecord> records,
    required List<SyncQueueItem> queue,
    required String entityName,
  }) {
    return records.map((record) {
      final task = Task.fromJson(record.data);
      final queueItem = _findQueueItem(
        taskId: task.id,
        entityName: entityName,
        queue: queue,
      );
      return TaskListItem(task: task, queueItem: queueItem);
    }).toList();
  }

  static SyncQueueItem? _findQueueItem({
    required String taskId,
    required String entityName,
    required List<SyncQueueItem> queue,
  }) {
    final matches = queue.where(
      (item) => item.id == taskId && item.entityName == entityName,
    );
    return matches.isEmpty ? null : matches.last;
  }
}
