#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:-}
APP_PORT=${2:-3080}
ACME_EMAIL=${3:-}

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: setup_caddy.sh <DOMAIN> [APP_PORT=3080] [ACME_EMAIL]" >&2
  exit 1
fi

sudo apt-get update -y
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

# Install Caddy (official repo with signed-by keyring)
if ! command -v caddy >/dev/null 2>&1; then
  sudo mkdir -p /usr/share/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  echo 'deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y caddy
fi

sudo mkdir -p /etc/caddy

TMP_CADDYFILE=$(mktemp)
{
  if [[ -n "$ACME_EMAIL" ]]; then
    echo "{"
    echo "  email $ACME_EMAIL"
    echo "}"
    echo
  fi
  echo "$DOMAIN {"
  echo "  encode gzip"
  echo "  reverse_proxy localhost:$APP_PORT"
  echo "}"
} > "$TMP_CADDYFILE"

sudo mv "$TMP_CADDYFILE" /etc/caddy/Caddyfile
sudo chown root:root /etc/caddy/Caddyfile
sudo chmod 0644 /etc/caddy/Caddyfile

sudo systemctl enable caddy
sudo systemctl restart caddy
echo "Caddy is configured for https://$DOMAIN (proxy to localhost:$APP_PORT)"


