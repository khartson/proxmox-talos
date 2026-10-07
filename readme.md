# Talos Linux on Proxmox

Terraform that creates Talos Linux VMs on Proxmox VE and bootstraps them into a
Kubernetes cluster ([Talos](https://www.talos.dev/) +
[siderolabs/talos provider](https://registry.terraform.io/providers/siderolabs/talos)).
Work in progress. The CNI (Cilium) and Longhorn are not installed yet.

## Repository layout

```
terraform/
  versions.tf                 # Terraform + provider version constraints
  providers.tf                # bpg/proxmox provider configuration
  main.tf                     # Talos ISO download, one VM per node (for_each), moved blocks
  talos.tf                    # Talos secrets, machine configs, apply, bootstrap, kubeconfig
  locals.tf                   # Role sizing defaults, control-plane/bootstrap selection
  variables.tf                # Input variables (with validation)
  outputs.tf                  # Node info, cluster endpoint, talosconfig/kubeconfig (sensitive)
  terraform.tfvars.example    # Template for your terraform.tfvars
  .terraform.lock.hcl         # Locked provider versions (committed)
config/
  cni.yaml                    # Cluster patch: CNI "none" (Cilium installed separately)
  patch-control.yaml          # Control-plane role patch (kubelet reservations)
  patch-worker.yaml           # Worker role patch (Longhorn kubelet mount)
  patch-node.yaml.tftpl       # Per-node template: hostname, static IP, install disk/image
  patch-tailscale.yaml.tftpl  # Tailscale extension config (only if tailscale_authkey is set)
```

## Prerequisites

- Terraform >= 1.9 (variable validations reference other variables)
- `talosctl` v1.14.x (optional, for day-2 operations)
- A Proxmox VE API token with permission to manage VMs and datastore content
- A Talos v1.14 ISO URL from the [Talos Image Factory](https://factory.talos.dev/),
  of the form `https://factory.talos.dev/image/<schematic>/<version>/metal-amd64.iso`.
  Include the `qemu-guest-agent` extension, because the VMs enable the agent and
  Proxmox waits for it. Add `tailscale` if you set `tailscale_authkey`. The
  schematic and version are parsed from the URL to build the installer image,
  so the installed OS keeps the same extensions. For a non-Factory URL, set
  `talos_schematic_id` + `talos_version` or `talos_installer_image`; validation
  fails otherwise.
- One static IPv4 address per node, reachable from where you run Terraform

## Supplying variables

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored, so it won't be committed
$EDITOR terraform.tfvars                       # nodes, IPs, gateway, ISO URL, ...
```

You can pass the API token as environment variables instead of writing it to disk:
`TF_VAR_proxmox_api_token_id` and `TF_VAR_proxmox_api_token_secret`. A value set
in `terraform.tfvars` overrides the matching `TF_VAR_*` variable, so keep the
token lines in `terraform.tfvars` commented out (as in the example) when using
env vars. The same applies to `TF_VAR_tailscale_authkey`.

Nodes are defined in the `nodes` map. The key is the VM name and the Talos
hostname. Example:

```hcl
nodes = {
  "talos-ctrl"      = { role = "controlplane", vm_id = 1000, ip = "192.0.2.10" }
  "talos-worker-01" = { role = "worker",       vm_id = 2001, ip = "192.0.2.21" }
}
```

`cores`, `memory` (MiB) and `disk_size` (GB) are optional. The role defaults
are control plane 2 / 2048 / 20 and worker 1 / 3072 / 20.

### Multiple control-plane nodes

- `cluster_endpoint` is required once there is more than one control-plane
  node. Use a VIP or DNS name that doesn't change when nodes are added or
  removed. With a single control plane it defaults to `https://<its IP>:6443`.
  When you add the second one, set it to that same URL (or migrate
  deliberately), because changing it re-pushes the endpoint to every node.
- Etcd is bootstrapped once, on `bootstrap_node` (default: the first
  control-plane key in sorted order). Set `bootstrap_node` explicitly before
  adding control-plane nodes. The bootstrap resource ignores later changes to
  its node, so bootstrap never runs on a second control plane.

## Cluster bootstrap

```sh
terraform init
terraform plan
terraform apply
```

`apply` runs these steps in order:

1. Downloads the Talos ISO and creates one VM per node. The VMs boot the ISO into
   maintenance mode.
2. Generates the cluster secrets and one machine config per node: `config/cni.yaml`,
   the role patch, the per-node patch (hostname, static IP, install disk/image) and,
   optionally, the Tailscale patch.
3. Applies each config to its node at the node's **static IP**. The node installs
   Talos to disk and reboots from it.
4. Bootstraps etcd on the first control-plane node, sorted by name.
5. Retrieves the admin kubeconfig.

There is no health check at the end. With CNI `none`, nodes stay `NotReady`
until Cilium is installed in a later phase.

### First boot: the node must be reachable at its static IP

In maintenance mode the ISO uses DHCP, but Terraform connects to the node's
static IP. Set `mac_address` for each node and create a DHCP reservation that
hands out that same IP. Otherwise the config apply times out after 15 minutes.

### Getting talosconfig and kubeconfig

Both are sensitive outputs and are never written to disk by Terraform. Write
them to gitignored paths yourself:

```sh
# umask 077 in a subshell: the files are created owner-only from the start
(umask 077
 terraform output -raw talosconfig > ../config/talosconfig
 terraform output -raw kubeconfig  > ../config/kubeconfig)
export TALOSCONFIG=$PWD/../config/talosconfig KUBECONFIG=$PWD/../config/kubeconfig
```

### Migrating from the old `control`/`workers` resources

In `terraform.tfvars`, **remove `worker_count`**, because it no longer exists and
an undeclared variable warns in tfvars and errors with `-var`. Add the `nodes`
map, `node_network_prefix` and `node_gateway` (see the example).

`main.tf` has `moved` blocks that map the old `control` resource and `workers[0]`
and `workers[1]` to `node["talos-ctrl"]`, `node["talos-worker-01"]` and
`node["talos-worker-02"]`. Keep those keys and vm_ids in `nodes`, as the example
does. If you had more than 2 workers, add one more `moved` block per extra worker
before running `plan`, or Terraform will recreate those VMs. If the cluster was
bootstrapped by hand, Terraform's new secrets will not match it. Either rebuild
the cluster, or import the existing secrets (see the talos provider docs).

### Recreating VMs

If a VM is replaced, its config apply is re-run automatically
(`replace_triggered_by`). Bootstrap is **not** re-run automatically. If you
recreate the bootstrap control-plane node of a single-control-plane cluster,
run `terraform apply -replace=talos_machine_bootstrap.this`. Never do this
while other control-plane nodes still have a healthy etcd.

When recreating any control-plane node in a **multi-control-plane** cluster,
remove its old etcd member first. Otherwise the stale member stays in etcd and
counts against quorum:

```sh
talosctl -n <healthy-cp-ip> etcd members                     # find the old member ID
talosctl -n <healthy-cp-ip> etcd remove-member <member-id>
# or, before destroying the node: talosctl -n <node-ip> reset --graceful
```

## Secrets and state

The Terraform state now holds the **cluster CA and keys, machine secrets,
talosconfig and admin kubeconfig**, plus the Proxmox token and the Tailscale
key if you set them. Keep `terraform.tfstate` local and gitignored (the default
here), or move it to an encrypted remote backend with restricted access.
Saved plans (`terraform plan -out=...`) contain the same secrets in plaintext.
`*.tfplan` and `tfplan` are gitignored, but delete plan files after use.

Never commit `terraform.tfvars`/`*.tfvars.json`, `*.tfstate`, `talosconfig`,
`kubeconfig` or `secrets.yaml`. `.gitignore` ignores these in any directory.
It also ignores `controlplane.yaml`/`worker.yaml` where `talosctl gen config`
writes them (repo root, `config/`, `terraform/`).

## Config contract: migrating to v1.14 (TODO)

Configs are generated with the **v1.13** machine-config contract
(`talos_config_contract`), because the v1.14 contract rejects the current
patches. To migrate later:

1. Move the kubelet `extraConfig` (reservations) from `config/patch-control.yaml`
   into a `KubeletConfig` document (`config:` field).
2. Express CNI `none` in the v1.14 network documents (`KubeNetworkConfig`) and
   delete the default `KubeFlannelCNIConfig` document (`$patch: delete`).
3. Move the Longhorn `/var/lib/longhorn` bind mount from
   `machine.kubelet.extraMounts` to a volume/mount document (e.g.
   `UserVolumeConfig`). The v1.14 `KubeletConfig` has no `extraMounts`.
4. Bump `talos_config_contract`. The machine-config data source picks up the
   change; `talos_machine_secrets` also uses it but ignores changes, so the
   cluster secrets are not regenerated.
5. Render and check each node with `talosctl validate --mode metal`, then apply.
   Consider `apply_mode = "staged_if_needing_reboot"` (or staged) so nodes don't
   reboot unexpectedly.

## Manual fallback

To bootstrap without the Talos resources, use `talosctl gen config` with
`--talos-version v1.13 -o config/` and the patches in `config/`. Render
`patch-node.yaml.tftpl` by hand. Then run `talosctl apply-config --insecure`
against each node and `talosctl bootstrap` against one control-plane node.
