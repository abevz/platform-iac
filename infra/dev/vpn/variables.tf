# Minimal variables needed for provider (to allow tofu init)
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

# Existing Raspberry Pi settings
variable "pi_ip" {
  type    = string
  default = "<PIHOLE-IP>"
}
variable "pi_user" {
  type    = string
  default = ""
}
