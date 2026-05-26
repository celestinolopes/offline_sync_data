import 'package:flutter/material.dart';
import 'package:offline_sync_data/offline_sync_data.dart';

import '../models/task.dart';
import '../models/task_list_item.dart';

class TaskListTile extends StatelessWidget {
  const TaskListTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final TaskListItem item;
  final ValueChanged<Task> onToggle;
  final ValueChanged<Task> onDelete;

  @override
  Widget build(BuildContext context) {
    final status = _SyncStatusPresentation.from(item);

    return ListTile(
      leading: Checkbox(
        value: item.task.completed,
        onChanged: (_) => onToggle(item.task),
      ),
      title: Text(item.task.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (status.errorMessage != null)
            Text(
              status.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDelete(item.task),
      ),
    );
  }
}

class _SyncStatusPresentation {
  const _SyncStatusPresentation({
    required this.label,
    required this.color,
    this.errorMessage,
  });

  final String label;
  final Color color;
  final String? errorMessage;

  factory _SyncStatusPresentation.from(TaskListItem item) {
    return switch (item.syncStatus) {
      null || SyncStatus.synced => const _SyncStatusPresentation(
          label: 'Sincronizada',
          color: Colors.green,
        ),
      SyncStatus.syncing => const _SyncStatusPresentation(
          label: 'Enviando…',
          color: Colors.orange,
        ),
      SyncStatus.pending => const _SyncStatusPresentation(
          label: 'Pendente',
          color: Colors.orange,
        ),
      SyncStatus.failed => _SyncStatusPresentation(
          label: 'Falhou — nova tentativa automática',
          color: Colors.red,
          errorMessage: item.lastError,
        ),
    };
  }
}
