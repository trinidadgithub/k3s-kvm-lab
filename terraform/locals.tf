locals {
  vms = {
    jumpbox = {
      memory = 2048
      vcpu   = 2
      disk   = 20 * 1024 * 1024 * 1024
      mac    = "52:54:00:aa:aa:01"
    }
    k3s-master = {
      memory = 3072
      vcpu   = 2
      disk   = 25 * 1024 * 1024 * 1024
      mac    = "52:54:00:aa:aa:02"
    }
    k3s-worker1 = {
      memory = 2048
      vcpu   = 2
      disk   = 20 * 1024 * 1024 * 1024
      mac    = "52:54:00:aa:aa:03"
    }
  }

  ssh_public_key = trimspace(file(
    fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
    pathexpand("~/.ssh/id_ed25519.pub") :
    pathexpand("~/.ssh/id_rsa.pub")
  ))
}
