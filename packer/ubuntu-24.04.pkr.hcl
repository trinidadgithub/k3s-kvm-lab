packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

source "qemu" "ubuntu2404" {
  iso_url          = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
  iso_checksum     = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
  output_directory = "output-ubuntu2404"
  format           = "qcow2"
  accelerator      = "kvm"
  headless         = true
  ssh_username     = "ubuntu"
  ssh_password     = "ubuntu"
  vm_name          = "ubuntu-24.04-base"
  disk_size        = "12288"
}

build {
  sources = ["source.qemu.ubuntu2404"]
}
