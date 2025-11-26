locals {
  vm      = proxmox_virtual_environment_vm.vm
  host_ip = try(local.vm.ipv4_addresses[1][0], "unknown")
}

output "ansible_inventory_data" {
  value = jsonencode({
    _meta = {
      hostvars = {
        (local.vm.name) = {
          ansible_host = local.host_ip
          ansible_user = var.vm_user
          ansible_port = 22
          node_role    = "support"
        }
      }
    },
    all             = { children = ["support_servers"] },
    support_servers = { hosts = [local.vm.name] }
  })
}
