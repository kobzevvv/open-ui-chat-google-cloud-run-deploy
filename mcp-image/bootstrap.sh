#!/usr/bin/env bash
set -euo pipefail

# Location where Open WebUI persists its data. This may change between versions; adjust if needed.
DATA_DIR="/app/backend/data"
CONNECTORS_FILE="$DATA_DIR/mcp_connectors.json"

# Allow override via env
DEFAULT_MCP_CONNECTORS_JSON=${DEFAULT_MCP_CONNECTORS_JSON:-}

echo "[bootstrap] Starting MCP seeding..."

mkdir -p "$DATA_DIR"

if [[ -s "$CONNECTORS_FILE" ]]; then
  echo "[bootstrap] Existing MCP connectors found at $CONNECTORS_FILE; skipping seed."
  exit 0
fi

if [[ -n "$DEFAULT_MCP_CONNECTORS_JSON" ]]; then
  echo "$DEFAULT_MCP_CONNECTORS_JSON" > "$CONNECTORS_FILE"
  echo "[bootstrap] Seeded MCP connectors from DEFAULT_MCP_CONNECTORS_JSON env."
  exit 0
fi

# Fallback: use the baked file if present
if [[ -f "/app/mcp_connectors.json" ]]; then
  cp /app/mcp_connectors.json "$CONNECTORS_FILE"
  echo "[bootstrap] Seeded MCP connectors from baked /app/mcp_connectors.json."
  exit 0
fi

echo "[bootstrap] No default MCP connectors provided; nothing to seed."


