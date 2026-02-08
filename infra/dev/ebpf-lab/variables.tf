# infra/dev/harbor/variables.tf
# --- PROVIDER VARIABLES (FROM SOPS) ---
variable "proxmox_api_url" {
  type      = string
  sensitive = true
}
variable "proxmox_api_username" {
  type      = string
  sensitive = true
}
variable "proxmox_api_password" {
  type      = string
  sensitive = true
}
variable "proxmox_ssh_user" {
  type      = string
  sensitive = true
}
variable "proxmox_ssh_private_key" {
  type      = string
  sensitive = true
}
variable "proxmox_node_name" {
  type    = string
  default = "homelab"
}
variable "proxmox_ssh_address" {
  type    = string
  default = "homelab.bevz.net"
}
variable "proxmox_ssh_port" {
  type      = number
  sensitive = true
}
variable "vm_template_id" {
  type    = number
  default = 9013
}
variable "vm_bridge" {
  type    = string
  default = "vmbr0"
}
variable "proxmox_snippet_storage" {
  type    = string
  default = "local"
}

# --- Ansible Variables ---
variable "vm_user" {
  type    = string
  default = ""
}
variable "ssh_public_key" {
  type    = string
  default = "ssh-rsa AAAA..."
}

# --- Counters (Only 1 VM) ---
variable "control_plane_count" {
  description = "Number of Harbor VMs"
  type        = number
  default     = 1
}

# --- VM Specifications ---
variable "vm_id" {
  description = "VMID you want to assign"
  type        = number
  default     = 150 # 👈 *** YOUR VMID ***
}
variable "cp_cores" {
  type    = number
  default = 4
}
variable "cp_memory" {
  type    = number
  default = 8192
}
variable "cp_disk_size" {
  type    = number
  default = 100 # (100G for cache)
}
variable "control_plane_ips" {
  description = "List of static IPs for Harbor VM"
  type        = list(string)
  default     = ["10.10.10.103"] # 👈 *** YOUR IP ADDRESS ***
}
variable "gateway" {
  type    = string
  default = "10.10.10.1"
}
variable "ip_prefix_length" {
  type    = number
  default = 24
}
variable "vm_started" {
  type    = bool
  default = true
}
variable "vm_dns_server" {
  type    = string
  default = "10.10.10.100"
}
