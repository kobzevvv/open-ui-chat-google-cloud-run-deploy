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
IMAGE=${IMAGE:-ghcr.io/open-webui/open-webui:main}
# Open WebUI listens on 8080 by default
CONTAINER_PORT=${CONTAINER_PORT:-8080}
# Artifact Registry mirror settings (override in .env if desired)
AR_REPO=${AR_REPO:-$SERVICE_NAME}
AR_IMAGE_NAME=${AR_IMAGE_NAME:-$SERVICE_NAME}
CPU=${CPU:-2}
MEMORY=${MEMORY:-2Gi}
ALLOW_UNAUTHENTICATED=${ALLOW_UNAUTHENTICATED:-true}
TIMEOUT=${TIMEOUT:-600}
# Optional: run only diagnostics without deploying when set to "true"
DIAG_ONLY=${DIAG_ONLY:-false}

HOST=${HOST:-0.0.0.0}

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

:

# Env vars helper
add_env() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    args+=(--set-env-vars "${name}=${value}")
  fi
}

# Diagnostics for networking setup (VPC connector / egress)
diagnose_connectivity() {
  echo "--- Connectivity Diagnostics ---"
  echo "Project: $PROJECT_ID  Region: $REGION"
  # Show whether required services are enabled (best-effort)
  echo "APIs enabled (subset):"
  gcloud services list --enabled --project "$PROJECT_ID" \
    --format='value(config.name)' | grep -E 'run.googleapis.com|vpcaccess.googleapis.com|compute.googleapis.com' || true

  if [[ -n "$VPC_CONNECTOR" ]]; then
    echo "VPC Connector: $VPC_CONNECTOR"
    gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR" \
      --region="$REGION" --project="$PROJECT_ID" \
      --format='table(name,region,network,ipCidrRange,state,minInstances,maxInstances,minThroughput,maxThroughput)' || {
        echo "WARN: Failed to describe VPC connector '$VPC_CONNECTOR'" >&2
      }
  else
    echo "VPC Connector: (not set)"
  fi

  echo "Cloud Router NATs in $REGION (if any):"
  gcloud compute routers list --regions="$REGION" --project="$PROJECT_ID" \
    --format='table(name,region,network)' || true
  for router in $(gcloud compute routers list --regions="$REGION" --project "$PROJECT_ID" --format='value(name)' 2>/dev/null); do
    echo "- NATs on router: $router"
    gcloud compute routers nats list --router="$router" --router-region="$REGION" --project "$PROJECT_ID" \
      --format='table(name,natIpAllocateOption,natIps)' || true
  done
  echo "--- End Diagnostics ---"
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
    --port="$CONTAINER_PORT"
    --cpu="$CPU" --memory="$MEMORY" --timeout="$TIMEOUT"
  )

  if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
    args+=(--allow-unauthenticated)
  fi

  # Required runtime/envs
  add_env HOST "$HOST"

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

diagnose_connectivity

if [[ "$DIAG_ONLY" == "true" ]]; then
  echo "Diagnostics only; skipping deploy (set DIAG_ONLY=false to deploy)."
  exit 0
fi

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


