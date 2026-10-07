# Talos Linux on Proxmox

Terraform and Talos machine-config patches for a small Kubernetes cluster
running [Talos Linux](https://www.talos.dev/) on Proxmox VE. Work in progress.

## Repository layout

```
terraform/
  versions.tf                 # Terraform + provider version constraints
  providers.tf                # bpg/proxmox provider configuration
  main.tf                     # Talos ISO download, control-plane and worker VMs
  variables.tf                # Input variables
  outputs.tf                  # VM IDs/names, ISO file ID
  terraform.tfvars.example    # Template for your terraform.tfvars
  .terraform.lock.hcl         # Locked provider versions (committed)
config/
  cni.yaml                    # Cluster patch: disable default CNI (Cilium installed separately)
  patch-control.yaml          # Control-plane node patch (hostname, static IP, kubelet)
  patch-worker.yaml           # Worker node patch (hostname, static IP, Longhorn mount)
  patch-tailscale.yaml        # Tailscale extension service config
```

## Prerequisites

- Terraform >= 1.7
- `talosctl` matching the Talos version of your ISO
- A Proxmox VE API token with permission to manage VMs and datastore content
- A Talos ISO URL, e.g. from the [Talos Image Factory](https://factory.talos.dev/)
  with the extensions you need (qemu-guest-agent, tailscale, ...)

## Supplying variables

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored, so it won't be committed
$EDITOR terraform.tfvars
terraform init
terraform plan
```

You can pass the API token as environment variables instead of writing it to disk:
`TF_VAR_proxmox_api_token_id` and `TF_VAR_proxmox_api_token_secret`.

Never commit `terraform.tfvars`, `*.tfstate`, generated Talos configs
(`talosconfig`, `controlplane.yaml`, `worker.yaml`, `secrets.yaml`) or a
`kubeconfig`. `.gitignore` already covers them.

## Cluster bootstrap

Bootstrap is manual for now. After Terraform creates the VMs, generate the
machine configs with `talosctl gen config` using the patches in `config/`
(fill in the placeholders first). Then apply them to each node, run
`talosctl bootstrap` against the control plane, and install Cilium. Automating
these steps is planned.
