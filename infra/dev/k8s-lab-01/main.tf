# ---
# ЭТАП 1: Создание Cloud-Init Snippets (Метод v3.13)
# ---

resource "proxmox_virtual_environment_file" "cp_user_data" {
  count = var.control_plane_count

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    # Tofu рендерит шаблон cp-userdata.tftpl
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "k8s-lab-01-cp-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
    })
    file_name = "k8s-lab-01-cp-${count.index + 1}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_file" "wn_user_data" {
  count = var.worker_count

  # Зависит от CP-файла (для решения проблемы блокировки)
  depends_on = [
    proxmox_virtual_environment_file.cp_user_data
  ]

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    # Tofu рендерит шаблон wn-userdata.tftpl
    data = templatefile("${path.module}/wn-userdata.tftpl", {
      hostname       = "k8s-lab-01-wn-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
    })
    file_name = "k8s-lab-01-wn-${count.index + 1}-userdata.yaml"
  }
}


# ---
# ЭТАП 2: Создание VM (со Статическими IP)
# ---

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.control_plane_count
  name  = "k8s-lab-01-cp-${count.index + 1}"
  
  depends_on = [
    proxmox_virtual_environment_file.cp_user_data
  ]

  node_name = var.proxmox_node_name
  tags      = ["k8s-lab-01", "control-plane", "terraform"]

  clone { vm_id = var.vm_template_id }
  #agent { enabled = true }
  cpu { cores = var.cp_cores }
  memory { dedicated = var.cp_memory }
  disk {
    datastore_id = "local-lvm" 
    interface    = "scsi0"
    size         = var.cp_disk_size
  }

  # Этот provisioner запускается при создании ресурса
  provisioner "local-exec" {
    # Даем VM 60 секунд на первую загрузку и запуск QEMU Agent
    # перед тем, как Terraform попытается выполнить 'reboot' через агент.
    when    = create
    command = "echo 'VM ${self.name} создана, ожидание 60 секунд для запуска QEMU Agent...' && sleep 60"
  }  

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  # --- ИСПРАВЛЕНО: Статический IP ---
  initialization {
    ip_config {
      ipv4 {
        #address = "dhcp"
        address = "${var.control_plane_ips[count.index]}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cp_user_data[count.index].id
  }
  # --------------------------------

  lifecycle {
    ignore_changes = [
      initialization
    ]
  }

  started = var.vm_started
}

resource "proxmox_virtual_environment_vm" "workers" {
  count = var.worker_count
  name  = "k8s-lab-01-wn-${count.index + 1}"

  # Зависит от WN-файлов И CP-VM (для решения проблемы блокировки)
  depends_on = [
    proxmox_virtual_environment_file.wn_user_data,
    proxmox_virtual_environment_vm.control_plane
  ]

  node_name = var.proxmox_node_name
  tags      = ["k8s-lab-01", "worker", "terraform"]

  clone { vm_id = var.vm_template_id }
  #agent { enabled = true }
  cpu { cores = var.worker_cores }
  memory { dedicated = var.worker_memory }
  disk {
    datastore_id = "local-lvm" 
    interface    = "scsi0"
    size         = var.worker_disk_size
  }

# --- ИСПРАВЛЕНИЕ: Добавляем принудительную задержку ---
  provisioner "local-exec" {
    when    = create
    command = "echo 'VM ${self.name} создана, ожидание 60 секунд для запуска QEMU Agent...' && sleep 60"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  # --- ИСПРАВЛЕНО: Статический IP ---
  initialization {
    ip_config {
      ipv4 {
        #address = "dhcp"
        address = "${var.worker_ips[count.index]}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.wn_user_data[count.index].id
  }
  # --------------------------------
  lifecycle {
    ignore_changes = [
      initialization
    ]
  }
  
  started = var.vm_started
}
