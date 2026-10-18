# --- PROVIDER VARIABLES (FROM SOPS) ---
variable "proxmox_api_url" {
  type      = string
  sensitive = true
}

# --- FIX ---
variable "proxmox_api_username" {
  type      = string
  sensitive = true
}
variable "proxmox_api_password" {
  type      = string
  sensitive = true
}
# -----------

variable "proxmox_ssh_user" {
  type      = string
  sensitive = true
}
variable "proxmox_ssh_private_key" {
  type      = string
  sensitive = true
}

variable "proxmox_node_name" {
  description = "Proxmox node where VMs will be created"
  type        = string
  default     = "lab-host"
}

variable "proxmox_ssh_address" {
  description = "FQDN or IP for SSH connection to Proxmox node"
  type        = string
  default     = "lab-host.example.com"
}

variable "proxmox_ssh_port" {
  description = "SSH port of the Proxmox node (snippet uploads)"
  type        = number
  default     = 22
}

variable "vm_template_id" {
  description = "VM template ID (Cloud-Init golden image)"
  type        = number
  default     = "9420"
}

variable "vm_bridge" {
  description = "Network bridge (e.g. vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_snippet_storage" {
  description = "Storage for Cloud-Init snippets"
  type        = string
  default     = "local"
}

# --- Ansible Variables ---
variable "vm_user" {
  description = "Ansible SSH username"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
  default     = "ssh-rsa AAAA..."
}

# --- Node Counts ---
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

# --- VM Specifications ---
variable "cp_cores" {
  type    = number
  default = 2
}
variable "cp_memory" {
  type    = number
  default = 4096
}
variable "cp_disk_size" {
  type    = number
  default = 32
}
variable "worker_cores" {
  type    = number
  default = 2
}
variable "worker_memory" {
  type    = number
  default = 4096
}
variable "worker_memory_overrides" {
  description = "Dedicated memory in MiB for named CPU workers; other workers use worker_memory"
  type        = map(number)
  default     = {}

  validation {
    condition = alltrue([
      for name, memory in var.worker_memory_overrides :
      contains([for index in range(var.worker_count) : "lab-cluster-wn-${index + 1}"], name) && memory > 0 && floor(memory) == memory
    ])
    error_message = "Memory overrides must name an existing CPU worker and specify a positive integer in MiB."
  }
}
variable "worker_disk_size" {
  type    = number
  default = 50
}

variable "control_plane_ips" {
  description = "Static IPs for control plane nodes"
  type        = list(string)
  default     = ["<K8S-INGRESS-IP>"]
}

variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
  default     = ["<K8S-WORKER-1-IP>", "<K8S-WORKER-2-IP>"]
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "<LAN-GATEWAY-IP>"
}

variable "ip_prefix_length" {
  description = "CIDR prefix length (e.g. 24 for /24)"
  type        = number
  default     = 24
}

variable "vm_started" {
  description = "Controls if the VMs should be running (true) or stopped (false)."
  type        = bool
  default     = true
}

variable "vm_dns_server" {
  description = "DNS server IP for VMs (e.g. Pi-hole)"
  type        = string
  default     = "<PIHOLE-IP>"
}

# --- Optional GPU worker (PCI passthrough) ---
variable "gpu_worker_count" {
  description = "Number of GPU worker nodes (0 disables the GPU worker and its PCI mapping)"
  type        = number
  default     = 0

  validation {
    condition     = var.gpu_worker_count >= 0 && var.gpu_worker_count <= 1
    error_message = "Only one passthrough GPU exists on the host: gpu_worker_count must be 0 or 1."
  }
}

variable "gpu_worker_ips" {
  description = "Static IPs for GPU worker nodes"
  type        = list(string)
  default     = []
}

variable "gpu_worker_cores" {
  type    = number
  default = 4
}

variable "gpu_worker_memory" {
  description = "RAM for the GPU worker in MB. Passthrough pins all of it on the host, so keep it modest"
  type        = number
  default     = 8192
}

variable "gpu_worker_disk_size" {
  type    = number
  default = 60
}

variable "gpu_mapping_name" {
  description = "Name of the cluster PCI resource mapping for the GPU"
  type        = string
  default     = "gpu-gtx1660s"
}

variable "gpu_pci_path" {
  description = "Host PCI address of the GPU without function suffix (all functions are passed through)"
  type        = string
  default     = "0000:08:00"
}

variable "gpu_pci_id" {
  description = "vendor:device of GPU function .0"
  type        = string
  default     = "10de:21c4"
}

variable "gpu_pci_subsystem_id" {
  description = "Subsystem vendor:device of GPU function .0"
  type        = string
  default     = "1462:c758"
}

variable "gpu_iommu_group" {
  description = "IOMMU group of the GPU (must contain only the GPU functions)"
  type        = number
  default     = 21
}
