resource "libvirt_volume" "vm_disk" {
  for_each = var.vms

  name     = "${each.key}.qcow2"
  pool     = var.pool_name
  capacity = each.value.disk
  backing_store = {
    path   = var.base_image
    format = { type = "qcow2" }
  }
  target = {
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  for_each = var.vms

  name      = "${each.key}-cloudinit"
  user_data = var.cloudinit_data[each.key].user_data
  meta_data = var.cloudinit_data[each.key].meta_data
}

resource "libvirt_domain" "vm" {
  for_each = var.vms

  name        = each.key
  type        = "kvm"
  running     = true
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu

  lifecycle {
    ignore_changes = [devices]
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        source = {
          file = {
            file = libvirt_volume.vm_disk[each.key].path
          }
        }
        target = { dev = "vda", bus = "virtio" }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_cloudinit_disk.commoninit[each.key].path
          }
        }
        target = { dev = "sda", bus = "sata" }
      },
    ]
    interfaces = [
      {
        mac = {
          address = each.value.mac
        }
        source = {
          network = {
            network = var.network_name
          }
        }
        model = { type = "virtio" }
      },
    ]
    consoles = [
      {
        source = { pty = { path = "" } }
        target = { type = "serial", port = 0 }
      },
    ]
  }
}
