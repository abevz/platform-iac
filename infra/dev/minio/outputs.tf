# infra/dev/minio/outputs.tf
# /infra/dev/minio/outputs.tf

locals {
  vm        = proxmox_virtual_environment_vm.minio_vm
  host_ip   = try(local.vm.ipv4_addresses[1][0], "unknown")
  host_name = local.vm.name
}

output "ansible_inventory_data" {
  value = jsonencode({
    _meta = {
      hostvars = {
        (local.host_name) = {
          ansible_host = local.host_ip
          private_ip   = local.host_ip
          ansible_user = var.vm_user
          ansible_port = 22
          vm_name      = local.host_name
          vm_id        = local.vm.id
          node_role    = "minio" # <-- ИЗМЕНЕНО
        }
      }
    },

    all = {
      children = ["minio_servers"] # <-- ИЗМЕНЕНО
    },

    minio_servers = { # <-- ИЗМЕНЕНО
      hosts = [local.host_name]
    },
    proxmox_vms = {
      hosts = [local.host_name]
    }
  })
}
