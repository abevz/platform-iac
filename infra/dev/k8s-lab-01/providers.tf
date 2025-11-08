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
  endpoint         = var.proxmox_api_url
  api_token_id     = var.proxmox_api_token_id
  api_token_secret = var.proxmox_api_token_secret
  insecure         = true 

  # SSH Аутентификация (для операций с файлами/сниппетами)
  ssh {
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key
  }
}
