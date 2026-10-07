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

  # Control-plane nodes sorted by key. The bootstrap node is var.bootstrap_node
  # if set, otherwise the first sorted key. Pin it before adding more control
  # planes (see the README). The bootstrap resource also ignores later changes.
  control_plane_names = sort([for name, node in var.nodes : name if node.role == "controlplane"])
  control_plane_ips   = [for name in local.control_plane_names : var.nodes[name].ip]
  bootstrap_node_name = coalesce(var.bootstrap_node, local.control_plane_names[0])
  bootstrap_node_ip   = var.nodes[local.bootstrap_node_name].ip

  # Only used as the default with a single control plane. With more, the
  # cluster_endpoint validation requires an explicit value.
  cluster_endpoint = coalesce(var.cluster_endpoint, "https://${local.control_plane_ips[0]}:6443")

  # Installer image written to machine.install.image. It must come from the
  # same Image Factory schematic as the ISO, or the extensions
  # (qemu-guest-agent, tailscale, ...) are lost after install and on upgrades.
  # Schematic and version are parsed from talos_image_url
  #   https://factory.talos.dev/image/<schematic>/<version>/metal-amd64.iso
  # and the talos_schematic_id / talos_version variables override them. The
  # talos_installer_image validation fails early if neither source works.
  talos_image_url_parts = try(
    regex("factory\\.talos\\.dev/image/([0-9a-f]{64})/(v[0-9]+\\.[0-9]+\\.[0-9]+)/", var.talos_image_url),
    [null, null],
  )
  talos_schematic_id = var.talos_schematic_id != null ? var.talos_schematic_id : local.talos_image_url_parts[0]
  talos_version      = var.talos_version != null ? var.talos_version : local.talos_image_url_parts[1]
  talos_installer_image = (
    var.talos_installer_image != null ? var.talos_installer_image :
    "factory.talos.dev/metal-installer/${local.talos_schematic_id}:${local.talos_version}"
  )
}
