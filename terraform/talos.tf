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

  # Ordering: Terraform tracks dependencies per resource, not per instance, so
  # every apply waits for all VMs. replace_triggered_by doesn't add ordering. It
  # only re-runs this node's apply when its VM is replaced (new empty disk =
  # maintenance mode again). In-place VM edits don't trigger it.
  depends_on = [proxmox_virtual_environment_vm.node]

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.node[each.key].id]
  }

  timeouts = {
    create = "15m"
  }
}

# Bootstrap etcd exactly once, on local.bootstrap_node_name (var.bootstrap_node,
# or the first control-plane key in sorted order).
# Ordering: dependencies are per resource, so bootstrap waits for ALL config
# applies, workers included. This can't deadlock: an apply to a maintenance-mode
# node returns once the config is accepted, without waiting to join the cluster.
#
# Not re-run automatically: if the bootstrap node's VM is recreated in a
# single-control-plane cluster, run
#   terraform apply -replace=talos_machine_bootstrap.this
# Auto re-bootstrap would split etcd in a multi-control-plane cluster.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip

  depends_on = [talos_machine_configuration_apply.node]

  timeouts = {
    create = "15m"
  }

  lifecycle {
    # Bootstrap is a one-shot. If the bootstrap node later changes (another
    # control plane sorts first, or a new IP), keep the recorded value. In
    # provider 0.12.0 node/endpoint are not RequiresReplace, so this mainly
    # prevents misleading diffs and guards against a future provider change.
    ignore_changes = [node, endpoint]
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
