#!/bin/bash
set -e

ENVIRONMENT=${1:-local}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/deployment/envs/${ENVIRONMENT}.env"
OVERLAY_PATH="$PROJECT_ROOT/k8s/overlays/${ENVIRONMENT}/second-step"
APP_REPO_ROOT="${APP_REPO_ROOT:-$PROJECT_ROOT/src}"

# Prefer externally provided IMAGE_TAG (from CI), then fall back later if empty.
IMAGE_TAG="${IMAGE_TAG:-}"

echo "🚀 Starting second step of CloudNotes deployment ($ENVIRONMENT)..."

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi

# Load environment variables
set -a
source "$ENV_FILE"
set +a

resolve_path() {
  local candidate="$1"
  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
  else
    (cd "$PROJECT_ROOT" && printf '%s\n' "$(cd "$candidate" && pwd)")
  fi
}

APP_REPO_ROOT="$(resolve_path "$APP_REPO_ROOT")"
CLIENT_DIR="$APP_REPO_ROOT/client"

echo "🧩 Generating runtime client config map..."
TMP_CONFIG="$(mktemp)"
cat > "$TMP_CONFIG" <<EOF
window.__APP_CONFIG__ = {
  REACT_APP_API_BASE_URL: "${REACT_APP_API_BASE_URL}",
  REACT_APP_CLIENT_ID: "${REACT_APP_CLIENT_ID}",
  REACT_APP_CLIENT_SECRET: "${REACT_APP_CLIENT_SECRET}",
  REACT_APP_SECRET_KEY: "${REACT_APP_SECRET_KEY}",
  REACT_APP_ENABLE_AI: "${REACT_APP_ENABLE_AI}"
};
EOF

kubectl -n "$NAMESPACE" create configmap client-runtime-config \
  --from-file=config.js="$TMP_CONFIG" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f "$TMP_CONFIG"

if [ "$ENVIRONMENT" == "local" ]; then
  echo "🐳 Setting Docker to Minikube daemon..."
  eval $(minikube docker-env --shell bash)

  # Generate a unique image tag
  IMAGE_TAG="local-$(date +%s)"
  echo "🏷️ Using image tag: $IMAGE_TAG"

  echo "📦 Building local client Docker image: cloudnotes-client:$IMAGE_TAG"
  docker build \
    -t cloudnotes-client:$IMAGE_TAG \
    --build-arg REACT_APP_ENV="$REACT_APP_NODE_ENV" \
    --build-arg REACT_APP_API_BASE_URL="$REACT_APP_API_BASE_URL" \
    --build-arg REACT_APP_CLIENT_ID="$REACT_APP_CLIENT_ID" \
    --build-arg REACT_APP_CLIENT_SECRET="$REACT_APP_CLIENT_SECRET" \
    --build-arg REACT_APP_SECRET_KEY="$REACT_APP_SECRET_KEY" \
    --build-arg REACT_APP_ENABLE_AI="$REACT_APP_ENABLE_AI" \
    "$CLIENT_DIR"

  echo "🧩 Patching Kustomize overlay (second-step) with new client image..."
  (cd "$OVERLAY_PATH" && kustomize edit set image cloudnotes-client=cloudnotes-client:$IMAGE_TAG)

else
  # Use provided image tag or generate a unique image tag
  if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null)
    if [ -z "$IMAGE_TAG" ]; then
      echo "❌ Could not get git hash. Make sure this is a git repository."
      exit 1
    fi
  fi
  echo "🏷️ Using image tag: $IMAGE_TAG"

  if [ "$SKIP_BUILD" != "true" ]; then
    echo "📦 Building client Docker image for production: cloudnotes-client:$IMAGE_TAG"
    docker build \
      -t cloudnotes-client:$IMAGE_TAG \
      --build-arg REACT_APP_ENV="$REACT_APP_NODE_ENV" \
      --build-arg REACT_APP_API_BASE_URL="$REACT_APP_API_BASE_URL" \
      --build-arg REACT_APP_CLIENT_ID="$REACT_APP_CLIENT_ID" \
      --build-arg REACT_APP_CLIENT_SECRET="$REACT_APP_CLIENT_SECRET" \
      --build-arg REACT_APP_SECRET_KEY="$REACT_APP_SECRET_KEY" \
      --build-arg REACT_APP_ENABLE_AI="$REACT_APP_ENABLE_AI" \
      "$CLIENT_DIR"

    # Ensure Docker credentials exist
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then
      echo "❌ Missing Docker credentials in environment."
      exit 1
    fi

    echo "📤 Tagging and pushing client image to Docker Hub..."
    docker tag cloudnotes-client:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-client:$IMAGE_TAG"
    docker tag cloudnotes-client:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-client:latest"
    docker push "$DOCKER_USERNAME/cloudnotes-client:$IMAGE_TAG"
    docker push "$DOCKER_USERNAME/cloudnotes-client:latest"
  else
    echo "⏭️ SKIP_BUILD is enabled. Skipping Docker build and push."
  fi

  # Ensure Docker credentials exist for registry secret
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then
    echo "❌ Missing Docker credentials in environment."
    exit 1
  fi

  echo "🔐 Creating or updating Docker registry secret in Kubernetes..."
  kubectl -n "$NAMESPACE" delete secret regcred --ignore-not-found
  kubectl -n "$NAMESPACE" create secret docker-registry regcred \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --docker-email="$DOCKER_EMAIL"

  echo "🧩 Patching Kustomize overlay (second-step) with new client image..."
  (cd "$OVERLAY_PATH" && \
    kustomize edit set image cloudnotes-client="$DOCKER_USERNAME/cloudnotes-client:$IMAGE_TAG")
fi

echo "✅ Client image build and patch complete."
