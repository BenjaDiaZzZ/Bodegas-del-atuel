#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f api/openapi.yaml ]]; then
  echo "ERROR: falta api/openapi.yaml." >&2
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "ERROR: se requiere Node.js y npx para ejecutar Prism." >&2
  exit 1
fi

PORT="${PRISM_PORT:-4010}"

echo "Mock disponible en http://127.0.0.1:${PORT}"
echo "Probá con: curl http://127.0.0.1:${PORT}/salud"

exec npx --yes @stoplight/prism-cli@5 mock api/openapi.yaml --port "$PORT"
