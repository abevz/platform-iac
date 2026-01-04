## outputs.tf (Универсальная версия v11.0 - Агрегация через flatten)

# Шаг 1: Универсальная Агрегация всех VM в одну Map.
locals {
  # 1. Объединяем ВСЕ списки ресурсов VM в один плоский список.
  # Этот блок требует обновления ТОЛЬКО при добавлении нового имени ресурса в main.tf.
  all_vm_resources_list = flatten([
    proxmox_virtual_environment_vm.control_plane,
    proxmox_virtual_environment_vm.workers,
  ])

  # 2. Создаем Map 'all_vms' из этого списка. Этот for-выражение УНИВЕРСАЛЬНО.
  all_vms = {
    for vm in local.all_vm_resources_list :
    vm.name => {
      name = vm.name
      # Используем проверенный путь [1][0] для IP
      ipv4_address         = try(vm.ipv4_addresses[1][0], "unknown")
      private_ipv4_address = try(vm.ipv4_addresses[1][0], "unknown")
      vm_id                = vm.id
      # Логика определения роли остается здесь
      node_role = can(regex("cp", vm.name)) ? "master" : "worker"
    }
  }
}

output "ansible_inventory_data" {
  value = jsonencode({
    # --- Метаданные Хостов (hostvars) ---
    _meta = {
      # Перебираем универсальный Map 'all_vms'. Эта секция УНИВЕРСАЛЬНА.
      hostvars = {
        for name, vm in local.all_vms :
        name => {
          ansible_host = vm.ipv4_address
          private_ip   = vm.private_ipv4_address
          ansible_user = var.vm_user
          ansible_port = 22
          vm_name      = vm.name
          vm_id        = vm.vm_id
          # Роль берется из универсального Map
          node_role = vm.node_role
        }
      }
    },

    # --- Группы Ansible ---
    # ВНИМАНИЕ: Эта секция НЕ универсальна, она зависит от имени ресурса в main.tf.
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
