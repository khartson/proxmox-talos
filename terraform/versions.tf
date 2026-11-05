terraform {
  # 1.9+: variable validations reference other variables (installer image,
  # bootstrap_node, cluster_endpoint, gateway subnet checks).
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # bpg/proxmox is pre-1.0 and ships breaking changes in minor releases,
      # so only allow patch updates within the tested 0.116.x line.
      version = "~> 0.116.0"
    }
    talos = {
      source = "siderolabs/talos"
      # 0.12.x is built against Talos machinery v1.14 (matches talosctl v1.14.x).
      # Minor releases track Talos minors, so only allow patch updates.
      version = "~> 0.12.0"
    }
  }
}
