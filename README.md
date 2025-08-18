## Open UI Chat on Google Cloud Run — One-command Deploy

This repo provides configuration-as-code to deploy the upstream open-ui-chat container (UI+API) to Google Cloud Run using a single command.

### What you get
- Cloud Run deploy script (`deploy.sh`) that sources `.env`, generates any missing secrets, and deploys with best-practice flags
- Environment template (`.env.example`) with all required/optional variables
- `.gitignore` that keeps secrets (like `.env`) out of version control

### Prerequisites
- Google Cloud SDK installed and authenticated (`gcloud auth login`)
- A GCP project selected with billing enabled

### Quickstart
1) Copy and edit your environment

```bash
cp .env.example .env
# Edit .env and set at least PROJECT_ID, MONGO_URI, MEILI_HOST, RAG_API_URL
```

2) Deploy

```bash
bash ./deploy.sh
```

On success, the script outputs the Cloud Run service URL. Optionally set `CUSTOM_DOMAIN` in `.env` to auto-create a domain mapping.

### Variables (from `.env`)

- Core service
  - `PROJECT_ID` (required), `REGION` (default `europe-west1`), `SERVICE_NAME` (default `open-ui-chat`)
  - `IMAGE` (default `ghcr.io/danny-avila/open-ui-chat-dev:latest`)
  - `CPU` (default `2`), `MEMORY` (default `2Gi`), `ALLOW_UNAUTHENTICATED` (default `true`)
  - `AR_REPO`/`AR_IMAGE_NAME` for Artifact Registry mirroring (default: same as `SERVICE_NAME`)
- Connectivity
  - `HOST=0.0.0.0` (always set), `MONGO_URI`, `MEILI_HOST`, `RAG_API_URL`
  - Optional: `VPC_CONNECTOR`, `VPC_EGRESS` (`all-traffic` or `private-ranges-only`)
- Secrets (generated if empty)
  - `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CREDS_KEY` (64 hex), `CREDS_IV` (32 hex)
  - Optional: `MEILI_MASTER_KEY`
- Auth flags (open access example)
  - `ALLOW_EMAIL_LOGIN=false`, `ALLOW_REGISTRATION=false`, `ALLOW_SOCIAL_LOGIN=false`, `ALLOW_SOCIAL_REGISTRATION=false`
- Provider keys (optional)
  - `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`
- Domain mapping (optional)
  - `MAP_DOMAIN=true`, `CUSTOM_DOMAIN=chat.example.com`

### Notes
- Cloud Run sets `PORT` automatically; `deploy.sh` sets `HOST=0.0.0.0` so the container listens correctly
- External services (MongoDB Atlas, Meilisearch, RAG API, Cloud SQL/pgvector) must be network-reachable by Cloud Run
- Keep `.env` out of git; this repo ships a `.gitignore` entry for it

### Logs and verification

```bash
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format json | jq '.status.url'
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
  --limit=100 --format=json | jq '.[].jsonPayload.message? // .[].textPayload?'
```

### MCP (optional)
If you need MCP over SSE, configure a reachable public endpoint and expose it to open-ui-chat via environment variables or a proxy service. Cloud Run cannot mount arbitrary config files.


