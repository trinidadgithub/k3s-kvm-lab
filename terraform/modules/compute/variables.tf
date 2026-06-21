variable "vms" {
  type = map(object({
    memory = number
    vcpu   = number
    disk   = number
    mac    = string
  }))
}

variable "pool_name" {
  type = string
}

variable "network_name" {
  type = string
}

variable "base_image" {
  type = string
}

variable "cloudinit_data" {
  type = map(object({
    user_data = string
    meta_data = string
  }))
}
