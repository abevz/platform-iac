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
  default     = "homelab.<your-domain>.com"
}

variable "proxmox_ssh_port" {
  description = "SSH port for Proxmox node"
  type        = number
}

variable "proxmox_snippet_storage" {
  description = "Storage for Cloud-Init snippets"
  type        = string
  default     = "local"
}

variable "vm_template_id" {
  description = "VM template ID (Cloud-Init golden image)"
  type        = number
  default     = 9420
}

variable "vm_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vm_user" {
  description = "Ansible SSH username"
  type        = string
  default     = "abevz"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
  default     = "ssh-rsa AAAA..."
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "10.10.10.1"
}

variable "ip_prefix_length" {
  description = "Network prefix length"
  type        = number
  default     = 24
}

variable "vm_dns_server" {
  description = "DNS server IP"
  type        = string
  default     = "10.10.10.100"
}

variable "vm_started" {
  description = "Whether VM should be running"
  type        = bool
  default     = true
}

variable "vm_cores" {
  description = "CPU cores"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "vm_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 40
}

variable "nodes_count" {
  description = "Number of server nodes"
  type        = number
  default     = 3
}

variable "vm_ips" {
  type    = list(string)
  default = ["10.10.10.221", "10.10.10.222", "10.10.10.223"]
}
