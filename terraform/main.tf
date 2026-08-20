terraform {
  required_version = ">= 1.0.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

locals {
  server_droplet_id = var.create_droplet ? digitalocean_droplet.server[0].id : var.existing_droplet_id
  server_ipv4       = var.create_droplet ? digitalocean_droplet.server[0].ipv4_address : var.existing_droplet_ip
  bootstrap_script = templatefile("${path.module}/templates/user_data.sh", {
    letsencrypt_email     = var.letsencrypt_email
    k3s_version           = var.k3s_version
    ingress_nginx_version = var.ingress_nginx_version
    cert_manager_version  = var.cert_manager_version
  })
}

# Register developer public SSH key on DigitalOcean
resource "digitalocean_ssh_key" "deployer" {
  count      = var.create_droplet ? 1 : 0
  name       = "cloudnotes-deployer-key"
  public_key = var.pub_key
}

# Provision Droplet and bootstrap K3s stack
resource "digitalocean_droplet" "server" {
  count    = var.create_droplet ? 1 : 0
  image    = "ubuntu-22-04-x64"
  name     = var.droplet_name
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [digitalocean_ssh_key.deployer[0].id]

  user_data = templatefile("${path.module}/templates/user_data.sh", {
    letsencrypt_email     = var.letsencrypt_email
    k3s_version           = var.k3s_version
    ingress_nginx_version = var.ingress_nginx_version
    cert_manager_version  = var.cert_manager_version
  })

  tags = ["cloudnotes", "production"]
}

# FireWall rules to secure the Droplet
resource "digitalocean_firewall" "kubernetes" {
  name = "cloudnotes-firewall"

  droplet_ids = [local.server_droplet_id]

  lifecycle {
    precondition {
      condition     = var.create_droplet || (var.existing_droplet_id != null && var.existing_droplet_ip != null)
      error_message = "When create_droplet is false, set both existing_droplet_id and existing_droplet_ip."
    }
  }

  # SSH Access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTP Web Traffic & Let's Encrypt Verification
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS Web Traffic
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Remote Kubectl API Server access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = var.k8s_api_allowed_cidrs
  }

  # Outbound Rules (Allow all traffic)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "null_resource" "bootstrap_existing_droplet" {
  count = var.create_droplet ? 0 : 1

  triggers = {
    droplet_id      = tostring(var.existing_droplet_id)
    droplet_ip      = var.existing_droplet_ip
    script_sha1     = sha1(local.bootstrap_script)
    k3s_version     = var.k3s_version
    ingress_version = var.ingress_nginx_version
    certmgr_version = var.cert_manager_version
    acme_email      = var.letsencrypt_email
  }

  connection {
    type        = "ssh"
    host        = var.existing_droplet_ip
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    content     = local.bootstrap_script
    destination = "/tmp/cloudnotes-bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/cloudnotes-bootstrap.sh",
      "bash /tmp/cloudnotes-bootstrap.sh"
    ]
  }

  depends_on = [digitalocean_firewall.kubernetes]
}
