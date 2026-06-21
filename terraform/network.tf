resource "libvirt_network" "lab" {
  name = "lab-net"
  bridge = {
    name  = "virbr1"
    stp   = "on"
    delay = "0"
  }
  forward = {
    mode = "nat"
    nat = {
      ports = [{ start = 1024, end = 65535 }]
    }
  }
  ips = [{
    address = "192.168.123.1"
    netmask = "255.255.255.0"
    dhcp = {
      hosts = [
        { mac = "52:54:00:aa:aa:01", name = "jumpbox", ip = "192.168.123.10" },
        { mac = "52:54:00:aa:aa:02", name = "k3s-master", ip = "192.168.123.11" },
        { mac = "52:54:00:aa:aa:03", name = "k3s-worker1", ip = "192.168.123.12" },
      ]
      ranges = [{ start = "192.168.123.100", end = "192.168.123.200" }]
    }
  }]
  domain = {
    local_only = "yes"
    name       = "lab.internal"
  }
}
