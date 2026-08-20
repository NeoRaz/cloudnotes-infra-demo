#!/bin/bash
set -e

echo "🧹 Resetting Minikube and Kubernetes environment..."

if minikube status >/dev/null 2>&1; then
  echo "🛑 Stopping Minikube..."
  minikube stop
  echo "🗑️ Deleting Minikube cluster..."
  minikube delete  --all --purge
else
  echo "✅ Minikube is already clean."
fi

echo "🧽 Cleanup complete!"
