#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-europe-west1}
ZONE=${ZONE:-europe-west1-b}
VM_NAME=${VM_NAME:-open-ui-chat-vm}
MACHINE_TYPE=${MACHINE_TYPE:-e2-standard-2}
DOMAIN=${DOMAIN:-}
ACME_EMAIL=${ACME_EMAIL:-}

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: set PROJECT_ID env var or export in .env before running" >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

echo "Creating VM $VM_NAME in $ZONE..."
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --tags=open-ui-chat,https-server,http-server \
  --scopes=storage-ro || true

echo "Opening ports 80, 443, and 3080..."
gcloud compute firewall-rules create open-ui-chat-allow-3080 \
  --allow tcp:3080 --target-tags=open-ui-chat --source-ranges=0.0.0.0/0 --quiet || true
gcloud compute firewall-rules create open-ui-chat-allow-80 \
  --allow tcp:80 --target-tags=https-server,http-server --source-ranges=0.0.0.0/0 --quiet || true
gcloud compute firewall-rules create open-ui-chat-allow-443 \
  --allow tcp:443 --target-tags=https-server,http-server --source-ranges=0.0.0.0/0 --quiet || true

echo "Copying files via gcloud compute scp..."
gcloud compute scp --recurse vm "${VM_NAME}:~/open-ui-chat-vm" --zone="$ZONE" --quiet
gcloud compute scp .env "${VM_NAME}:~/open-ui-chat-vm/.env" --zone="$ZONE" --quiet || true

echo "Installing Docker and starting stack via gcloud compute ssh..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command='bash -lc "cd ~/open-ui-chat-vm && sudo bash ./setup.sh && sudo docker compose up -d"' --quiet

if [[ -n "$DOMAIN" ]]; then
  echo "Installing and configuring Caddy for $DOMAIN..."
  gcloud compute scp vm/setup_caddy.sh "${VM_NAME}:~/open-ui-chat-vm/setup_caddy.sh" --zone="$ZONE" --quiet || true
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command='bash -lc "cd ~/open-ui-chat-vm && sudo bash ./setup_caddy.sh '"$DOMAIN"' 3080 '"$ACME_EMAIL"'"' --quiet
  VM_IP=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
  echo "Point your DNS A record for $DOMAIN to: $VM_IP"
fi

echo "Service should be reachable at: http://${VM_IP}:3080"



