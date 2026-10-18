moved {
  from = proxmox_virtual_environment_vm.minio_vm
  to   = proxmox_virtual_environment_vm.rustfs_vm
}

moved {
  from = proxmox_virtual_environment_file.minio_user_data
  to   = proxmox_virtual_environment_file.rustfs_user_data
}
