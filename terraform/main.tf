resource "proxmox_download_file" "talos" {
  content_type        = "iso"
  datastore_id        = var.datastore_id
  node_name           = var.proxmox_node
  url                 = var.talos_image_url
  file_name           = var.talos_image_file_name
  overwrite_unmanaged = var.talos_image_overwrite_unmanaged
  upload_timeout      = var.talos_image_upload_timeout
  verify              = false
}

# One VM per entry in var.nodes. The map key is the VM name and the Talos hostname.
resource "proxmox_virtual_environment_vm" "node" {
  for_each   = var.nodes
  depends_on = [proxmox_download_file.talos]

  name        = each.key
  description = "Managed by terraform"
  tags        = ["k8s", "talos", local.role_tag[each.value.role]]

  node_name = var.proxmox_node

  boot_order = ["scsi0", "ide3"]

  vm_id = each.value.vm_id

  agent {
    enabled = true
  }

  stop_on_destroy = true

  cpu {
    cores = local.node_specs[each.key].cores
    type  = "host"
  }

  memory {
    dedicated = local.node_specs[each.key].memory
  }

  disk {
    datastore_id = var.disk_datastore_id
    interface    = "scsi0"
    size         = local.node_specs[each.key].disk_size
  }

  cdrom {
    file_id   = proxmox_download_file.talos.id
    interface = "ide3"
  }

  # Kept unchanged so that migrating existing VMs is a no-op. The Talos metal
  # ISO does not read cloud-init, so this DHCP setting has no effect: the static
  # IP comes from the Talos machine config (see talos.tf).
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_device {
    bridge = "vmbr0"
    # Optional fixed MAC so a DHCP reservation can hand out the node's static IP
    # while it boots the ISO in maintenance mode. null lets Proxmox pick one.
    mac_address = each.value.mac_address
  }
}

# State migration from the pre-for_each resources. These map the default
# topology only. If you had more than 2 workers (count > 2), add a matching
# block for each extra one, e.g. workers[2] -> node["talos-worker-03"], before
# running plan. Otherwise Terraform will destroy and recreate those VMs.
moved {
  from = proxmox_virtual_environment_vm.control
  to   = proxmox_virtual_environment_vm.node["talos-ctrl"]
}

moved {
  from = proxmox_virtual_environment_vm.workers[0]
  to   = proxmox_virtual_environment_vm.node["talos-worker-01"]
}

moved {
  from = proxmox_virtual_environment_vm.workers[1]
  to   = proxmox_virtual_environment_vm.node["talos-worker-02"]
}
