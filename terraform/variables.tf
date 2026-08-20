variable "do_token" {
  type        = string
  description = "DigitalOcean API Personal Access Token"
  sensitive   = true
}

variable "pub_key" {
  type        = string
  description = "The SSH Public Key content to register on the Droplet for SSH access"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email address for Let's Encrypt certificate notices"
}

variable "region" {
  type        = string
  description = "DigitalOcean Region to deploy resources in"
  default     = "nyc3"
}

variable "droplet_size" {
  type        = string
  description = "Droplet server size (s-2vcpu-4gb is recommended to run MySQL, Postgres, Redis, and Python AI service)"
  default     = "s-2vcpu-4gb"
}

variable "droplet_name" {
  type        = string
  description = "Name of the DigitalOcean Droplet"
  default     = "cloudnotes-prod-server"
}

variable "k3s_version" {
  type        = string
  description = "Pinned K3s version used during droplet bootstrap"
  default     = "v1.30.6+k3s1"
}

variable "ingress_nginx_version" {
  type        = string
  description = "Pinned ingress-nginx controller manifest tag"
  default     = "controller-v1.11.3"
}

variable "cert_manager_version" {
  type        = string
  description = "Pinned cert-manager release tag"
  default     = "v1.15.3"
}

variable "k8s_api_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access Kubernetes API server on 6443"
  default     = ["0.0.0.0/0", "::/0"]
}

variable "create_droplet" {
  type        = bool
  description = "Whether Terraform should create a new droplet. Set false to reuse an existing droplet."
  default     = true
}

variable "existing_droplet_id" {
  type        = number
  description = "Existing DigitalOcean droplet ID to reuse when create_droplet is false."
  default     = null
}

variable "existing_droplet_ip" {
  type        = string
  description = "Existing DigitalOcean droplet public IPv4 to reuse when create_droplet is false."
  default     = null
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to local SSH private key used to connect to existing droplet when create_droplet is false."
  default     = "~/.ssh/id_ed25519"
}
