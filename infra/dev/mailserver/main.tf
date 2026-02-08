terraform {
  required_version = ">= 0.13.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "2.9.10"
    }

    sops = {
      source  = "carlpett/sops"
      version = "~> 0.5"
    }
  }
}

data "sops_file" "secrets" {
  source_file = ".secrets.sops.yaml"
}

provider "proxmox" {
  pm_api_url      = "https://${var.proxmox_host}:8006/api2/json"
  pm_tls_insecure = true
  pm_parallel     = 1
  pm_log_enable   = true
  pm_log_file     = "terraform-plugin-proxmox.log"
  pm_debug        = true
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
  pm_user = "terraform-prov@pve"
  # Uncomment the below for debugging.
  # pm_log_enable = true
  # pm_log_file = "terraform-plugin-proxmox.log"
  # pm_debug = true
  # pm_log_levels = {
  # _default = "debug"
  # _capturelog = ""
  # }
}

provider "sops" {}
