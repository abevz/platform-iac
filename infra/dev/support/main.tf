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
  lifecycle {
    # Preserve the already-used first-boot input; configure the guest separately.
    ignore_changes = [source_raw[0].data]
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  vm_id               = var.vm_id
  name                = "support-server"
  reboot              = false
  reboot_after_update = false
  node_name           = var.proxmox_node_name
  tags                = ["support", "rustdesk", "tailscale", "terraform"]
  depends_on          = [proxmox_virtual_environment_file.user_data]
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
  # Keep the empty scsi0 disk separate from the relocated system disk.
  disk {
    datastore_id = "DataPool"
    interface    = "virtio0"
    size         = 20
    iothread     = true
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
    # The snippet path stays stable when its content is replaced.
    user_data_file_id = "${var.proxmox_snippet_storage}:snippets/${proxmox_virtual_environment_file.user_data.source_raw[0].file_name}"
  }
  on_boot = var.vm_on_boot
  started = var.vm_started
  lifecycle {
    # Preserve inherited first-boot DNS/accounts, not the whole cloud-init block.
    # IP, gateway, snippet references and disk attachments remain managed.
    ignore_changes = [
      initialization[0].dns,
      initialization[0].user_account,
    ]
  }
}
