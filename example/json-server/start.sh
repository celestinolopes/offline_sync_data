#!/bin/sh
set -eu

cd "$(dirname "$0")"

db_file="${DB_PATH:-db.json}"

# A mounted Render disk starts empty; seed it from the repository once.
if [ "$db_file" != "db.json" ] && [ ! -f "$db_file" ]; then
  cp db.json "$db_file"
fi

json_server="./node_modules/.bin/json-server"
if [ ! -x "$json_server" ]; then
  echo "json-server not found. Run: npm install" >&2
  exit 1
fi

exec "$json_server" "$db_file" --host 0.0.0.0 --port "${PORT:-3000}"
