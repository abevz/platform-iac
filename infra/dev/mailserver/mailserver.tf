resource "proxmox_vm_qemu" "mailserver" {
  for_each = var.mailserver

  name        = each.key
  target_node = each.value.target_node
  agent       = 1
  clone       = var.common.clone
  vmid        = each.value.id
  memory      = each.value.memory
  cores       = each.value.cores
  vga {
    type = "qxl"
  }
  network {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = true
  }
  disk {
    type    = "scsi"
    storage = "DataPool"
    size    = each.value.disk
    format  = "raw"
    ssd     = 1
    discard = "on"
  }
  serial {
    id   = 0
    type = "socket"
  }
  bootdisk     = "scsi0"
  scsihw       = "virtio-scsi-pci"
  os_type      = "cloud-init"
  ipconfig0    = "ip=${each.value.cidr},gw=${each.value.gw}"
  ciuser       = "ubuntu"
  cipassword   = data.sops_file.secrets.data["ubuntu.user_password"]
  searchdomain = var.common.search_domain
  nameserver   = var.common.nameserver
  sshkeys      = data.sops_file.secrets.data["ubuntu.ssh_key"]
}
