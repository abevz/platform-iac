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
  default     = "homelab"
}

variable "proxmox_ssh_address" {
  description = "FQDN or IP for SSH connection to Proxmox node"
  type        = string
  default     = "homelab.bevz.net"
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

variable "ssh_port" {
  description = "Proxmox ssh port for the VM template"
  type        = number
  default     = "22006" # Your template
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
variable "worker_disk_size" {
  type    = number
  default = 50
}

variable "control_plane_ips" {
  description = "Static IPs for control plane nodes"
  type        = list(string)
  default     = ["10.10.10.200"]
}

variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
  default     = ["10.10.10.201", "10.10.10.202"]
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "10.10.10.1"
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
  default     = "10.10.10.100"
}
