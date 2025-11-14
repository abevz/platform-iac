# infra/dev/minio/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.86.0"
    }
  }
}

# HCL ТЕПЕРЬ ОЖИДАЕТ ПЕРЕМЕННЫЕ
provider "proxmox" {
  # API Аутентификация
  endpoint = var.proxmox_api_url
  username = var.proxmox_api_username # Используем 'username'
  password = var.proxmox_api_password # Используем 'password'
  insecure = true

  # SSH Аутентификация (для операций с файлами/сниппетами)
  ssh {
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key
    node {
      name = var.proxmox_node_name # (т.е. "homelab")

      # Это FQDN, который Вы используете в ~/.ssh/config
      address = var.proxmox_ssh_address # (т.е. "homelab.bevz.net")

      # Это порт из Вашего ~/.ssh/config
      port = var.proxmox_ssh_port # <-- ИСПОЛЬЗУЕМ ПЕРЕМЕННУЮ
    }
  }
}
