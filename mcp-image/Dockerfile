FROM ghcr.io/open-webui/open-webui:main

# Copy default MCP connectors (edit mcp_connectors.json in this repo before build)
COPY mcp_connectors.json /app/mcp_connectors.json

# Seed MCP connectors on startup if not already present
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh \
  && bash -lc 'set -e; found=""; for f in /app/start.sh /start.sh /app/backend/start.sh; do if [[ -f "$f" ]]; then echo "[mcp-image] Found start script: $f"; sed -i "1i /usr/local/bin/bootstrap.sh || true" "$f" && found="yes"; fi; done; if [[ -z "$found" ]]; then echo "[mcp-image] No known start script found; bootstrap will not auto-run"; fi'

# No change to exposed ports / entrypoint — we only prepend our bootstrap


