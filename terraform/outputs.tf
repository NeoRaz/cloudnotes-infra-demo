output "droplet_ip" {
  value       = local.server_ipv4
  description = "The public IP address of the target Droplet"
}

output "ssh_connection_string" {
  value       = "ssh root@${local.server_ipv4}"
  description = "SSH command to connect to the Droplet console"
}

output "kubeconfig_fetch_instructions" {
  value       = <<EOF
1. Wait 2-3 minutes for the K3s cluster bootstrap scripts to complete running.
2. Fetch the secure kubeconfig using scp:
   scp root@${local.server_ipv4}:/root/k3s-remote.yaml ./k3s-prod.yaml
3. Point your local kubectl to the production cluster:
   export KUBECONFIG=./k3s-prod.yaml  (Linux/macOS)
   $env:KUBECONFIG=".\k3s-prod.yaml"  (PowerShell)
4. Verify the cluster nodes:
   kubectl get nodes
5. Verify the ingress controller and cert-manager services are running:
   kubectl get pods -n ingress-nginx
   kubectl get pods -n cert-manager
EOF
  description = "Steps to pull the remote kubeconfig and connect kubectl"
}
