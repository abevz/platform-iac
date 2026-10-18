# Existing bootstrap objects: adoption only, never clone/recreate them.
resource "proxmox_virtual_environment_file" "rustfs_user_data" {
  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"
  overwrite    = false

  # piac-50 STOP exception: retain 8 historical minio-server literals in user-data.
  # Content changes alter both VMs' NoCloud instance IDs; see the runbook and audit allowlist.
  # No source_file/source_raw: ownership of existing file, no upload intent.
  lifecycle {
    prevent_destroy = true
    # Import does not populate these upload-control metadata fields. No source is configured.
    ignore_changes = [overwrite, timeout_upload]
    postcondition {
      condition     = self.file_name == "rustfs-server-userdata.yaml"
      error_message = "The imported snippet does not match the existing VM."
    }
  }
}

resource "proxmox_virtual_environment_vm" "rustfs_vm" {
  vm_id               = var.vm_id
  name                = "rustfs-server"
  node_name           = var.proxmox_node_name
  description         = "Machine-ID will be regenerated on clone to ensure unique DHCP IPs"
  tags                = sort(["rustfs-server", "terraform", var.vm_ip_address])
  machine             = "q35"
  reboot              = false
  reboot_after_update = false

  agent {
    enabled = true
    trim    = true
  }
  cpu {
    cores = var.cp_cores
    type  = "host"
    units = 100
  }
  memory {
    dedicated = var.cp_memory
    floating  = 0
  }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.cp_disk_size
    iothread     = false
  }
  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    size         = 20
    iothread     = true
  }
  network_device {
    bridge      = var.vm_bridge
    model       = "virtio"
    mac_address = "BC:24:11:03:1F:B6"
  }
  serial_device {
    device = "socket"
  }
  vga {
    type = "serial0"
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_ip_address}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.rustfs_user_data.id
  }
  lifecycle {
    prevent_destroy = true
    # Existing cloud-init settings are retained; disks remain fully managed.
    ignore_changes = [
      initialization,
      # Provider 0.86 import omits these control/default metadata fields.
      # Preserve the live API values; no disk fields are ignored.
      keyboard_layout, migrate, on_boot, stop_on_destroy,
      timeout_clone, timeout_create, timeout_migrate, timeout_move_disk,
      timeout_reboot, timeout_shutdown_vm, timeout_start_vm, timeout_stop_vm,
      agent[0].type, operating_system,
    ]
  }
  started = var.vm_started
}
