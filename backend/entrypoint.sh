#!/bin/sh
set -e

if [ "${RUN_MIGRATIONS_ON_START:-true}" = "true" ]; then
  echo "Running database migrations..."
  alembic upgrade head
fi

# When running on Cloud Run, PORT is passed in the environment (default 8080).
# If PORT is set and the command is the default uvicorn command, bind to PORT.
if [ -n "$PORT" ] && [ "$1" = "uvicorn" ] && [ "$2" = "app.main:app" ]; then
  echo "Starting uvicorn on port $PORT..."
  exec uvicorn app.main:app --host 0.0.0.0 --port "$PORT"
fi

exec "$@"
