## outputs.tf (Universal version v11.0 - Aggregation via flatten)

# Step 1: Universal aggregation of all VMs into a single Map.
locals {
  # 1. Combine ALL VM resource lists into a single flat list.
  # This block only needs updating when adding a new resource name in main.tf.
  all_vm_resources_list = flatten([
    proxmox_virtual_environment_vm.control_plane,
    proxmox_virtual_environment_vm.workers,
  ])

  # 2. Create 'all_vms' Map from this list. This for-expression is UNIVERSAL.
  all_vms = {
    for vm in local.all_vm_resources_list :
    vm.name => {
      name = vm.name
      # Using verified path [1][0] for IP
      ipv4_address         = try(vm.ipv4_addresses[1][0], "unknown")
      private_ipv4_address = try(vm.ipv4_addresses[1][0], "unknown")
      vm_id                = vm.id
      # Role determination logic stays here
      node_role = can(regex("cp", vm.name)) ? "master" : "worker"
    }
  }
}

output "ansible_inventory_data" {
  value = jsonencode({
    # --- Host Metadata (hostvars) ---
    _meta = {
      # Iterate over universal 'all_vms' Map. This section is UNIVERSAL.
      hostvars = {
        for name, vm in local.all_vms :
        name => {
          ansible_host = vm.ipv4_address
          private_ip   = vm.private_ipv4_address
          ansible_user = var.vm_user
          ansible_port = 22
          vm_name      = vm.name
          vm_id        = vm.vm_id
          # Role taken from universal Map
          node_role = vm.node_role
        }
      }
    },

    # --- Ansible Groups ---
    # NOTE: This section is NOT universal, it depends on resource names in main.tf.
    all = {
      children = ["k8s_master", "k8s_worker"],
      vars = {
        kube_config_dir = "~/.kube"
      }
    },
    k8s_master = {
      hosts = [for vm in proxmox_virtual_environment_vm.control_plane : vm.name]
      vars = {
        is_control_plane = true
      }
    },
    k8s_worker = {
      hosts = [for vm in proxmox_virtual_environment_vm.workers : vm.name]
      vars = {
        is_control_plane = false
      }
    },
    proxmox_vms = {
      hosts = keys(local.all_vms)
    }
  })
}
