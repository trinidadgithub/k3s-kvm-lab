provider "libvirt" {
  uri = "qemu:///system"
}

locals {
  vms = {
    jumpbox = {
      memory = 2048
      vcpu   = 2
      disk   = 20 * 1024 * 1024 * 1024
    }
    k3s-master = {
      memory = 3072
      vcpu   = 2
      disk   = 25 * 1024 * 1024 * 1024
    }
    k3s-worker1 = {
      memory = 2048
      vcpu   = 2
      disk   = 20 * 1024 * 1024 * 1024
    }
  }

  ssh_public_key = trimspace(file(pathexpand("~/.ssh/id_rsa.pub")))
}

resource "libvirt_volume" "vm_disk" {
  for_each = local.vms

  name   = "${each.key}.qcow2"
  pool   = "lab"
  source = var.base_image
  format = "qcow2"

  provisioner "local-exec" {
    command = "sudo -n chown libvirt-qemu:kvm /var/lib/libvirt/images/lab/${self.name} && sudo -n chmod 660 /var/lib/libvirt/images/lab/${self.name}"
  }

}

resource "libvirt_cloudinit_disk" "commoninit" {
  for_each = local.vms

  name = "${each.key}-cloudinit.iso"
  pool = "lab"

  user_data = templatefile("${path.module}/../cloud-init/user-data.tftpl", {
    hostname   = each.key
    public_key = local.ssh_public_key
  })

  meta_data = templatefile("${path.module}/../cloud-init/meta-data.tftpl", {
    hostname = each.key
  })

  provisioner "local-exec" {
    command = "sudo -n chown libvirt-qemu:kvm /var/lib/libvirt/images/lab/${self.name} && sudo -n chmod 640 /var/lib/libvirt/images/lab/${self.name}"
  }
}

resource "libvirt_domain" "vm" {
  for_each = local.vms

  name   = each.key
  memory = each.value.memory
  vcpu   = each.value.vcpu

  cloudinit = libvirt_cloudinit_disk.commoninit[each.key].id

  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    autoport    = true
    listen_type = "none"
  }
}
