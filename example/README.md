# Task example

Aplicativo Flutter minimo que demonstra `offline_sync_data` com uma entidade
`Task` e uma API REST local via [`json-server`](../json-server/README.md).

- Adicione, conclua ou remova tarefas enquanto o dispositivo estiver offline.
- A tela lista tarefas com estado `pending` ou `synced`.
- Toque no icone de sincronizacao para chamar `syncNow()`.
- Reative a internet para ver `startAutoSync()` processar a fila.
- A tela mostra `Online`/`Offline` usando `watchConnectivity()`.
- Feche e reabra o app offline: as tarefas continuam disponiveis no SQLite.

## API local (json-server)

Em um terminal:

```shell
cd example/json-server
npm install
npm start
```

A API fica em `http://localhost:3000/tasks`.

## Executar o app

Em outro terminal:

```shell
cd example
flutter run
```

URLs usadas por padrao:

| Plataforma | Base URL |
|------------|----------|
| iOS Simulator / macOS | `http://localhost:3000` |
| Android Emulator | `http://10.0.2.2:3000` |

Dispositivo fisico ou outra porta:

```shell
flutter run --dart-define=API_BASE_URL=http://<IP-DA-MAQUINA>:3000
```

## Estrutura do código (`lib/`)

```text
main.dart                 → entrada mínima
app.dart                  → MaterialApp
config/api_config.dart    → URL do json-server
sync/offline_sync_bootstrap.dart → cria OfflineSyncEngine
models/task.dart          → modelo Task
models/task_list_item.dart → Task + estado na fila
screens/task_list_screen.dart  → tela e ações save/sync
widgets/                  → banner online, resumo, tile da lista
```

## Fluxo local primeiro

1. `offlineSync.save(...)` grava a tarefa e sua operacao no SQLite.
2. A interface le `watchRecords('tasks')` e exibe itens pendentes e sincronizados,
   mesmo sem internet.
3. Com internet disponivel, `OfflineSyncManager` envia a operacao para o
   json-server local.
4. O servidor persiste o resultado em `json-server/db.json`.

Desligue a internet antes de criar uma tarefa para ve-la com status `pending`.
Religue a internet; o status muda para `synced` quando o envio terminar.

O envio so acontece enquanto o monitor reporta internet acessivel. Se a
internet cair durante o processo, a tarefa permanece `Pendente` e sera
reenviada automaticamente quando a ligacao voltar.
