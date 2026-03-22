#!/bin/zsh
set -euo pipefail

export HOME="$HOME"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export ENABLE_BACKEND_ACCESS_CONTROL="false"
export LLM_PROVIDER="openai"
OPENCLAW_HOME="$HOME/.openclaw"
LOG_DIR="$OPENCLAW_HOME/logs"
SHIM="$OPENCLAW_HOME/bin/openclaw-cognee-llm-shim.py"
PYTHON_BIN="$HOME/.openclaw/cognee-venv/bin/python"
UVICORN_BIN="$HOME/.openclaw/cognee-venv/bin/uvicorn"

mkdir -p "$LOG_DIR"

GATEWAY_TOKEN=$(/usr/bin/python3 - <<'PY'
import json
import pathlib
import sys

path = pathlib.Path.home() / ".openclaw" / "openclaw.json"
try:
    root = json.loads(path.read_text())
except Exception:
    sys.exit(1)

token = str(root.get("gateway", {}).get("auth", {}).get("token", "") or "").strip()
if not token:
    sys.exit(1)
sys.stdout.write(token)
PY
)

if [[ -z "${GATEWAY_TOKEN}" ]]; then
  echo "Missing OpenClaw gateway token for Cognee." >&2
  exit 1
fi

export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
export OPENCLAW_COGNEE_GATEWAY_URL="http://127.0.0.1:18789/v1"
export OPENCLAW_COGNEE_GATEWAY_MODEL="openclaw:cognee"
export LLM_MODEL="gpt-4o-mini"
export LLM_ENDPOINT="http://127.0.0.1:18790/v1"
export LLM_API_KEY="openclaw-local"
export EMBEDDING_PROVIDER="fastembed"
export EMBEDDING_MODEL="BAAI/bge-small-en-v1.5"
export EMBEDDING_DIMENSIONS="384"
export PYTHONUNBUFFERED="1"

cleanup() {
  local code=$?
  if [[ -n "${SHIM_PID:-}" ]]; then
    kill "$SHIM_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${COGNEE_PID:-}" ]]; then
    kill "$COGNEE_PID" >/dev/null 2>&1 || true
  fi
  wait "${SHIM_PID:-}" >/dev/null 2>&1 || true
  wait "${COGNEE_PID:-}" >/dev/null 2>&1 || true
  exit "$code"
}

trap cleanup EXIT INT TERM

"$PYTHON_BIN" "$SHIM" >>"$LOG_DIR/cognee-shim.log" 2>>"$LOG_DIR/cognee-shim.err" &
SHIM_PID=$!

"$UVICORN_BIN" cognee.api.client:app --host 127.0.0.1 --port 8000 >>"$LOG_DIR/cognee.log" 2>>"$LOG_DIR/cognee.err" &
COGNEE_PID=$!

while true; do
  if ! kill -0 "$SHIM_PID" >/dev/null 2>&1; then
    wait "$SHIM_PID"
    exit $?
  fi
  if ! kill -0 "$COGNEE_PID" >/dev/null 2>&1; then
    wait "$COGNEE_PID"
    exit $?
  fi
  sleep 1
done