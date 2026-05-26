import 'package:flutter/material.dart';
import 'package:offline_sync_data/offline_sync_data.dart';

import '../config/api_config.dart';
import '../models/task.dart';
import '../models/task_list_item.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/sync_summary_bar.dart';
import '../widgets/task_list_tile.dart';

/// Tela principal: lê SQLite local e cruza com a fila de sync.
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({
    required this.offlineSync,
    super.key,
  });

  final OfflineSyncEngine offlineSync;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final _titleController = TextEditingController();

  OfflineSyncEngine get _sync => widget.offlineSync;

  @override
  void dispose() {
    _titleController.dispose();
    _sync.dispose();
    super.dispose();
  }

  Future<void> _save(Task task, SyncOperation operation) {
    return _sync.save(
      entity: ApiConfig.entityName,
      id: task.id,
      data: task.toJson(),
      operation: operation,
    );
  }

  Future<void> _addTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    _titleController.clear();
    await _save(Task.newLocal(title: title), SyncOperation.create);
  }

  Future<void> _toggle(Task task) {
    return _save(
      task.copyWith(completed: !task.completed),
      SyncOperation.update,
    );
  }

  Future<void> _remove(Task task) {
    return _save(task, SyncOperation.delete);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarefas offline-first'),
        actions: [
          IconButton(
            tooltip: 'Enviar fila agora (syncNow)',
            onPressed: _sync.syncManager.syncNow,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TaskInput(
            controller: _titleController,
            onSubmit: _addTask,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'API: ${ApiConfig.tasksEndpoint}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ConnectivityBanner(offlineSync: _sync),
          Expanded(child: _TaskListView(sync: _sync, onToggle: _toggle, onDelete: _remove)),
        ],
      ),
    );
  }
}

/// Combina [watchRecords] + [watchQueue] — padrão recomendado na documentação.
class _TaskListView extends StatelessWidget {
  const _TaskListView({
    required this.sync,
    required this.onToggle,
    required this.onDelete,
  });

  final OfflineSyncEngine sync;
  final ValueChanged<Task> onToggle;
  final ValueChanged<Task> onDelete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocalRecord>>(
      stream: sync.watchRecords(ApiConfig.entityName),
      initialData: const [],
      builder: (context, recordsSnapshot) {
        return StreamBuilder<List<SyncQueueItem>>(
          stream: sync.watchQueue(),
          initialData: const [],
          builder: (context, queueSnapshot) {
            final items = TaskListItem.merge(
              records: recordsSnapshot.data ?? const [],
              queue: queueSnapshot.data ?? const [],
              entityName: ApiConfig.entityName,
            );

            if (items.isEmpty) {
              return const Center(
                child: Text('Nenhuma tarefa. Crie uma acima.'),
              );
            }

            return Column(
              children: [
                SyncSummaryBar(items: items),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return TaskListTile(
                        item: item,
                        onToggle: onToggle,
                        onDelete: onDelete,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TaskInput extends StatelessWidget {
  const _TaskInput({
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'Nova tarefa',
          hintText: 'Grava no SQLite e enfileira create',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            onPressed: onSubmit,
            icon: const Icon(Icons.add),
          ),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}
