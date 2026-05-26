# JSON Server API

API REST falsa para o exemplo `offline_sync_engine`.

## Local

```sh
cd example/json-server
npm install
npm start
```

Nao passe argumentos ao `npm start` (por exemplo `npm start -- --port 3000`).
A porta padrao e `3000`; para outra porta: `PORT=4000 npm start`.

A API fica disponivel em `http://localhost:3000/tasks`.

## Render

Configure um Web Service com:

```text
Build Command: npm ci
Start Command: npm start
```

Para persistir os dados entre reinicios e novos deploys, adicione um
Persistent Disk montado em `/var/data` e defina a variavel:

```text
DB_PATH=/var/data/db.json
```

O primeiro inicio copia o `db.json` inicial para o disco; nos proximos
inicios, o arquivo persistido e reutilizado.
