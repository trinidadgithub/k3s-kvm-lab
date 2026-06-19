packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

locals {
  seed_iso = "./seed.iso"
}

source "qemu" "ubuntu2404" {
  iso_url             = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  iso_checksum        = "sha256:9fa17e6ba43609bdcf9929b7f73bf2de2a54f65cc4a9e2b4f52ffe1d033c62a0"
  disk_image          = true

  output_directory    = "output-ubuntu2404"
  format              = "qcow2"
  accelerator         = "kvm"
  headless            = true
  vm_name             = "ubuntu-24.04-lab-base"

  ssh_username        = "ubuntu"
  ssh_private_key_file = "~/.ssh/id_ed25519"

  qemuargs = [
    ["-cdrom", local.seed_iso]
  ]

  shutdown_timeout = "30s"

  boot_wait         = "15s"
  boot_command     = ["<wait>"]

  disk_size         = "20G"
}

build {
  sources = ["source.qemu.ubuntu2404"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo apt-get install -y -qq qemu-guest-agent curl vim git",
      "sudo systemctl enable --now qemu-guest-agent",
      "sudo apt-get clean",
      "sudo truncate -s 0 /etc/machine-id"
    ]
  }
}
