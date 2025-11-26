# Минимум переменных, нужны только для провайдера (чтобы tofu init не упал)
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

# Данные существующей Raspberry Pi
variable "pi_ip" {
  type    = string
  default = "10.10.10.100"
}
variable "pi_user" {
  type    = string
  default = "abevz" # Или root, смотря как настроено
}
