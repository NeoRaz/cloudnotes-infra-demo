#!/bin/bash
set -e

ENVIRONMENT=${1:-local}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY_PATH="$PROJECT_ROOT/k8s/overlays/${ENVIRONMENT}/second-step"
ENV_FILE="$PROJECT_ROOT/deployment/envs/${ENVIRONMENT}.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi

# Load env vars
set -a
source "$ENV_FILE"
set +a

echo "📁 Applying final overlay for client, nginx, queue worker, and ingress..."
kubectl apply -k "$OVERLAY_PATH"

echo "⏳ Waiting for deployments..."
kubectl wait --for=condition=available --timeout=300s deployment --all -n "$NAMESPACE" || exit 1

echo "✅ All deployments applied!"
kubectl get pods -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE"
