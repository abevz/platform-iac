variable "proxmox_host" {
  type    = string
  default = "10.10.10.124"
}

variable "common" {
  type = map(string)
  default = {
    os_type       = "ubuntu"
    clone         = "ubuntu-2210-cloudinit-template"
    search_domain = "homelab.bevz.dev"
    nameserver    = "10.10.10.1"
  }
}

variable "mailserver" {
  type = map(map(string))
  default = {
    devmail = {
      id          = 5010
      cidr        = "10.10.10.185/24"
      cores       = 2
      gw          = "10.10.10.1"
      memory      = 2096
      disk        = "40G"
      target_node = "homelab"
    }
  }
}
