import 'package:flutter/material.dart';
import 'package:offline_sync_data/offline_sync_data.dart';

/// Mostra se o app consegue alcançar a API (via [OfflineSyncEngine.watchConnectivity]).
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({required this.offlineSync, super.key});

  final OfflineSyncEngine offlineSync;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: offlineSync.watchConnectivity(),
      builder: (context, snapshot) {
        final online = snapshot.data;
        final (icon, message, color) = switch (online) {
          null => (
              Icons.wifi_find,
              'Verificando conexão…',
              Colors.grey,
            ),
          true => (
              Icons.cloud_done,
              'Online — fila enviada automaticamente',
              Colors.green,
            ),
          false => (
              Icons.cloud_off,
              'Offline — alterações ficam no SQLite',
              Colors.orange,
            ),
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
