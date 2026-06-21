resource "libvirt_pool" "lab" {
  name = "lab"
  type = "dir"
  target = {
    path = "/var/lib/libvirt/images/lab"
    permissions = {
      mode  = "0770"
      owner = "0"
      group = "64055"
    }
  }
}
