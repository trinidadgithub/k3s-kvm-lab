output "vm_names" {
  value = module.compute.vm_names
}

output "vm_uuids" {
  value = module.compute.vm_uuids
}

output "network_name" {
  value = libvirt_network.lab.name
}

output "pool_name" {
  value = libvirt_pool.lab.name
}
