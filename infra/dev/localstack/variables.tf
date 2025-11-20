# infra/dev/localstack/variables.tf
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
  default = "homelab.example.com"
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
  default = "abevz"
}
variable "ssh_public_key" {
  type    = string
  default = "ssh-rsa AAAA..." # (Вставьте Ваш ключ)
}

# --- Спецификации VM ---
variable "vm_id" {
  description = "VMID"
  type        = number
  default     = 108 # 👈 НОВЫЙ ID
}
variable "cp_cores" {
  type    = number
  default = 4
}
variable "cp_memory" {
  type    = number
  default = 4096 # 4GB
}
variable "cp_disk_size" {
  type    = number
  default = 40 # 40G
}
variable "control_plane_ips" { # (Используем это имя для совместимости)
  description = "Статический IP для LocalStack"
  type        = list(string)
  default     = ["192.0.2.108"] # 👈 НОВЫЙ IP
}
variable "gateway" {
  type    = string
  default = "192.0.2.1"
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
  default = "192.0.2.100"
}
