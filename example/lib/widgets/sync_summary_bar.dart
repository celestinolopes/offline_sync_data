import 'package:flutter/material.dart';

import '../models/task_list_item.dart';

/// Contador de tarefas pendentes vs sincronizadas.
class SyncSummaryBar extends StatelessWidget {
  const SyncSummaryBar({required this.items, super.key});

  final List<TaskListItem> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((item) => !item.isSynced).length;
    final synced = items.where((item) => item.isSynced).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _Chip(
            label: '$pending pendentes',
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          _Chip(
            label: '$synced sincronizadas',
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
