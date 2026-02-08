mock_provider "proxmox" {}

override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      "ubuntu.user_password" = "test-password" # gitleaks:allow
      "ubuntu.ssh_key"       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILm+..."
    }
  }
}

variables {
  proxmox_host = "pve1.example.com"

  common = {
    os_type = "ubuntu"
    clone = "ubuntu-2210-cloudinit-template"
    search_domain = "homelab.<your-dev-domain>.dev"
    nameserver = "<LAN-GATEWAY-IP>"
  }

  mailserver = {
    "mail-test-01" = {
      id = "101"
      cidr = "192.168.1.10/24"
      gw = "192.168.1.1"
      memory = "2048"
      cores = "2"
      disk = "20G"
      target_node = "pve1"
    }
  }
}

run "valid_configuration" {
  command = plan

  assert {
    condition     = proxmox_vm_qemu.mailserver["mail-test-01"].name == "mail-test-01"
    error_message = "VM name did not match expected"
  }

  assert {
    condition     = proxmox_vm_qemu.mailserver["mail-test-01"].memory == 2048
    error_message = "Memory configuration is incorrect"
  }
}
