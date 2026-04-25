resource "proxmox_virtual_environment_file" "clickhouse_user_data" {
  count        = var.nodes_count
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "ch-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "ch-${count.index + 1}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "clickhouse_vm" {
  count = var.nodes_count
  name  = "ch-${count.index + 1}"

  # Depends on WN files AND CP VM (to prevent locking issues)
  depends_on = [
    proxmox_virtual_environment_file.clickhouse_user_data
  ]

  node_name = var.proxmox_node_name
  tags      = ["clickhouse", "terraform"]

  clone { vm_id = var.vm_template_id }
  #agent { enabled = true }
  cpu {
    cores = var.vm_cores
    type  = "host"
  }
  memory { dedicated = var.vm_memory }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.vm_disk_size
  }

  # --- Force delay for QEMU Agent ---
  provisioner "local-exec" {
    when    = create
    command = "echo 'VM ${self.name} created, waiting 60s for QEMU Agent...' && sleep 60"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  # --- FIXED: Static IP ---
  initialization {
    ip_config {
      ipv4 {
        #address = "dhcp"
        address = "${var.vm_ips[count.index]}/24"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.clickhouse_user_data[count.index].id
  }
  # --------------------------------
  lifecycle {
    ignore_changes = [
      initialization
    ]
  }

  started = var.vm_started

}
