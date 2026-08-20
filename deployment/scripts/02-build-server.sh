#!/bin/bash
set -e

ENVIRONMENT=${1:-local}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/deployment/envs/${ENVIRONMENT}.env"
APP_REPO_ROOT="${APP_REPO_ROOT:-$PROJECT_ROOT/src}"

FIRST_STEP_OVERLAY_PATH="$PROJECT_ROOT/k8s/overlays/${ENVIRONMENT}/first-step"
SECOND_STEP_OVERLAY_PATH="$PROJECT_ROOT/k8s/overlays/${ENVIRONMENT}/second-step"

echo "🚀 Starting CloudNotes deployment ($ENVIRONMENT)..."

IMAGE_TAG="${IMAGE_TAG:-}"
SED_INPLACE="sed -i"
if [[ "$(uname)" == "Darwin" ]]; then
  SED_INPLACE="sed -i ''"
fi

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
SERVER_DIR="$APP_REPO_ROOT/server"
AI_DIR="$APP_REPO_ROOT/ai"

# Normalize AI flag so "true"/"TRUE"/"True" all work.
ENABLE_AI_CLEAN="$(printf '%s' "${ENABLE_AI:-false}" | tr '[:upper:]' '[:lower:]')"

# Ensure namespace exists
echo "📁 Ensuring namespace '$NAMESPACE' exists..."
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"


if [ "$ENVIRONMENT" == "local" ]; then
  echo "🐳 Setting Docker to Minikube daemon..."
  eval $(minikube docker-env --shell bash)

  # Generate a unique image tag
  IMAGE_TAG="local-$(date +%s)"
  echo "🏷️ Using image tag: $IMAGE_TAG"

  echo "🛠️ Building local Docker image: cloudnotes-server:$IMAGE_TAG"
  docker build -t cloudnotes-server:$IMAGE_TAG "$SERVER_DIR"

  if [ "$ENABLE_AI_CLEAN" = "true" ]; then
    echo "🛠️ Building local Docker image: cloudnotes-ai:$IMAGE_TAG"
    docker build -t cloudnotes-ai:$IMAGE_TAG "$AI_DIR"
  else
    echo "⏭️ ENABLE_AI is false. Skipping local AI image build."
  fi



  echo "🧩 Patching Kustomize overlay (first-step) with new server image..."
  (cd "$FIRST_STEP_OVERLAY_PATH" && kustomize edit set image cloudnotes-server=cloudnotes-server:$IMAGE_TAG)
  
  echo "🧩 Patching Kustomize overlay (second-step) with new server image..."
  (cd "$SECOND_STEP_OVERLAY_PATH" && kustomize edit set image cloudnotes-server=cloudnotes-server:$IMAGE_TAG)

  if [ "$ENABLE_AI_CLEAN" = "true" ]; then
    echo "🧩 Patching Kustomize overlay (first-step) with new AI image..."
    (cd "$FIRST_STEP_OVERLAY_PATH" && kustomize edit set image cloudnotes-ai=cloudnotes-ai:$IMAGE_TAG)

    echo "🧩 Patching Kustomize overlay (second-step) with new AI image..."
    (cd "$SECOND_STEP_OVERLAY_PATH" && kustomize edit set image cloudnotes-ai=cloudnotes-ai:$IMAGE_TAG)
  else
    echo "⏭️ ENABLE_AI is false. Skipping AI image patching."
  fi



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
    echo "☁️ Building and pushing Docker Hub image for production..."

    # Build image on the host daemon
    echo "🛠️ Building server Docker image: cloudnotes-server:$IMAGE_TAG"
    docker build -t cloudnotes-server:$IMAGE_TAG "$SERVER_DIR"

    if [ "$ENABLE_AI_CLEAN" = "true" ]; then
      echo "🛠️ Building AI Docker image: cloudnotes-ai:$IMAGE_TAG"
      docker build -t cloudnotes-ai:$IMAGE_TAG "$AI_DIR"
    else
      echo "⏭️ ENABLE_AI is false. Skipping AI Docker image build."
    fi

    # Ensure Docker credentials exist
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then
      echo "❌ Missing Docker credentials in environment."
      exit 1
    fi

    echo "📤 Tagging and pushing server image to Docker Hub..."
    docker tag cloudnotes-server:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-server:$IMAGE_TAG"
    docker tag cloudnotes-server:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-server:latest"
    docker push "$DOCKER_USERNAME/cloudnotes-server:$IMAGE_TAG"
    docker push "$DOCKER_USERNAME/cloudnotes-server:latest"

    if [ "$ENABLE_AI_CLEAN" = "true" ]; then
      echo "📤 Tagging and pushing AI image to Docker Hub..."
      docker tag cloudnotes-ai:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-ai:$IMAGE_TAG"
      docker tag cloudnotes-ai:$IMAGE_TAG "$DOCKER_USERNAME/cloudnotes-ai:latest"
      docker push "$DOCKER_USERNAME/cloudnotes-ai:$IMAGE_TAG"
      docker push "$DOCKER_USERNAME/cloudnotes-ai:latest"
    else
      echo "⏭️ ENABLE_AI is false. Skipping AI image push."
    fi
  else
    echo "⏭️ SKIP_BUILD is enabled. Skipping Docker build and push."
  fi

  # Ensure Docker credentials exist for registry secret
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then
    echo "❌ Missing Docker credentials in environment."
    exit 1
  fi

  echo "🔑 Creating Docker registry secret..."
  kubectl -n "$NAMESPACE" delete secret regcred --ignore-not-found
  kubectl -n "$NAMESPACE" create secret docker-registry regcred \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --docker-email="$DOCKER_EMAIL"

  echo "🧩 Patching Kustomize overlay (first-step) with new server image..."
  (cd "$FIRST_STEP_OVERLAY_PATH" && \
    kustomize edit set image cloudnotes-server="$DOCKER_USERNAME/cloudnotes-server:$IMAGE_TAG")

  echo "🧩 Patching Kustomize overlay (second-step) with new server image..."
  (cd "$SECOND_STEP_OVERLAY_PATH" && \
    kustomize edit set image cloudnotes-server="$DOCKER_USERNAME/cloudnotes-server:$IMAGE_TAG")

  if [ "$ENABLE_AI_CLEAN" = "true" ]; then
    echo "🧩 Patching Kustomize overlay (first-step) with new AI image..."
    (cd "$FIRST_STEP_OVERLAY_PATH" && \
      kustomize edit set image cloudnotes-ai="$DOCKER_USERNAME/cloudnotes-ai:$IMAGE_TAG")

    echo "🧩 Patching Kustomize overlay (second-step) with new AI image..."
    (cd "$SECOND_STEP_OVERLAY_PATH" && \
      kustomize edit set image cloudnotes-ai="$DOCKER_USERNAME/cloudnotes-ai:$IMAGE_TAG")
  else
    echo "⏭️ ENABLE_AI is false. Skipping AI image patching."
  fi
