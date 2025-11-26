# Мы не создаем ресурсов, так как Pi физическая.
# Этот файл нужен, чтобы Tofu не ругался на пустую директорию.
data "proxmox_virtual_environment_nodes" "list" {}
