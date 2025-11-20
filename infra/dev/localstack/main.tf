# infra/dev/localstack/main.tf
resource "proxmox_virtual_environment_file" "localstack_user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "localstack-server"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "localstack-server-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "localstack_vm" {
  vm_id = var.vm_id
  name  = "localstack-server"

  depends_on = [
    proxmox_virtual_environment_file.localstack_user_data
  ]

  node_name = var.proxmox_node_name
  tags      = ["localstack", "terraform", var.control_plane_ips[0]]

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

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.control_plane_ips[0]}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.localstack_user_data.id
  }

  lifecycle {
    ignore_changes = [initialization]
  }
  started = var.vm_started
}
