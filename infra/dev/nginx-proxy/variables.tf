# /infra/dev/nginx-proxy/variables.tf

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
  description = "Proxmox node name"
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
  default     = 9420
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

# --- Single VM Specifications ---
variable "vm_id" {
  description = "VM ID to assign"
  type        = number
  default     = 105
}
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
variable "vm_ip_address" {
  description = "Static IP for nginx-proxy"
  type        = string
  default     = "10.10.10.105"
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
  description = "Whether VM should be running"
  type        = bool
  default     = true
}
variable "vm_dns_server" {
  description = "DNS server IP address (Pi-hole)"
  type        = string
  default     = "10.10.10.100"
}
variable "proxmox_ssh_port" {
  description = "SSH port for Tofu connection to Proxmox node (passed via iac-wrapper)"
  type        = number
}
