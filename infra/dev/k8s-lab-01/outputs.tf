output "ansible_inventory" {
  description = "Динамический инвентарь для Ansible в формате JSON"
  
  value = jsonencode({
    k8s_control_plane = {
      hosts = [for i, vm in proxmox_virtual_environment_vm.control_plane : vm.name]
    }
    k8s_workers = {
      hosts = [for i, vm in proxmox_virtual_environment_vm.workers : vm.name]
    }
    k8s_cluster = {
      children = [
        "k8s_control_plane",
        "k8s_workers"
      ]
    }
    _meta = {
      hostvars = merge(
        { for i, vm in proxmox_virtual_environment_vm.control_plane : vm.name => {
            ansible_host = vm.ipv4_addresses[0]
            ansible_user = var.vm_user # (abevz)
          }
        },
        { for i, vm in proxmox_virtual_environment_vm.workers : vm.name => {
            ansible_host = vm.ipv4_addresses[0]
            ansible_user = var.vm_user # (abevz)
          }
        }
      )
    }
  })
}
