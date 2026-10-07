terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # bpg/proxmox is pre-1.0 and ships breaking changes in minor releases,
      # so only allow patch updates within the tested 0.116.x line.
      version = "~> 0.116.0"
    }
  }
}
