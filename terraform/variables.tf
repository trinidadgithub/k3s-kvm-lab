variable "vm_memory_mb" {
  type    = number
  default = 2048
}

variable "vm_vcpu" {
  type    = number
  default = 2
}

variable "network_name" {
  type    = string
  default = "default"
}

variable "pool_path" {
  type    = string
  default = "/var/lib/libvirt/images/lab"
}

variable "base_image" {
  type    = string
  default = "/var/lib/libvirt/images/lab/base/ubuntu-24.04-server-cloudimg-amd64.img"
}
