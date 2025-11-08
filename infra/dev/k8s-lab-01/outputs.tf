# outputs.tf

output "ansible_inventory_data" {
  value = jsonencode({
    # --- Метаданные Хостов (hostvars) ---
    _meta = {
      hostvars = merge(
        # 1. Статический элемент: Мастер-нода
        {
          (module.vms["k8s-master-01"].name) = {
            ansible_host      = module.vms["k8s-master-01"].ipv4_address
            private_ip        = module.vms["k8s-master-01"].private_ipv4_address
            ansible_user      = var.ssh_user
            ansible_port      = var.ssh_port
            node_role         = "master"
            vm_name           = module.vms["k8s-master-01"].name
            vm_id             = module.vms["k8s-master-01"].id
          }
        },

        # 2. Динамические элементы: Рабочие ноды (итерация с for expression)
        {
          for name, vm in module.vms :
          name => { # Синтаксис: ключ => значение
            ansible_host      = vm.ipv4_address
            private_ip        = vm.private_ipv4_address
            ansible_user      = var.ssh_user
            ansible_port      = var.ssh_port
            node_role         = "worker"
            vm_name           = vm.name
            vm_id             = vm.id
          }
          # Условие исключения: исключаем мастера, если имя содержит 'master'
          if !can(regex("master", name))
        }
      ) # Конец merge()
    },

    # --- Группы Ansible ---
    all = {
      children = ["k8s_master", "k8s_worker"],
      vars = {
        kube_config_dir = "~/.kube"
      }
    },
    k8s_master = {
      hosts = [module.vms["k8s-master-01"].name],
      vars = {
        is_control_plane = true
      }
    },
    k8s_worker = {
      # Создаем список имен рабочих нод, используя List for expression
      hosts = [for name, vm in module.vms : name if !can(regex("master", name))]
      vars = {
        is_control_plane = false
      }
    },
    proxmox_vms = {
      hosts = [for name, vm in module.vms : name]
    }
  })
}
