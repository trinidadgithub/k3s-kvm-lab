locals {
  cloudinit_data = {
    for k, vm in local.vms : k => {
      user_data = templatefile("${path.module}/../cloud-init/user-data.tftpl", {
        hostname   = k
        public_key = local.ssh_public_key
      })
      meta_data = templatefile("${path.module}/../cloud-init/meta-data.tftpl", {
        hostname = k
      })
    }
  }
}

module "compute" {
  source = "./modules/compute"

  vms            = local.vms
  pool_name      = libvirt_pool.lab.name
  network_name   = libvirt_network.lab.name
  base_image     = var.base_image
  cloudinit_data = local.cloudinit_data
}
