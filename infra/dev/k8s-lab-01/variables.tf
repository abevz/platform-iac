# --- ПЕРЕМЕННЫЕ ДЛЯ ПРОВАЙДЕРА (ИЗ SOPS) ---
variable "proxmox_api_url" {
  type      = string
  sensitive = true
}
variable "proxmox_api_token_id" {
  type      = string
  sensitive = true
}
variable "proxmox_api_token_secret" {
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
  description = "Нода Proxmox, на которой будут созданы VM"
  type        = string
  default     = "pve" # Укажите Вашу целевую ноду
}

variable "vm_template_id" {
  description = "Имя 'Золотого Образа' (Cloud-Init)"
  type        = number
  default     = "9420" # Ваш шаблон
}

variable "vm_bridge" {
  description = "Сетевой мост (напр. vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_snippet_storage" {
  description = "Хранилище для Cloud-Init Snippets (напр. 'local')"
  type        = string
  default     = "local" # Хранилище, где лежат сниппеты
}

# --- Переменные для Ansible ---
variable "vm_user" {
  description = "Имя пользователя для Ansible"
  type        = string
  default     = "abevz"
}

variable "ssh_public_key" {
  description = "Содержимое cpc_deployment_key.pub"
  type        = string
  # Вставьте сюда содержимое Вашего cpc_deployment_key.pub
  default     = "ssh-rsa AAAA..." 
}

# --- Счетчики ---
variable "control_plane_count" {
  description = "Количество Control Plane нод"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Количество Worker нод"
  type        = number
  default     = 2
}

# --- Спецификации VM ---
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
