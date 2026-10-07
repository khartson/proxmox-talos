locals {
  # Per-role sizing defaults. These reproduce the original hardcoded VM values.
  role_defaults = {
    controlplane = { cores = 2, memory = 2048, disk_size = 20 }
    worker       = { cores = 1, memory = 3072, disk_size = 20 }
  }

  # Proxmox tag per role (unchanged from the original resources).
  role_tag = {
    controlplane = "control-plane"
    worker       = "worker"
  }

  # Effective VM sizing per node: explicit values win over role defaults.
  node_specs = {
    for name, node in var.nodes : name => {
      cores     = coalesce(node.cores, local.role_defaults[node.role].cores)
      memory    = coalesce(node.memory, local.role_defaults[node.role].memory)
      disk_size = coalesce(node.disk_size, local.role_defaults[node.role].disk_size)
    }
  }

  # Control-plane nodes sorted by key, so the bootstrap node is deterministic.
  control_plane_names = sort([for name, node in var.nodes : name if node.role == "controlplane"])
  control_plane_ips   = [for name in local.control_plane_names : var.nodes[name].ip]
  bootstrap_node_name = local.control_plane_names[0]
  bootstrap_node_ip   = var.nodes[local.bootstrap_node_name].ip

  cluster_endpoint = coalesce(var.cluster_endpoint, "https://${local.control_plane_ips[0]}:6443")

  # Installer image written to machine.install.image. It should come from the
  # same Image Factory schematic as the ISO, or the extensions
  # (qemu-guest-agent, tailscale, ...) are lost after install and on upgrades.
  talos_installer_image = coalesce(
    var.talos_installer_image,
    "factory.talos.dev/metal-installer/${var.talos_schematic_id}:${var.talos_version}",
  )
}
