output "ansible_inventory_data" {
  value = jsonencode({
    _meta = {
      hostvars = {
        "raspberry-pi" = {
          ansible_host = var.pi_ip
          ansible_user = var.pi_user
          ansible_port = 22
          node_role    = "vpn_gateway"
        }
      }
    },
    all          = { children = ["vpn_gateways"] },
    vpn_gateways = { hosts = ["raspberry-pi"] }
  })
}
