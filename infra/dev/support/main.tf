resource "proxmox_virtual_environment_file" "user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"
  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "support-server"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "support-server-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  vm_id      = var.vm_id
  name       = "support-server"
  node_name  = var.proxmox_node_name
  tags       = ["support", "rustdesk", "tailscale", "terraform"]
  depends_on = [proxmox_virtual_environment_file.user_data]
  clone { vm_id = var.vm_template_id }

  # More resources for RustDesk
  cpu {
    cores = 2
    type  = "host"
  }
  memory { dedicated = 2048 }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
  }
  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_ip}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }
  started = var.vm_started
}
