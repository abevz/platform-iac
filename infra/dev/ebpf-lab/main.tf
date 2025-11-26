# infra/dev/ebpf-lab/main.tf
# --- Cloud-Init Config ---
resource "proxmox_virtual_environment_file" "user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/userdata.tftpl", {
      hostname       = "ebpf-lab-01"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "ebpf-lab-01-userdata.yaml"
  }
}

# --- VM Resource ---
resource "proxmox_virtual_environment_vm" "ebpf_lab" {
  vm_id     = var.vm_id
  name      = "ebpf-lab-01"
  node_name = var.proxmox_node_name

  depends_on = [proxmox_virtual_environment_file.user_data]

  # Клонируем из Вашего нового шаблона (ID 9000)
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  agent { enabled = true }

  # Ресурсы: eBPF компиляция (BCC/bpftrace) любит CPU и RAM
  cpu {
    cores = 4
    type  = "host" # Важно: пробрасывает флаги процессора хоста
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "DataPool"
    interface    = "scsi0"
    size         = 30 # Увеличиваем до 30ГБ (тулинг весит немало)
    ssd          = true
    discard      = "on"
  }

  provisioner "local-exec" {
    when    = create
    command = "echo 'VM ${self.name} создана. Ждем 90с пока Cloud-Init установит QEMU Agent...' && sleep 90"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio" # Важно для XDP (eXpress Data Path)
  }

  # Cloud-Init
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp" # Для лабы DHCP ок, или укажите статику
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  lifecycle {
    ignore_changes = [initialization]
  }

  started = true
}
