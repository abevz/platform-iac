resource "proxmox_virtual_environment_file" "vault_user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = var.vm_name
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "${var.vm_name}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vault_vm" {
  vm_id               = var.vm_id
  name                = var.vm_name
  node_name           = var.proxmox_node_name
  tags                = sort(["vault", "terraform", var.vm_ip_address])
  machine             = "q35"
  reboot              = false
  reboot_after_update = false

  depends_on = [
    proxmox_virtual_environment_file.vault_user_data
  ]

  # VM109 already exists. Clone ancestry is not an instruction to replace it.
  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = var.cp_cores
    type  = "host"
  }

  memory { dedicated = var.cp_memory }

  disk {
    datastore_id = var.vm_disk_datastore
    interface    = "scsi0"
    size         = var.cp_disk_size
  }
  # Preserve both existing disks when adopting the manually moved VM.
  disk {
    datastore_id = var.vm_disk_datastore
    interface    = "virtio0"
    size         = 20
    iothread     = true
  }
  serial_device {
    device = "socket"
  }
  vga {
    type = "serial0"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_ip_address}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.vault_user_data.id
  }

  lifecycle {
    prevent_destroy = true
    # Preserve operator-owned notes, inherited first-boot data and existing VM defaults.
    # Provider operation controls, IP, gateway and snippet references remain managed.
    ignore_changes = [
      description,
      initialization[0].dns,
      initialization[0].user_account,
      keyboard_layout,
      agent[0].type,
      operating_system,
    ]
  }

  started = var.vm_started
}
