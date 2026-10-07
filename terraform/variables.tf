# Proxmox Connection Variables
variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL (e.g. https://10.0.0.6:8006/) — do not include /api2/json"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name where the VMs will be created"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!token-name). Use this instead of username/password for better security"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret. Use this instead of password for better security"
  type        = string
  sensitive   = true
}

variable "talos_image_url" {
  description = "URL of the Talos ISO image to download into the Proxmox datastore"
  type        = string
}

variable "talos_image_file_name" {
  description = "Target filename for the downloaded Talos ISO in the Proxmox datastore"
  type        = string
}

variable "talos_image_overwrite_unmanaged" {
  description = "Replace an existing unmanaged ISO file with the same name when downloading"
  type        = bool
}

variable "talos_image_upload_timeout" {
  description = "Timeout in seconds for downloading the Talos ISO"
  type        = number
  default     = 900
}

variable "datastore_id" {
  description = "Proxmox datastore ID where the Talos ISO is stored"
  type        = string
  default     = "local"
}

variable "disk_datastore_id" {
  description = "Proxmox datastore ID for the VM disk"
  type        = string
  default     = "local-lvm"
}

# Cluster topology
variable "nodes" {
  description = <<-EOT
    Cluster nodes keyed by name. The key is used as the VM name and the Talos hostname.
    role: "controlplane" or "worker". ip: static IPv4 address (no prefix length).
    mac_address: optional fixed MAC (for DHCP reservations). If cores/memory (MiB)/disk_size (GB)
    are omitted, role defaults apply: controlplane 2/2048/20, worker 1/3072/20.
  EOT
  type = map(object({
    role        = string
    vm_id       = number
    ip          = string
    mac_address = optional(string)
    cores       = optional(number)
    memory      = optional(number)
    disk_size   = optional(number)
  }))

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node's role must be \"controlplane\" or \"worker\"."
  }

  validation {
    condition     = length([for n in values(var.nodes) : n if n.role == "controlplane"]) >= 1
    error_message = "At least one node must have role \"controlplane\"."
  }

  validation {
    # cidrnetmask() only accepts IPv4 CIDRs, so this rejects malformed and IPv6 addresses.
    condition     = alltrue([for n in values(var.nodes) : can(cidrnetmask("${n.ip}/32"))])
    error_message = "Each node's ip must be a valid IPv4 address without a prefix length (e.g. 192.0.2.10)."
  }

  validation {
    condition     = length(distinct([for n in values(var.nodes) : n.ip])) == length(var.nodes)
    error_message = "Node IPs must be unique."
  }

  validation {
    condition     = length(distinct([for n in values(var.nodes) : n.vm_id])) == length(var.nodes)
    error_message = "Node vm_ids must be unique."
  }

  validation {
    condition     = alltrue([for k in keys(var.nodes) : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", k))])
    error_message = "Node names (map keys) must be valid lowercase hostnames (a-z, 0-9, '-')."
  }

  validation {
    condition = alltrue([
      for n in values(var.nodes) : n.mac_address == null || can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", n.mac_address))
    ])
    error_message = "mac_address must look like AA:BB:CC:DD:EE:FF."
  }
}

# Node network (applied via the Talos machine config)
variable "node_network_prefix" {
  description = "Prefix length of the node subnet, e.g. 24 for a /24"
  type        = number

  validation {
    condition     = var.node_network_prefix >= 1 && var.node_network_prefix <= 32 && floor(var.node_network_prefix) == var.node_network_prefix
    error_message = "node_network_prefix must be an integer between 1 and 32."
  }
}

variable "node_gateway" {
  description = "Default IPv4 gateway for the nodes"
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.node_gateway}/32"))
    error_message = "node_gateway must be a valid IPv4 address."
  }
}

variable "node_nameservers" {
  description = "DNS servers for the nodes. Empty uses the Talos defaults."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ns in var.node_nameservers : can(cidrnetmask("${ns}/32"))])
    error_message = "Each nameserver must be a valid IPv4 address."
  }
}

# Talos / Kubernetes
variable "cluster_name" {
  description = "Talos/Kubernetes cluster name"
  type        = string
  default     = "talos"
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint. null defaults to https://<first control-plane IP>:6443."
  type        = string
  default     = null

  validation {
    condition     = var.cluster_endpoint == null || can(regex("^https://[^/]+:[0-9]+$", var.cluster_endpoint))
    error_message = "cluster_endpoint must look like https://<host>:<port>."
  }
}

variable "talos_version" {
  description = "Talos version installed on the nodes (installer image tag). Should match the ISO in talos_image_url."
  type        = string
  default     = "v1.14.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must look like v1.14.1."
  }
}

variable "talos_config_contract" {
  description = <<-EOT
    Talos machine-config contract used to generate configs and secrets. Pinned to v1.13 because
    the v1.14 contract moves kubelet/CNI/hostname settings into new documents that conflict with
    this repo's patches. Do not change it on an existing cluster.
  EOT
  type        = string
  default     = "v1.13"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy (default for Talos v1.14)"
  type        = string
  default     = "v1.37.0"
}

variable "talos_schematic_id" {
  description = <<-EOT
    Talos Image Factory schematic ID used for the installer image. Use the same schematic as the ISO
    so the system extensions survive installation. The default is the vanilla (no extensions) schematic.
  EOT
  type        = string
  default     = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
}

variable "talos_installer_image" {
  description = "Full installer image reference. Overrides talos_schematic_id/talos_version when set."
  type        = string
  default     = null
}

variable "talos_install_disk" {
  description = "Disk Talos installs to. /dev/sda is the scsi0 disk on Proxmox (the Talos default)."
  type        = string
  default     = "/dev/sda"
}

variable "tailscale_authkey" {
  description = "Tailscale auth key. When set, the Tailscale extension is configured on every node (the image must include the tailscale extension). null disables it."
  type        = string
  default     = null
  sensitive   = true
}
