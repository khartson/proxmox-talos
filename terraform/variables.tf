# Proxmox Connection Variables
variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL (e.g. https://10.0.0.6:8006/) — do not include /api2/json"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name where the container will be created"
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
  description = "Talos ISO image URL used when download_talos_image is true"
  type        = string
  }

variable "talos_image_file_name" {
  description = "Target filename for the downloaded talos template in Proxmox datastore"
  type        = string
}

variable "talos_image_overwrite_unmanaged" {
  description = "Replace an existing unmanaged template file with the same name when downloading"
  type        = bool
}

variable "talos_image_upload_timeout" {
  description = "Timeout in seconds for downloading the talos template"
  type        = number
  default     = 900
}

variable "datastore_id" {
  description = "Proxmox datastore ID for the VM template"
  type        = string
  default     = "local"
}

variable "disk_datastore_id" {
  description = "Proxmox datastore ID for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "worker_count" {
  description = "Number of worker VMs to create"
  type        = number
  default     = 2
}
