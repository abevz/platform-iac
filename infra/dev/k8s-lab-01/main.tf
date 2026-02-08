# ---
# STEP 1: Create Cloud-Init Snippets
# ---

resource "proxmox_virtual_environment_file" "cp_user_data" {
  count = var.control_plane_count

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/cp-userdata.tftpl", {
      hostname       = "k8s-lab-01-cp-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "k8s-lab-01-cp-${count.index + 1}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_file" "wn_user_data" {
  count = var.worker_count

  # Depends on CP file (to prevent locking issues)
  depends_on = [
    proxmox_virtual_environment_file.cp_user_data
  ]

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/wn-userdata.tftpl", {
      hostname       = "k8s-lab-01-wn-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "k8s-lab-01-wn-${count.index + 1}-userdata.yaml"
  }
}


# ---
# STEP 2: Create VMs (with Static IPs)
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
  cpu {
    cores = var.cp_cores
    type  = "host"
  }
  memory { dedicated = var.cp_memory }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.cp_disk_size
  }

  # This provisioner runs when the resource is created
  provisioner "local-exec" {
    # Give VM 60 seconds for initial boot and QEMU Agent startup
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

  # Depends on WN files AND CP VM (to prevent locking issues)
  depends_on = [
    proxmox_virtual_environment_file.wn_user_data,
    proxmox_virtual_environment_vm.control_plane
  ]

  node_name = var.proxmox_node_name
  tags      = ["k8s-lab-01", "worker", "terraform"]

  clone { vm_id = var.vm_template_id }
  #agent { enabled = true }
  cpu {
    cores = var.worker_cores
    type  = "host"
  }
  memory { dedicated = var.worker_memory }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.worker_disk_size
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
