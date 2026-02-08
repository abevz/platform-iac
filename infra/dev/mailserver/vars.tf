variable "proxmox_host" {
  type    = string
  default = "<MAILSERVER-IP>"
}

variable "common" {
  type = map(string)
  default = {
    os_type       = "ubuntu"
    clone         = "ubuntu-2210-cloudinit-template"
    search_domain = "homelab.<your-dev-domain>.dev"
    nameserver    = "<LAN-GATEWAY-IP>"
  }
}

variable "mailserver" {
  type = map(map(string))
  default = {
    devmail = {
      id          = 5010
      cidr        = "<MAIL-NETWORK-IP>/24"
      cores       = 2
      gw          = "<LAN-GATEWAY-IP>"
      memory      = 2096
      disk        = "40G"
      target_node = "homelab"
    }
  }
}
