# ---
# ЭТАП 1: Создание Cloud-Init Snippets (Ваш "выстраданный" метод)
# ---

# Snippet для Control Plane
resource "proxmox_virtual_environment_file" "cp_user_data" {
  count = var.control_plane_count

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = yamlencode({
      "hostname" : "k8s-lab-01-cp-${count.index + 1}",
      "manage_etc_hosts" : true,
      "package_update" : true,
      "packages" : [
        "qemu-guest-agent",
        "python3" # Для Ansible
      ],
      "users" : [
        {
          "name" : var.vm_user,
          "groups" : ["sudo"],
          "shell" : "/bin/bash",
          "sudo" : ["ALL=(ALL) NOPASSWD:ALL"],
          "ssh_authorized_keys" : [
            var.ssh_public_key
          ]
        }
      ],
      "runcmd" : [
        "systemctl enable --now qemu-guest-agent.service"
      ]
    })
    file_name = "k8s-lab-01-cp-${count.index + 1}-userdata.yaml"
  }
}

# Snippet для Workers
resource "proxmox_virtual_environment_file" "wn_user_data" {
  count = var.worker_count

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = yamlencode({
      "hostname" : "k8s-lab-01-wn-${count.index + 1}",
      "manage_etc_hosts" : true,
      "package_update" : true,
      "packages" : [
        "qemu-guest-agent",
        "python3"
      ],
      "users" : [
        {
          "name" : var.vm_user,
          "groups" : ["sudo"],
          "shell" : "/bin/bash",
          "sudo" : ["ALL=(ALL) NOPASSWD:ALL"],
          "ssh_authorized_keys" : [
            var.ssh_public_key
          ]
        }
      ],
      "runcmd" : [
        "systemctl enable --now qemu-guest-agent.service"
      ]
    })
    file_name = "k8s-lab-01-wn-${count.index + 1}-userdata.yaml"
  }
}


# ---
# ЭТАП 2: Создание VM
# ---

# --- Control Plane VM(s) ---
resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.control_plane_count
  name  = "k8s-lab-01-cp-${count.index + 1}"
  
  depends_on = [proxmox_virtual_environment_file.cp_user_data]

  node_name = var.proxmox_node_name
  tags      = ["k8s-lab-01", "control-plane", "terraform"]

  clone {
    vm_id = var.vm_template_id
  }
  
  agent { enabled = true }

  cpu { cores = var.cp_cores }
  memory { dedicated = var.cp_memory }

  disk {
    datastore_id = "local-lvm" 
    interface    = "scsi0"
    size         = var.cp_disk_size
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 { address = "dhcp" }
    }
    user_data_file_id = proxmox_virtual_environment_file.cp_user_data[count.index].id
  }
}

# --- Worker Node VM(s) ---
resource "proxmox_virtual_environment_vm" "workers" {
  count = var.worker_count
  name  = "k8s-lab-01-wn-${count.index + 1}"

  depends_on = [proxmox_virtual_environment_file.wn_user_data]

  node_name = var.proxmox_node_name
  tags      = ["k8s-lab-01", "worker", "terraform"]

  clone {
    vm_id = var.vm_template_id
  }
  
  agent { enabled = true }

  cpu { cores = var.worker_cores }
  memory { dedicated = var.worker_memory }
  
  disk {
    datastore_id = "local-lvm" 
    interface    = "scsi0"
    size         = var.worker_disk_size
  }
  
  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 { address = "dhcp" }
    }
    user_data_file_id = proxmox_virtual_environment_file.wn_user_data[count.index].id
  }
}
