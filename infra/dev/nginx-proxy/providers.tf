terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.86.0"
    }
  }
}

# HCL NOW EXPECTS VARIABLES
provider "proxmox" {
  # API Authentication
  endpoint = var.proxmox_api_url
  username = var.proxmox_api_username # Use 'username'
  password = var.proxmox_api_password # Use 'password'
  insecure = true

  # SSH Authentication (for file/snippet operations)
  ssh {
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key
    node {
      name = var.proxmox_node_name # (e.g. "lab-host")

      # This is the FQDN you use in ~/.ssh/config
      address = var.proxmox_ssh_address # (e.g. "lab-host.example.com")

      # iac-wrapper passes the direct port for bootstrap components
      port = var.proxmox_ssh_port
    }
  }
}
