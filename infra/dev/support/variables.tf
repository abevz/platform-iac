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

variable "vm_user" {
  type    = string
  default = ""
}

variable "ssh_public_key" {
  type    = string
  default = "ssh-rsa AAAA..."
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

# --- Support VM Settings ---
variable "vm_id" {
  description = "VM ID for Support server"
  type        = number
  default     = 106
}

variable "vm_ip" {
  description = "Static IP for Support server"
  type        = string
  default     = "<SERVICE-IP-106>"
}

variable "cp_cores" {
  type    = number
  default = 2
}

variable "cp_memory" {
  type    = number
  default = 2048
}

variable "cp_disk_size" {
  type    = number
  default = 32
}
