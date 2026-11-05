output "talos_iso_file_id" {
  description = "Proxmox file ID of the downloaded Talos ISO"
  value       = proxmox_download_file.talos.id
}

output "nodes" {
  description = "Per-node VM ID, role and static IP"
  value = {
    for name, vm in proxmox_virtual_environment_vm.node : name => {
      vm_id = vm.vm_id
      name  = vm.name
      role  = var.nodes[name].role
      ip    = var.nodes[name].ip
    }
  }
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = local.cluster_endpoint
}

output "talosconfig" {
  description = "talosctl client config. Write it to a gitignored path: terraform output -raw talosconfig > ../config/talosconfig"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Admin kubeconfig. Write it to a gitignored path: terraform output -raw kubeconfig > ../config/kubeconfig"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}
