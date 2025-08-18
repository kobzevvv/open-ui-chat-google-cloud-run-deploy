#!/usr/bin/env bash
set -euo pipefail

# Load .env
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
else
  echo "ERROR: .env not found. Copy .env.sample to .env and fill the required values." >&2
  exit 1
fi

command -v gcloud >/dev/null 2>&1 || { echo "ERROR: gcloud is required" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl is required" >&2; exit 1; }

# Defaults
PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-europe-west1}
SERVICE_NAME=${SERVICE_NAME:-open-ui-chat}
IMAGE=${IMAGE:-ghcr.io/danny-avila/librechat-dev:latest}
# Artifact Registry mirror settings (override in .env if desired)
AR_REPO=${AR_REPO:-$SERVICE_NAME}
AR_IMAGE_NAME=${AR_IMAGE_NAME:-$SERVICE_NAME}
CPU=${CPU:-2}
MEMORY=${MEMORY:-2Gi}
ALLOW_UNAUTHENTICATED=${ALLOW_UNAUTHENTICATED:-true}
TIMEOUT=${TIMEOUT:-600}

HOST=${HOST:-0.0.0.0}

MONGO_URI=${MONGO_URI:-}
MEILI_HOST=${MEILI_HOST:-}
RAG_API_URL=${RAG_API_URL:-}
MEILI_MASTER_KEY=${MEILI_MASTER_KEY:-}

# Secrets (generate if unset)
JWT_SECRET=${JWT_SECRET:-}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET:-}
CREDS_KEY=${CREDS_KEY:-}
CREDS_IV=${CREDS_IV:-}

ALLOW_EMAIL_LOGIN=${ALLOW_EMAIL_LOGIN:-false}
ALLOW_REGISTRATION=${ALLOW_REGISTRATION:-false}
ALLOW_SOCIAL_LOGIN=${ALLOW_SOCIAL_LOGIN:-false}
ALLOW_SOCIAL_REGISTRATION=${ALLOW_SOCIAL_REGISTRATION:-false}

OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}

VPC_CONNECTOR=${VPC_CONNECTOR:-}
VPC_EGRESS=${VPC_EGRESS:-}

MAP_DOMAIN=${MAP_DOMAIN:-false}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN:-}

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: PROJECT_ID is required in .env" >&2
  exit 1
fi

# Generate ephemeral secrets if missing (does not write back to .env)
if [[ -z "$JWT_SECRET" ]]; then JWT_SECRET=$(openssl rand -hex 32); fi
if [[ -z "$JWT_REFRESH_SECRET" ]]; then JWT_REFRESH_SECRET=$(openssl rand -hex 32); fi
if [[ -z "$CREDS_KEY" ]]; then CREDS_KEY=$(openssl rand -hex 32); fi
if [[ -z "$CREDS_IV" ]]; then CREDS_IV=$(openssl rand -hex 16); fi

# Env vars helper
add_env() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    args+=(--set-env-vars "${name}=${value}")
  fi
}

# Function to (re)build deploy args
build_args() {
  args=(
    gcloud run deploy "$SERVICE_NAME"
    --image="$IMAGE"
    --project="$PROJECT_ID"
    --region="$REGION"
    --platform=managed
    --execution-environment=gen2
    --cpu="$CPU" --memory="$MEMORY" --timeout="$TIMEOUT"
  )

  if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
    args+=(--allow-unauthenticated)
  fi

  # Required runtime/envs
  add_env HOST "$HOST"
  add_env JWT_SECRET "$JWT_SECRET"
  add_env JWT_REFRESH_SECRET "$JWT_REFRESH_SECRET"
  add_env CREDS_KEY "$CREDS_KEY"
  add_env CREDS_IV "$CREDS_IV"

  # Connectivity
  add_env MONGO_URI "$MONGO_URI"
  add_env MEILI_HOST "$MEILI_HOST"
  add_env RAG_API_URL "$RAG_API_URL"
  add_env MEILI_MASTER_KEY "$MEILI_MASTER_KEY"

  # Auth flags
  add_env ALLOW_EMAIL_LOGIN "$ALLOW_EMAIL_LOGIN"
  add_env ALLOW_REGISTRATION "$ALLOW_REGISTRATION"
  add_env ALLOW_SOCIAL_LOGIN "$ALLOW_SOCIAL_LOGIN"
  add_env ALLOW_SOCIAL_REGISTRATION "$ALLOW_SOCIAL_REGISTRATION"

  # Provider keys (optional)
  add_env OPENAI_API_KEY "$OPENAI_API_KEY"
  add_env ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
  add_env GOOGLE_API_KEY "$GOOGLE_API_KEY"

  # Networking (optional)
  if [[ -n "$VPC_CONNECTOR" ]]; then
    args+=(--vpc-connector "$VPC_CONNECTOR")
    if [[ -n "$VPC_EGRESS" ]]; then
      args+=(--vpc-egress "$VPC_EGRESS")
    fi
  fi
}

echo "Deploying $SERVICE_NAME to Cloud Run in project $PROJECT_ID ($REGION)..."
build_args
"${args[@]}" || {
  echo "Primary deploy failed. Attempting to mirror image to Artifact Registry and retry..." >&2

  # Enable required services
  gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com --project "$PROJECT_ID"

  # Create repo if missing
  gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$AR_REPO" --repository-format=docker --location="$REGION" --project="$PROJECT_ID"

  # Run Cloud Build mirror job
  MIRROR_DEST="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${AR_IMAGE_NAME}:latest"
  gcloud builds submit --config cloudbuild.mirror.yaml --project "$PROJECT_ID" --substitutions _SRC="$IMAGE",_DEST="$MIRROR_DEST" .

  # Swap image and retry deploy
  IMAGE="$MIRROR_DEST"
  echo "Retrying deploy with $IMAGE..."
  build_args
  "${args[@]}"
}

echo "Describe service URL:"
if command -v jq >/dev/null 2>&1; then
  gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format json | jq -r '.status.url'
else
  gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format='value(status.url)'
fi

if [[ "$MAP_DOMAIN" == "true" && -n "$CUSTOM_DOMAIN" ]]; then
  echo "Creating domain mapping for $CUSTOM_DOMAIN (may already exist)..."
  gcloud run domain-mappings create \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --service="$SERVICE_NAME" \
    --domain="$CUSTOM_DOMAIN" || true
  echo "Complete the DNS steps shown in the Cloud Console if prompted."
fi

echo "Done."


