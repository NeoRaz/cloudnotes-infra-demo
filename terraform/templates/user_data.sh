#!/bin/bash
# user_data.sh - Bootstrapping K3s, Ingress Nginx, and Cert-Manager on Ubuntu Droplet

set -e

# Redirect output to log file for debugging
exec > >(tee -i /var/log/user-data.log) 2>&1

echo "🟢 Starting Droplet bootstrapping..."

# Update package repository and install basic tools
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl vim git netcat-openbsd ufw

echo "🟢 Installing K3s (${k3s_version})..."
# Install pinned K3s version (disabling default Traefik ingress controller)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" INSTALL_K3S_EXEC="--disable traefik" sh -

# Wait for node availability
until kubectl get nodes; do
  echo "⏳ Waiting for K3s api-server to respond..."
  sleep 5
done

echo "🟢 Deploying Ingress Nginx Controller (${ingress_nginx_version})..."
# Apply pinned Ingress Nginx Baremetal manifest
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${ingress_nginx_version}/deploy/static/provider/baremetal/deploy.yaml"

# Wait for Ingress controller deployment to appear
until kubectl -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; do
  echo "⏳ Waiting for Ingress controller deployment resources..."
  sleep 5
done

echo "🟢 Patching Ingress controller for HostNetwork..."
# Patch deployment to use host network namespace to bind to ports 80/443 on the Droplet
kubectl -n ingress-nginx patch deployment ingress-nginx-controller \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}]' || true

# Restart deployment to apply changes
kubectl -n ingress-nginx rollout restart deployment ingress-nginx-controller

echo "🟢 Installing Cert-Manager (${cert_manager_version})..."
# Install pinned cert-manager manifests
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${cert_manager_version}/cert-manager.yaml"

# Wait for cert-manager components to become ready (controller, cainjector, webhook)
echo "⏳ Waiting for Cert-Manager components to become available..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=300s
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s

echo "⏳ Waiting for cert-manager-webhook service endpoints..."
until kubectl get endpoints cert-manager-webhook -n cert-manager -o jsonpath='{.subsets[0].addresses[0].ip}' >/dev/null 2>&1; do
  echo "Waiting for cert-manager-webhook endpoints..."
  sleep 3
done

echo "🟢 Configuring ClusterIssuer for Let's Encrypt..."
# Apply Let's Encrypt production ClusterIssuer
cat <<EOF > /tmp/cluster-issuer-prod.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${letsencrypt_email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl apply -f /tmp/cluster-issuer-prod.yaml

echo "🟢 Generating Remote Kubeconfig..."
# Fetch the droplet's public IP using DigitalOcean metadata service
PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

# Create kubeconfig for root user access
cp /etc/rancher/k3s/k3s.yaml /root/k3s-remote.yaml
sed -i "s|127.0.0.1|$PUBLIC_IP|g" /root/k3s-remote.yaml
chmod 600 /root/k3s-remote.yaml

echo "🟢 Droplet bootstrapping complete!"
