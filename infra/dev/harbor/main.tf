# /infra/dev/harbor/main.tf

# ЭТАП 1: Создание Cloud-Init Snippets
resource "proxmox_virtual_environment_file" "harbor_user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "harbor-server" # 👈 Статичное имя
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "harbor-server-userdata.yaml" # 👈 Статичное имя
  }
}

# ЭТАП 2: Создание VM
resource "proxmox_virtual_environment_vm" "harbor_vm" {
  vm_id = var.vm_id
  name  = "harbor-server"

  depends_on = [
    proxmox_virtual_environment_file.harbor_user_data
  ]

  node_name = var.proxmox_node_name
  tags      = ["harbor-server", "terraform", var.control_plane_ips[0]]

  clone { vm_id = var.vm_template_id }

  cpu {
    cores = var.cp_cores
    type  = "host"
  }
  memory { dedicated = var.cp_memory }
  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = var.cp_disk_size
  }

  provisioner "local-exec" {
    when    = create
    command = "echo 'VM ${self.name} создана, ожидание 60 секунд для запуска QEMU Agent...' && sleep 60"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        # Используем первый (и единственный) IP из списка
        address = "${var.control_plane_ips[0]}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    # Прямая ссылка на ID, без [count.index]
    user_data_file_id = proxmox_virtual_environment_file.harbor_user_data.id
  }

  lifecycle {
    ignore_changes = [
      initialization
    ]
  }

  started = var.vm_started
}
