# Talos cluster bootstrap. Flow:
#   VMs boot the Talos ISO (maintenance mode) -> machine config applied per node
#   -> etcd bootstrapped on one control-plane node -> kubeconfig retrieved.
# The CNI is intentionally "none" (config/cni.yaml). Cilium is installed in a
# later phase, so nodes stay NotReady until then.

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_config_contract

  lifecycle {
    # Replacing the secrets would mint a new cluster CA and orphan the running
    # cluster. Changing the contract on an existing cluster must be deliberate.
    ignore_changes = [talos_version]
  }
}

# Patches per node: cluster-wide CNI patch + role patch + per-node patch
# (hostname, static IP, install disk/image) + optional Tailscale patch.
# Kept in a local so it can be inspected with `terraform console`.
locals {
  node_config_patches = {
    for name, node in var.nodes : name => concat(
      [
        file("${path.module}/../config/cni.yaml"),
        file("${path.module}/../config/patch-${node.role == "controlplane" ? "control" : "worker"}.yaml"),
        templatefile("${path.module}/../config/patch-node.yaml.tftpl", {
          hostname        = name
          ip              = node.ip
          prefix          = var.node_network_prefix
          gateway         = var.node_gateway
          nameservers     = var.node_nameservers
          install_disk    = var.talos_install_disk
          installer_image = local.talos_installer_image
        }),
      ],
      var.tailscale_authkey == null ? [] : [
        templatefile("${path.module}/../config/patch-tailscale.yaml.tftpl", {
          authkey  = var.tailscale_authkey
          hostname = name
        }),
      ],
    )
  }
}

# One machine config per node (patches from local.node_config_patches).
data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = each.value.role
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_config_contract
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = local.node_config_patches[each.key]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = [for node in values(var.nodes) : node.ip]
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  # The node's static IP. On first boot the VM must already be reachable at it
  # (DHCP reservation via mac_address). See the README.
  node     = each.value.ip
  endpoint = each.value.ip

  # depends_on only accepts whole resources, so it orders every apply after all
  # VMs. The replace_triggered_by below adds the per-node edge and also re-applies
  # the config when this node's VM is recreated (new disk = maintenance mode again).
  depends_on = [proxmox_virtual_environment_vm.node]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.node[each.key].id]
  }

  timeouts = {
    create = "15m"
  }
}

# Bootstrap etcd exactly once, on the first control-plane node (sorted by name).
# `node` references that node's config-apply instance. This is the dependency
# on the control-plane config apply, scoped to that one instance (depends_on
# can't target a single for_each instance), so bootstrap doesn't wait on workers.
#
# Not re-run automatically: if the bootstrap node's VM is recreated in a
# single-control-plane cluster, run
#   terraform apply -replace=talos_machine_bootstrap.this
# Auto re-bootstrap would split etcd in a multi-control-plane cluster.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = talos_machine_configuration_apply.node[local.bootstrap_node_name].node
  endpoint             = local.bootstrap_node_ip

  timeouts = {
    create = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip

  depends_on = [talos_machine_bootstrap.this]
}

# No talos_cluster_health: with cni = none the nodes never become Ready until
# Cilium is installed (later phase), so a health check would block apply.