fi


# Add APP_KEY to env file if missing
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "PLACE_HOLDER" ]; then
  echo "🔑 Generating Laravel APP_KEY..."
  # Generate 32 random bytes and encode to base64
  RANDOM_KEY=$(openssl rand -base64 32)

  APP_KEY="base64:$RANDOM_KEY"

  # Update .env file cleanly
  $SED_INPLACE "s|^APP_KEY=.*|APP_KEY=$APP_KEY|" "$ENV_FILE"
  echo "✅ Generated APP_KEY: $APP_KEY"
else
  echo "✅ APP_KEY already set: $APP_KEY"
fi

# Recreate environment secret
echo "🔐 Creating environment secret..."
kubectl -n "$NAMESPACE" delete secret cloudnotes-env --ignore-not-found
kubectl -n "$NAMESPACE" create secret generic cloudnotes-env \
  --from-literal=APP_NAME="CloudNotesServer" \
  --from-literal=APP_KEY="$APP_KEY" \
  --from-literal=APP_ENV="$APP_ENV" \
  --from-literal=APP_DEBUG="$APP_DEBUG" \
  --from-literal=APP_URL="$APP_URL" \
  --from-literal=APP_TIMEZONE="$APP_TIMEZONE" \
  --from-literal=APP_LOCALE="$APP_LOCALE" \
  --from-literal=APP_FALLBACK_LOCALE="$APP_FALLBACK_LOCALE" \
  --from-literal=APP_FAKER_LOCALE="$APP_FAKER_LOCALE" \
  \
  --from-literal=DB_CONNECTION="$DB_CONNECTION" \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_PORT="$DB_PORT" \
  --from-literal=DB_DATABASE="$DB_DATABASE" \
  --from-literal=DB_USERNAME="$DB_USERNAME" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  \
  --from-literal=PG_DB_CONNECTION="$PG_DB_CONNECTION" \
  --from-literal=PG_HOST="$PG_HOST" \
  --from-literal=PG_PORT="$PG_PORT" \
  --from-literal=PG_DATABASE="$PG_DATABASE" \
  --from-literal=PG_USERNAME="$PG_USERNAME" \
  --from-literal=PG_PASSWORD="$PG_PASSWORD" \
  \
  --from-literal=REDIS_CLIENT="$REDIS_CLIENT" \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="$REDIS_PORT" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  \
  --from-literal=QUEUE_CONNECTION="$QUEUE_CONNECTION" \
  --from-literal=CACHE_STORE="$CACHE_STORE" \
  --from-literal=CACHE_PREFIX="$CACHE_PREFIX" \
  --from-literal=SESSION_DRIVER="$SESSION_DRIVER" \
  --from-literal=SESSION_LIFETIME="$SESSION_LIFETIME" \
  --from-literal=SESSION_ENCRYPT="$SESSION_ENCRYPT" \
  --from-literal=SESSION_PATH="$SESSION_PATH" \
  --from-literal=SESSION_DOMAIN="$SESSION_DOMAIN" \
  --from-literal=FILESYSTEM_DISK="$FILESYSTEM_DISK" \
  \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
  --from-literal=AWS_BUCKET="$AWS_BUCKET" \
  --from-literal=AWS_ENDPOINT="$AWS_ENDPOINT" \
  --from-literal=AWS_USE_PATH_STYLE_ENDPOINT="$AWS_USE_PATH_STYLE_ENDPOINT" \
  --from-literal=AWS_URL="$AWS_URL" \
  \
  --from-literal=MAIL_MAILER="$MAIL_MAILER" \
  --from-literal=MAIL_HOST="$MAIL_HOST" \
  --from-literal=MAIL_PORT="$MAIL_PORT" \
  --from-literal=MAIL_USERNAME="$MAIL_USERNAME" \
  --from-literal=MAIL_PASSWORD="$MAIL_PASSWORD" \
  --from-literal=MAIL_ENCRYPTION="$MAIL_ENCRYPTION" \
  --from-literal=MAIL_FROM_ADDRESS="$MAIL_FROM_ADDRESS" \
  --from-literal=MAIL_FROM_NAME="$MAIL_FROM_NAME" \
  \
  --from-literal=BREVO_API_KEY="$BREVO_API_KEY" \
  --from-literal=AI_MODEL_PROVIDER="$AI_MODEL_PROVIDER" \
  --from-literal=AI_ENDPOINT_URL="$AI_ENDPOINT_URL" \
  --from-literal=AI_API_KEY="$AI_API_KEY" \
  --from-literal=AI_LLM_MODEL="$AI_LLM_MODEL" \
  --from-literal=AI_EMBEDDING_MODEL="$AI_EMBEDDING_MODEL" \
  --from-literal=AI_EMBEDDING_DIM="$AI_EMBEDDING_DIM" \
  --from-literal=HUGGINGFACE_TOKENIZER="$HUGGINGFACE_TOKENIZER" \
  \
  --from-literal=ENABLE_AI="$ENABLE_AI" \
  --from-literal=AI_SERVICE_URL="$AI_SERVICE_URL" \
  \
  --from-literal=LOG_CHANNEL="$LOG_CHANNEL" \
  --from-literal=PASSPORT_PRIVATE_KEY="$PASSPORT_PRIVATE_KEY" \
  --from-literal=PASSPORT_PUBLIC_KEY="$PASSPORT_PUBLIC_KEY"

