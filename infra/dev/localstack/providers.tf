# infra/dev/localstack/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.86.0"
    }
  }
}
provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_api_username
  password = var.proxmox_api_password
  insecure = true
  ssh {
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key
    node {
      name    = var.proxmox_node_name
      address = var.proxmox_ssh_address
      port    = var.proxmox_ssh_port
    }
  }
}
