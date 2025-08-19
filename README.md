## Open WebUI on Google Cloud Run — One-command Deploy

This repo provides configuration-as-code to deploy the upstream Open WebUI container to Google Cloud Run using a single command.

### What you get
- Cloud Run deploy script (`deploy.sh`) that sources `.env` and deploys with best-practice flags
- Inline `.env` example in this README; copy it to `.env` and edit
- `.gitignore` that keeps secrets (like `.env`) and backups (e.g. `.env.bak`) out of version control

### Prerequisites
- Google Cloud SDK installed and authenticated (`gcloud auth login`)
- A GCP project selected with billing enabled

### Quickstart
1) Copy and edit your environment (working example)

```bash
cat > .env <<'EOF'
PROJECT_ID=YOUR_GCP_PROJECT_ID
REGION=europe-west1
SERVICE_NAME=open-ui-chat

# Open WebUI image and port
IMAGE=ghcr.io/open-webui/open-webui:main
CONTAINER_PORT=8080

# Recommended runtime settings
CPU=2
MEMORY=2Gi
ALLOW_UNAUTHENTICATED=true

# Ensure the container listens on all interfaces
HOST=0.0.0.0
EOF
```

2) Deploy

```bash
bash ./deploy.sh
# Print service URL
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format='value(status.url)'
```

3) Logs

```bash
gcloud run services logs read "$SERVICE_NAME" --region "$REGION" --limit 100
```

On success, the script outputs the Cloud Run service URL. Optionally set `CUSTOM_DOMAIN` in `.env` to auto-create a domain mapping.

### Variables (from `.env`)

- Core service
  - `PROJECT_ID` (required), `REGION` (default `europe-west1`), `SERVICE_NAME` (default `open-ui-chat`)
  - `IMAGE` (default `ghcr.io/open-webui/open-webui:main`)
  - `CPU` (default `2`), `MEMORY` (default `2Gi`), `ALLOW_UNAUTHENTICATED` (default `true`)
  - `AR_REPO`/`AR_IMAGE_NAME` for Artifact Registry mirroring (default: same as `SERVICE_NAME`)
- Connectivity
  - `HOST=0.0.0.0` (always set)
  - Optional: `VPC_CONNECTOR`, `VPC_EGRESS` (`all-traffic` or `private-ranges-only`)
- Provider keys (optional)
  - `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`
- Domain mapping (optional)
  - `MAP_DOMAIN=true`, `CUSTOM_DOMAIN=chat.example.com`

### Notes
- Cloud Run sets `PORT` automatically; `deploy.sh` sets `HOST=0.0.0.0` so the container listens correctly
- Open WebUI stores data on local container storage; on Cloud Run that storage is ephemeral between revisions
- Keep `.env` out of git; this repo ships a `.gitignore` entry for it (and ignores backups like `.env.bak`). Backups are not read by the deploy script.

### Logs and verification

```bash
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format json | jq '.status.url'
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
  --limit=100 --format=json | jq '.[].jsonPayload.message? // .[].textPayload?'
```

### References
- Upstream project: [open-webui/open-webui](https://github.com/open-webui/open-webui)


