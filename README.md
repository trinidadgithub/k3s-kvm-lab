# Local Lab

Portable KVM/libvirt lab on Ubuntu host.

## Workflow

1. Packer builds qcow2 base images
2. Terraform provisions libvirt resources
3. Ansible configures guests

## Core commands

- `make packer-init`
- `make packer-build`
- `make tf-init`
- `make tf-plan`
- `make tf-apply`
- `make ansible-ping`
- `make ansible-site`

## Notes

- Hypervisor runtime images live under `/var/lib/libvirt/images/lab`
- Source code and automation live under `~/workspace/lab`
