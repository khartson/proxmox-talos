output "talos_iso_file_id" {
  description = "Proxmox file ID of the downloaded Talos ISO"
  value       = proxmox_download_file.talos.id
}

output "control_plane_vm" {
  description = "VM ID and name of the control-plane VM"
  value = {
    vm_id = proxmox_virtual_environment_vm.control.vm_id
    name  = proxmox_virtual_environment_vm.control.name
  }
}

output "worker_vms" {
  description = "VM IDs and names of the worker VMs"
  value = [
    for vm in proxmox_virtual_environment_vm.workers : {
      vm_id = vm.vm_id
      name  = vm.name
    }
  ]
}
