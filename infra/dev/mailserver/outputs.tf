# /infra/dev/mailserver/outputs.tf

locals {
  # Take the first (and only) mailserver from for_each
  mailserver_instances = { for k, v in proxmox_vm_qemu.mailserver : k => v }
}

output "ansible_inventory_data" {
  value = jsonencode({
    _meta = {
      hostvars = {
        for name, vm in local.mailserver_instances : name => {
          ansible_host = split("/", vm.default_ipv4_address)[0]
          private_ip   = split("/", vm.default_ipv4_address)[0]
          ansible_user = "ubuntu"
          ansible_port = 22
          vm_name      = name
          vm_id        = vm.vmid
          node_role    = "mailserver"
        }
      }
    },

    all = {
      children = ["mailservers"]
    },
    mailservers = {
      hosts = [for name, _ in local.mailserver_instances : name]
    },
    proxmox_vms = {
      hosts = [for name, _ in local.mailserver_instances : name]
    }
  })
}
