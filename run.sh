#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$DIR:$PYTHONPATH"

if [ -x "$DIR/.venv/bin/python" ]; then
  exec "$DIR/.venv/bin/python" -m surrey_finder.cli "$@"
elif [ -x "$DIR/.venv/bin/python3" ]; then
  exec "$DIR/.venv/bin/python3" -m surrey_finder.cli "$@"
else
  exec python3 -m surrey_finder.cli "$@"
fi
