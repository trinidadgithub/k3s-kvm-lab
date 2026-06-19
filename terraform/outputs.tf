output "vm_ips" {
  value = {
    for name, domain in libvirt_domain.vm :
    name => try(domain.network_interface[0].addresses[0], null)
  }
}
