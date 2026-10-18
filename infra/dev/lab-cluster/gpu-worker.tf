# ---
# Optional GPU worker: the host GPU (PCI passthrough via vfio-pci) in its own VM.
# Disabled by default (gpu_worker_count = 0). Host prerequisites (vfio-pci.ids,
# nvidia blacklist, initcall_blacklist=sysfb_init) are outside this module.
# ---

# API tokens may only attach mapped PCI devices (raw hostpci ids are root@pam only),
# so the GPU is exposed through a cluster-wide PCI resource mapping.
resource "proxmox_virtual_environment_hardware_mapping_pci" "gpu" {
  count = var.gpu_worker_count > 0 ? 1 : 0

  name    = var.gpu_mapping_name
  comment = "lab-cluster GPU worker passthrough"
  # One entry per node; a path without the function suffix passes all functions
  # (VGA, audio, USB, UCSI) of the card. id/subsystem_id are those of function .0.
  map = [
    {
      node         = var.proxmox_node_name
      path         = var.gpu_pci_path
      id           = var.gpu_pci_id
      subsystem_id = var.gpu_pci_subsystem_id
      iommu_group  = var.gpu_iommu_group
    }
  ]
}

resource "proxmox_virtual_environment_file" "gpu_user_data" {
  count = var.gpu_worker_count

  depends_on = [
    proxmox_virtual_environment_file.wn_user_data
  ]

  datastore_id = var.proxmox_snippet_storage
  node_name    = var.proxmox_node_name
  content_type = "snippets"

  source_raw {
    data = templatefile("${path.module}/wn-userdata.tftpl", {
      hostname       = "lab-cluster-gpu-${count.index + 1}"
      vm_user        = var.vm_user
      ssh_public_key = var.ssh_public_key
      vm_dns         = var.vm_dns_server
    })
    file_name = "lab-cluster-gpu-${count.index + 1}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "gpu_workers" {
  count = var.gpu_worker_count
  name  = "lab-cluster-gpu-${count.index + 1}"

  depends_on = [
    proxmox_virtual_environment_file.gpu_user_data,
    proxmox_virtual_environment_vm.workers
  ]

  node_name = var.proxmox_node_name
  tags      = ["lab-cluster", "worker", "gpu", "terraform"]

  clone { vm_id = var.vm_template_id }
  # PCIe passthrough needs q35
  machine = "q35"
  cpu {
    cores = var.gpu_worker_cores
    type  = "host"
  }
  # Passthrough pins all guest RAM; ballooning must stay off
  memory { dedicated = var.gpu_worker_memory }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.gpu_worker_disk_size
  }

  hostpci {
    device  = "hostpci0"
    mapping = proxmox_virtual_environment_hardware_mapping_pci.gpu[0].name
    pcie    = true
    rombar  = true
    xvga    = false
  }

  provisioner "local-exec" {
    when    = create
    command = "echo 'VM ${self.name} created, waiting 60s for QEMU Agent...' && sleep 60"
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.gpu_worker_ips[count.index]}/${var.ip_prefix_length}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.gpu_user_data[count.index].id
  }
  lifecycle {
    # The GPU worker may be adopted with `tofu import`. An imported VM has no clone
    # history, so everything the template contributes at clone time (boot disk
    # virtio0, agent, serial console, OS type, CPU units/NUMA, description) would
    # otherwise show up as drift, and the boot disk would be detached.
    ignore_changes = [
      initialization,
      clone,
      agent,
      cpu[0].units,
      cpu[0].numa,
      disk,
      operating_system,
      serial_device,
      description,
    ]
    precondition {
      condition     = length(var.gpu_worker_ips) >= var.gpu_worker_count
      error_message = "gpu_worker_ips must have an address for every GPU worker."
    }
  }

  started = var.vm_started
}
