# /infra/dev/nginx-proxy/variables.tf

# --- ПЕРЕМЕННЫЕ ДЛЯ ПРОВАЙДЕРА (ИЗ SOPS) ---
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
  description = "Нода Proxmox"
  type        = string
  default     = "homelab"
}
variable "proxmox_ssh_address" {
  description = "FQDN или IP для SSH-подключения к ноде Proxmox"
  type        = string
  default     = "homelab.example.com"
}
variable "vm_template_id" {
  description = "Имя 'Золотого Образа' (Cloud-Init)"
  type        = number
  default     = 9420 # (ID Вашего шаблона)
}
variable "vm_bridge" {
  description = "Сетевой мост (напр. vmbr0)"
  type        = string
  default     = "vmbr0"
}
variable "proxmox_snippet_storage" {
  description = "Хранилище для Cloud-Init Snippets"
  type        = string
  default     = "local"
}

# --- Переменные для Ansible ---
variable "vm_user" {
  description = "Имя пользователя для Ansible"
  type        = string
  default     = "ansible"
}
variable "ssh_public_key" {
  description = "Содержимое <ssh-private-key>.pub"
  type        = string
  default     = "ssh-rsa AAAA..." # (Вставьте Ваш ключ)
}

# --- ИСПРАВЛЕНО: Спецификации для ОДНОЙ VM ---
variable "vm_id" {
  description = "VMID, который Вы хотите назначить (напр., 102)"
  type        = number
  default     = 105 # 👈 Укажите нужный ID
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
  description = "Статический IP для nginx-proxy"
  type        = string
  default     = "192.0.2.105" # 👈 Укажите IP (без /24)
}
variable "gateway" {
  description = "Сетевой шлюз"
  type        = string
  default     = "192.0.2.1"
}
variable "ip_prefix_length" {
  description = "CIDR префикс (напр., 24 для /24)"
  type        = number
  default     = 24
}
variable "vm_started" {
  description = "VM должна быть запущена"
  type        = bool
  default     = true
}
variable "vm_dns_server" {
  description = "IP-адрес DNS-сервера (Pi-hole)"
  type        = string
  default     = "192.0.2.100"
}