echo "📦 Applying Kustomize overlay for $ENVIRONMENT..."
kubectl apply -k "$FIRST_STEP_OVERLAY_PATH"

if [ "$ENABLE_AI_CLEAN" != "true" ]; then
  echo "🔕 ENABLE_AI is false. Scaling deployment/ai to 0."
  kubectl scale deployment/ai -n "$NAMESPACE" --replicas=0 || true
fi

echo "⏳ Waiting for dependencies to be ready..."
kubectl wait --for=condition=ready pod -l app=mysql -n "$NAMESPACE" --timeout=300s || exit 1
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=300s || exit 1
kubectl wait --for=condition=ready pod -l app=redis -n "$NAMESPACE" --timeout=300s || exit 1

echo "⏳ Waiting for server pod to be ready..."
kubectl rollout status deployment/server -n "$NAMESPACE" --timeout=300s

POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=server --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "✅ Found server pod: $POD_NAME"

echo "✅ Running Laravel Artisan commands..."
kubectl exec -n "$NAMESPACE" deployment/server -c php-fpm -- php artisan config:clear
kubectl exec -n "$NAMESPACE" deployment/server -c php-fpm -- php artisan route:clear
kubectl exec -n "$NAMESPACE" deployment/server -c php-fpm -- php artisan migrate --seed --force
kubectl exec -n "$NAMESPACE" deployment/server -c php-fpm -- php artisan cache:clear
kubectl exec -n "$NAMESPACE" deployment/server -c php-fpm -- php artisan config:cache

echo "✅ Deployment complete for $ENVIRONMENT."
