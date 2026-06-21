output "vm_names" {
  value = keys(var.vms)
}

output "vm_uuids" {
  value = {
    for k, d in libvirt_domain.vm : k => d.uuid
  }
}
