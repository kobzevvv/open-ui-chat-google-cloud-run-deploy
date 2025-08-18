#!/usr/bin/env bash
set -euo pipefail

DOMAIN=${1:-}
APP_PORT=${2:-3080}
ACME_EMAIL=${3:-}

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: setup_nginx.sh <DOMAIN> [APP_PORT=3080] [ACME_EMAIL]" >&2
  exit 1
fi

sudo apt-get update -y
sudo apt-get install -y nginx

cat > /tmp/open-ui-chat.nginx.conf <<'CONF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location / {
        proxy_pass http://127.0.0.1:APP_PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
CONF

sudo sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" /tmp/open-ui-chat.nginx.conf
sudo sed -i "s/APP_PORT_PLACEHOLDER/${APP_PORT}/g" /tmp/open-ui-chat.nginx.conf
sudo mv /tmp/open-ui-chat.nginx.conf /etc/nginx/sites-available/open-ui-chat

sudo ln -sf /etc/nginx/sites-available/open-ui-chat /etc/nginx/sites-enabled/open-ui-chat
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

if [[ -n "$ACME_EMAIL" ]]; then
  # Install certbot and obtain cert via nginx plugin
  sudo apt-get install -y certbot python3-certbot-nginx
  sudo certbot --nginx -d "$DOMAIN" -m "$ACME_EMAIL" --agree-tos --redirect --non-interactive || true
fi

echo "Nginx configured for http://${DOMAIN} -> http://127.0.0.1:${APP_PORT}"


