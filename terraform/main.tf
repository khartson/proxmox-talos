terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.53.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url

  api_token = var.proxmox_api_token_id != "" && var.proxmox_api_token_secret != "" ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null

}

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

resource "proxmox_virtual_environment_vm" "control" {
    depends_on = [proxmox_download_file.talos]
    
    name        = "talos-ctrl"
    description = "Managed by terraform"
    tags        = ["k8s", "talos", "control-plane"]

    node_name   = var.proxmox_node 

    boot_order = ["scsi0", "ide3"]

    vm_id       = 1000

    agent {
        enabled = true
    }

    stop_on_destroy = true

    cpu {
        cores = 2 
        type  = "host"
    }

    memory { 
        dedicated = 2048
    }

    disk {
        datastore_id = var.disk_datastore_id
        interface    = "scsi0"
        size         = 20
    }

    cdrom {
        file_id = proxmox_download_file.talos.id
        interface = "ide3"
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    network_device {
        bridge = "vmbr0"
    }
}

resource "proxmox_virtual_environment_vm" "workers" {
    depends_on = [proxmox_download_file.talos]
    
    count       = var.worker_count 
    name        = "talos-worker-0${count.index + 1}"
    description = "Managed by terraform"
    tags        = ["k8s", "talos", "worker"]

    node_name   = var.proxmox_node 
    
    boot_order = ["scsi0", "ide3"]

    vm_id       = 2000 + (count.index + 1) 

    agent {
        enabled = true
    }

    stop_on_destroy = true

    cpu {
        cores = 1 
        type  = "host"
    }

    memory { 
        dedicated = 3072 
    }

    disk {
        datastore_id = var.disk_datastore_id
        interface    = "scsi0"
        size         = 20
    }

    cdrom {
        file_id = proxmox_download_file.talos.id
        interface = "ide3"
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    network_device {
        bridge = "vmbr0"
    }
}
