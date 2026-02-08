variable "proxmox_host" {
  type    = string
  default = "192.0.2.124"
}

variable "common" {
  type = map(string)
  default = {
    os_type       = "ubuntu"
    clone         = "ubuntu-2210-cloudinit-template"
    search_domain = "homelab.dev.example.com"
    nameserver    = "192.0.2.1"
  }
}

variable "mailserver" {
  type = map(map(string))
  default = {
    devmail = {
      id          = 5010
      cidr        = "192.0.2.185/24"
      cores       = 2
      gw          = "192.0.2.1"
      memory      = 2096
      disk        = "40G"
      target_node = "homelab"
    }
  }
}
