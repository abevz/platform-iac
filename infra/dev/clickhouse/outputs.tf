output "ansible_inventory_data" {
  value = jsonencode({
    _meta = {
      hostvars = {
        for i, vm in proxmox_virtual_environment_vm.clickhouse_vm :
        vm.name => {
          ansible_host = try(vm.ipv4_addresses[1][0], "unknown")
          ansible_user = var.vm_user
          ansible_port = 22
          node_role    = "clickhouse"
        }
      }
    }

    all = {
      children = ["clickhouse_servers"]
    }
    clickhouse_servers = {
      hosts = [for vm in proxmox_virtual_environment_vm.clickhouse_vm : vm.name]
    }
  })
}
