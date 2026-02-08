# infra/dev/jenkins/variables.tf
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
  default = "homelab.<your-domain>.com"
}
variable "proxmox_ssh_port" {
  type      = number
  sensitive = true
}
variable "vm_template_id" {
  type    = number
  default = 9420
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

# --- VM Specifications ---
variable "vm_id" {
  description = "VM ID"
  type        = number
  default     = 109
}
variable "cp_cores" {
  type    = number
  default = 4
}
variable "cp_memory" {
  type    = number
  default = 8192 # 8GB
}
variable "cp_disk_size" {
  type    = number
  default = 60 # 60G
}
variable "control_plane_ips" {
  description = "Static IP for Jenkins"
  type        = list(string)
  default     = ["<JENKINS-IP>"]
}
variable "gateway" {
  type    = string
  default = "<LAN-GATEWAY-IP>"
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
  default = "<PIHOLE-IP>"
}
