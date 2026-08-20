#!/bin/bash
set -e

echo "🔥 Checking Minikube status..."

if ! minikube status >/dev/null 2>&1; then
  echo "🚀 Starting Minikube..."
  minikube start --driver=docker --memory=4096 --cpus=2
else
  echo "✅ Minikube already running."
fi

echo "🐳 Configuring Docker environment for Minikube..."
eval $(minikube docker-env)

if ! minikube addons list | grep -q "ingress: enabled"; then
  echo "🌐 Enabling ingress addon..."
  minikube addons enable ingress
else
  echo "✅ Ingress already enabled."
fi

if ! minikube addons list | grep -q "ingress-dns: enabled"; then
  echo "🌍 Enabling ingress-dns addon..."
  minikube addons enable ingress-dns || true
else
  echo "✅ Ingress DNS already enabled."
fi

echo "✨ Minikube setup complete."
