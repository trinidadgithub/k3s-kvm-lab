# Platform Engineering Review — Local Virtualization Lab

> Review date: 2026-06-18
> Host: ThinkPad X1 Carbon 6th Gen (i7-8650U, 8 threads, 16 GB RAM)
> OS: Ubuntu 24.04 LTS
> Stack: KVM + libvirt + qemu + Terraform (dmacvicar/libvirt) + cloud-init

---

## Table of Contents

1. [Security](#1-security)
2. [Terraform Structure](#2-terraform-structure)
3. [libvirt Architecture](#3-libvirt-architecture)
4. [Storage Pool Management](#4-storage-pool-management)
5. [cloud-init Design](#5-cloud-init-design)
6. [Packer Image Pipeline](#6-packer-image-pipeline)
7. [Ansible Integration](#7-ansible-integration)
8. [Kubernetes Lab Design](#8-kubernetes-lab-design)
9. [Disaster Recovery and Rebuild Procedures](#9-disaster-recovery-and-rebuild-procedures)
10. [Makefile and Developer Experience](#10-makefile-and-developer-experience)
11. [Hidden Risks and Anti-Patterns](#11-hidden-risks-and-anti-patterns)

---

## 1. Security

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 1.1 | **Static cloud-init `user-data.yaml` contains a hardcoded password hash** (`lock_passwd: false`, `passwd: $6$rounds=4096$changemehash`). Not used by Terraform (which uses `user-data.tftpl`) but still present in the repo. Risk of accidental use or commit. | **Immediate** | `cloud-init/user-data.yaml` |
| 1.2 | **SSH key path mismatch in Terraform.** `main.tf` hardcodes `pathexpand("~/.ssh/id_rsa.pub")` but primary key is `id_ed25519`. Will fail on `terraform apply` if `id_rsa.pub` doesn't exist. | **Immediate** | `terraform/main.tf:24` |
| 1.3 | **Packer config hardcodes password `"ubuntu"`** with no post-provision hardening. Exposes well-known credential if the pipeline is ever used. | **Immediate** | `packer/ubuntu-24.04.pkr.hcl:17-18` |
| 1.4 | **`disable_root: true` not enforced consistently.** Template sets it, static `user-data.yaml` doesn't. Inconsistent between manual and Terraform-managed VMs. | **Near-term** | `cloud-init/user-data.yaml` |
| 1.5 | **AppArmor rule is overly broad.** `** rwk` allows write to any file under the pool. Narrow to `**/*.{qcow2,iso} rwk,` to reduce blast radius. | **Near-term** | `/etc/apparmor.d/local/abstractions/libvirt-qemu` |
| 1.6 | **No secrets management for Ansible.** `ansible_ssh_private_key_file` path is hardcoded. No `ansible-vault` or external secrets. | **Future** | `ansible/inventories/terraform.py` |

### Rationale

- **1.1**: Password-based auth with a known hash is a credential exposure risk. The file is dead code — remove it or replace with a vault-encrypted template.
- **1.5**: The current `**` wildcard allows QEMU to write anything under the pool dir. Narrowing to `*.qcow2` and `*.iso` limits the kernel attack surface exposed through AppArmor while still allowing the VM runtime access it needs.

---

## 2. Terraform Structure

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 2.1 | **Unused variables.** `vm_memory_mb`, `vm_vcpu`, `pool_path` defined in `variables.tf` and `terraform.tfvars` but never referenced in `main.tf`. VM sizing is hardcoded in `locals`. Changing `.tfvars` has no effect — misleading. | **Immediate** | `terraform/variables.tf`, `terraform/terraform.tfvars` |
| 2.2 | **`local-exec` provisioners for chown/chmod** on volumes and cloudinit ISOs. Only run at resource creation — permission drift will not be detected or fixed by subsequent `terraform apply`. Not idempotent. | **Immediate** | `terraform/main.tf:35-37, 56-58` |
| 2.3 | **No `libvirt_pool` resource.** Pool created manually outside Terraform. Rebuilding from scratch requires manual steps not codified in IaC. | **Near-term** | — |
| 2.4 | **No `libvirt_network` resource.** Static DHCP leases configured manually via `virsh net-update`. Terraform cannot manage or recreate these. | **Near-term** | — |
| 2.5 | **No remote state backend.** Local state only. Loss of workspace = loss of Terraform state. Acceptable for laptop lab, but should be documented. | **Near-term** | — |
| 2.6 | **Version constraint too restrictive.** `~> 0.8.0` in `versions.tf` but `v0.9.7` installed. Mismatch forces downgrade on `terraform init`. | **Immediate** | `terraform/versions.tf:7` |
| 2.7 | **`source = var.base_image` creates full copies**, not backing-chain qcow2s. Each VM consumes ~1.2 GB instead of ~200 MB. No golden image propagation. | **Near-term** | `terraform/main.tf:32` |
| 2.8 | **No `pool` configuration on the provider.** Pool name hardcoded in each resource. If pool changes, every resource must be updated manually. | **Near-term** | `terraform/main.tf:31,45` |

### Rationale

- **2.2**: `local-exec` provisioners are a Terraform anti-pattern for side effects. The correct approach is either (a) configure permissions via the `libvirt_pool` resource's `target.permissions` block, or (b) use a dedicated configuration management tool (Ansible) after `terraform apply`.

---

## 3. libvirt Architecture

| # | Finding | Classification | Details |
|---|---------|---------------|---------|
| 3.1 | **Single NAT network, no isolation.** All VMs on `192.168.122.0/24`. No separation between control-plane and workload traffic. | **Near-term** | `virsh net-dumpxml default` |
| 3.2 | **Pool config is tribal knowledge.** Pool XML (target path, mode `0770`, group `64055`) not committed or documented. | **Near-term** | Rebuild requires `virsh pool-define-as` |
| 3.3 | **All 3 VMs are shut off.** If intentional, document start sequence. If not, they should be running or have `autostart` managed by Terraform. | **Near-term** | Current state from `virsh list --all` |
| 3.4 | **Split daemon vs monolith risk.** Ubuntu 24.04 defaults to `virtqemud`/`virtproxyd` split daemons. AppArmor references `virtqemud` as peer. Provider URI `qemu:///system` auto-resolves, but mixing models causes confusion. | **Near-term** | AppArmor profile, provider URI |

---

## 4. Storage Pool Management

| # | Finding | Classification | Details |
|---|---------|---------------|---------|
| 4.1 | **Inconsistent directory permissions.** Pool root `2770`, parent `/var/lib/libvirt/images` is `755` (default). Layering is fragile and undocumented. | **Near-term** | `ls -la /var/lib/libvirt/images/lab/` |
| 4.2 | **Orphaned base image copy** at `~/workspace/lab/images/ubuntu-24.04-server-cloudimg-amd64.img` (~615 MB). Not used by Terraform or `create-vm` script. | **Immediate** | `~/workspace/lab/images/` |
| 4.3 | **No discard/trim strategy.** qcow2 defaults to `lazy_refcounts=off`. Enabling `discard` on guests + `lazy_refcounts=on` reduces NVMe write amplification. | **Future** | `qemu-img create` defaults |
| 4.4 | **No snapshot/backup workflow.** `snapshots/` directory exists but is empty. No mechanism to protect against `terraform destroy` wiping all VMs. | **Near-term** | `~/workspace/lab/snapshots/` |

---

## 5. cloud-init Design

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 5.1 | **Dual cloud-init files create confusion.** Both `user-data.yaml` (static, password-based) and `user-data.tftpl` (Terraform template, SSH-only) exist. Only `.tftpl` is used. The `.yaml` files are dead code with worse security posture. | **Immediate** | `cloud-init/user-data.yaml`, `cloud-init/meta-data.yaml` |
| 5.2 | **No `network-config` template.** VMs rely on DHCP with static leases. No static IP fallback if the DHCP server is unavailable during network rebuilds. | **Future** | — |
| 5.3 | **`package_update: true` runs on every first boot.** Adds 30-60s to VM creation. Should be baked into a Packer golden image instead. | **Near-term** | `cloud-init/user-data.tftpl:17` |
| 5.4 | **No `write_files` or `bootcmd` section.** No mechanism to inject config files at first boot (sysctl, MOTD, apt sources). Increases Ansible's day-0 responsibilities. | **Near-term** | `cloud-init/user-data.tftpl` |

---

## 6. Packer Image Pipeline

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 6.1 | **Packer config is non-functional.** Live-server ISO install with no `autoinstall` user-data file — the `http/` directory is empty. Build will fail. | **Immediate** | `packer/ubuntu-24.04.pkr.hcl`, `packer/http/` |
| 6.2 | **No golden image strategy.** Base image is a raw cloud-image download. No hardened gold image with pre-installed packages. Every `terraform apply` repeats the same package install via cloud-init. | **Near-term** | — |
| 6.3 | **`iso_checksum` uses `file:` URL pointing to SHA256SUMS.** Fragile — mirror updates to checksum file will break validation. Pin to a specific SHA256. | **Near-term** | `packer/ubuntu-24.04.pkr.hcl:12` |
| 6.4 | **No versioned image tags.** Output filename `ubuntu-24.04-base` has no version. Cannot safely transition VMs to a new image version. | **Future** | `packer/ubuntu-24.04.pkr.hcl:19` |

### Recommended Pipeline

```
Packer download of Ubuntu cloud image
  → configure (inject SSH key, install packages, apply sysctl, security hardening)
  → output as qcow2 (version-tagged, e.g., ubuntu-24.04-hardened-v1.0.0.qcow2)
  → copy to /var/lib/libvirt/images/lab/base/
  → Terraform creates VMs using backing-chain from this gold image
```

---

## 7. Ansible Integration

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 7.1 | **Ansible inventory returns an empty host list.** The `terraform.py` script is a static stub — `hosts: []`. `make ansible-ping` and `make ansible-site` both fail. | **Immediate** | `ansible/inventories/terraform.py` |
| 7.2 | **No host groups defined.** Playbooks reference `jumpbox`, `k3s_server`, `k3s_agents` but these groups don't exist in any inventory. | **Immediate** | All playbooks |
| 7.3 | **Playbooks are empty shells.** `jumpbox.yaml`, `k3s-server.yaml`, `k3s-agent.yaml` all have `tasks: []`. No actual configuration is performed. | **Immediate** | `ansible/playbooks/*.yaml` |
| 7.4 | **No `group_vars` or `host_vars`.** Directory exists but is empty. No place for environment-specific config (k3s version, cluster token, API args). | **Near-term** | `ansible/group_vars/` |
| 7.5 | **No Terraform/Ansible integration.** No dynamic inventory reading `terraform.tfstate` to populate host IPs and groups. | **Near-term** | `ansible/inventories/terraform.py` |

### Recommended Approach

Replace `terraform.py` with a proper dynamic inventory that reads `terraform.tfstate` and maps VMs to Ansible groups:
- `jumpbox` → group `jumpbox`
- `k3s-master` → group `k3s_server`
- `k3s-worker1` → group `k3s_agents`

---

## 8. Kubernetes Lab Design

| # | Finding | Classification | Details |
|---|---------|---------------|---------|
| 8.1 | **Worker-to-master ratio is 1:1.** No functional HA or scheduling diversity. Room for at least one more worker (2 GB) on 16 GB host. | **Near-term** | Current: 3 VMs, 7 GB allocated |
| 8.2 | **No dedicated k3s Ansible role.** Server and agent playbooks are empty. No role structure for k3s binary download, systemd unit, or token config. | **Near-term** | `ansible/playbooks/k3s-*.yaml` |
| 8.3 | **No pod/service network isolation.** All VMs on same NAT network — can't meaningfully test CNI policies. | **Future** | Single `virbr0` bridge |
| 8.4 | **No k3s token management.** Cluster registration token must be generated and distributed securely between master and workers. No mechanism exists. | **Near-term** | — |
| 8.5 | **k3s-master has 3 GB RAM.** On a 16 GB host this leaves ~11 GB for host + other VMs. Workable, but could reduce master to 2 GB (k3s is lightweight) for more worker memory. | **Near-term** | `terraform/main.tf:14` |

---

## 9. Disaster Recovery and Rebuild Procedures

| # | Finding | Classification | Details |
|---|---------|---------------|---------|
| 9.1 | **No documented rebuild procedure.** `docs/lab-plan.md` is a trivial description with no runbook for recovery from: host reinstall, SSD failure, state corruption, accidental `terraform destroy`. | **Immediate** | `docs/lab-plan.md` |
| 9.2 | **Terraform state is local-only with no backup.** If `terraform.tfstate` is lost, VMs become orphaned. `terraform import` required for each. | **Near-term** | `terraform/terraform.tfstate` (gitignored) |
| 9.3 | **No `terraform destroy` guard.** No state locking, no `prevent_destroy` lifecycle, no `-target` workflow documented. Single `make tf-destroy` obliterates everything. | **Near-term** | `Makefile:37` |
| 9.4 | **Static DHCP leases are manual recovery items.** If the libvirt network is recreated, leases must be re-added via `virsh net-update`. Not covered by IaC. | **Near-term** | `virsh net-dumpxml default` |
| 9.5 | **No snapshot/restore capability.** `snapshots/` directory exists but has no tooling. | **Future** | `~/workspace/lab/snapshots/` |

### Required Rebuild Procedure (to be documented)

1. Install packages: `qemu-kvm`, `libvirt-daemon-system`, `virtinst`, `terraform`, `packer`, `ansible`
2. Add user to groups: `usermod -aG libvirt,kvm,libvirt-qemu ubuntu`
3. Create pool: `virsh pool-define-as lab dir --target /var/lib/libvirt/images/lab && virsh pool-build lab && virsh pool-start lab && virsh pool-autostart lab`
4. Copy base image to pool: `cp ~/workspace/lab/images/ubuntu-24.04-*.img /var/lib/libvirt/images/lab/base/`
5. Set pool permissions: `chown -R root:libvirt-qemu /var/lib/libvirt/images/lab && chmod 2770 /var/lib/libvirt/images/lab /var/lib/libvirt/images/lab/base && find /var/lib/libvirt/images/lab -type f -exec chmod 640 {} \;`
6. Verify AppArmor override: `/etc/apparmor.d/local/abstractions/libvirt-qemu` contains `/var/lib/libvirt/images/lab/** rwk,`
7. Define network static leases via `virsh net-update default add ip-dhcp-host ...`
8. `cd ~/workspace/lab && make tf-init && make tf-apply`
9. `make ansible-site`

---

## 10. Makefile and Developer Experience

| # | Finding | Classification | File |
|---|---------|---------------|------|
| 10.1 | **No `auto-approve` variant of `tf-apply`/`tf-destroy`.** Interactive only — can't be used in scripts or chained workflows. Add `tf-apply-auto` and `tf-destroy-auto` targets. | **Near-term** | `Makefile:33,37` |
| 10.2 | **No `make up` or `make all` end-to-end target.** The Packer→Terraform→Ansible workflow is documented but not automated. | **Near-term** | `Makefile` |
| 10.3 | **No pre-flight checks.** Targets don't validate prerequisites (pool exists, base image exists, SSH key exists, cloud-init templates present). | **Near-term** | `Makefile` |
| 10.4 | **No formatting enforcement.** `make tf-fmt` and `make packer-fmt` exist but are manual. No pre-commit hook or CI. | **Future** | `Makefile:11,23` |
| 10.5 | **`destroy-vm` script lacks safety guards.** No argument validation, no confirmation prompt, no `set -euo pipefail`. Empty argument runs partial-name match risk. | **Immediate** | `bin/destroy-vm` |

---

## 11. Hidden Risks and Anti-Patterns

### A. Terraform `local-exec` permission hacks will break silently

The `chown`/`chmod` provisioners in `main.tf:35-37` and `56-58` run **only at resource creation**. If permissions drift (libvirt reinstall, pool recreate, manual chmod), `terraform apply` will **not detect or fix** it because the resource attributes haven't changed. The provisioner is a one-shot side effect, not a desired-state declaration.

### B. Static cloud-init files are a credential exposure risk

`cloud-init/user-data.yaml` contains a hardcoded password hash. If this repo is ever pushed to a remote (even private), the credential pattern is exposed. The file should be removed or vault-encrypted.

### C. No filesystem-level or VM-level backup

No protection against:
- Accidental `terraform destroy` (wipes all VMs and disks)
- SSD failure
- Accidental `rm -rf /var/lib/libvirt/images/lab`
- Corrupt qcow2 file

A daily `rsync` of the pool or a `virsh snapshot-create-as` wrapper would provide basic protection.

### D. CPU oversubscription

8 host threads. Current allocation: 6 vCPUs (75%). Adding `k3s-worker2` (2) + `vault-dev` (2) = 10 vCPUs on 8 threads (125%). Will work but CPU steal time becomes noticeable. Document the limit.

### E. Memory ceiling

Current allocation: 2 + 3 + 2 = 7 GB + host overhead (~4 GB) = ~11 GB of 16 GB. Adding 2 more VMs at 2 GB each = 15 GB — dangerously close to the ceiling with zero headroom for host processes or OOM. Hard limit for this hardware.

### F. `set -euo pipefail` inconsistency

`destroy-vm` and `list-vms` lack `set -euo pipefail` while all other bin scripts have it. `destroy-vm` also uses unquoted `$1` — shell injection/word-splitting risk.

### G. Full qcow2 copies instead of backing chains

`source = var.base_image` on `libvirt_volume` creates a full copy of the base for each VM. Each VM consumes ~1.2 GB instead of ~200 MB. Updating the base image doesn't propagate to existing VMs. Use `base_volume_id` for backing chains instead.

---

## Recommendation Priority Summary

### Immediate (fix now)
| # | Issue |
|---|-------|
| 1.1 | Static cloud-init with hardcoded password hash |
| 1.2 | SSH key path mismatch (id_rsa vs id_ed25519) |
| 1.3 | Packer hardcodes well-known password |
| 2.1 | Unused variables in variables.tf / terraform.tfvars |
| 2.2 | `local-exec` permission hacks (non-idempotent) |
| 2.6 | Terraform version constraint mismatch |
| 4.2 | Orphaned base image copy |
| 5.1 | Dual cloud-init files, dead code |
| 6.1 | Packer config is non-functional |
| 7.1 | Ansible inventory returns empty host list |
| 7.2 | No host groups defined in inventory |
| 7.3 | Playbooks are empty shells (`tasks: []`) |
| 9.1 | No documented rebuild procedure |
| 10.5 | `destroy-vm` script lacks safety guards |

### Near-term (next session)
| # | Issue |
|---|-------|
| 1.4 | `disable_root: true` not enforced consistently |
| 1.5 | AppArmor rule overly broad |
| 2.3 | No `libvirt_pool` resource in Terraform |
| 2.4 | No `libvirt_network` resource in Terraform |
| 2.5 | No remote state backend (document at minimum) |
| 2.7 | Full qcow2 copies instead of backing chains |
| 3.1 | Single NAT network, no isolation |
| 3.2 | Pool config is tribal knowledge |
| 3.3 | VMs are shut off |
| 3.4 | Split daemon vs monolith risk |
| 4.1 | Inconsistent directory permissions |
| 4.4 | No snapshot/backup workflow |
| 5.3 | `package_update: true` slows first boot |
| 5.4 | No `write_files` / `bootcmd` in cloud-init |
| 6.2 | No golden image strategy |
| 6.3 | `iso_checksum` uses fragile `file:` URL |
| 7.4 | No `group_vars` or `host_vars` |
| 7.5 | No Terraform/Ansible integration |
| 8.1 | Worker-to-master ratio 1:1 |
| 8.2 | No dedicated k3s Ansible role |
| 8.4 | No k3s token management |
| 8.5 | k3s-master RAM allocation could be optimized |
| 9.2 | Terraform state is local-only, no backup |
| 9.3 | No `terraform destroy` guard |
| 9.4 | Static DHCP leases are manual recovery items |
| 10.1 | No `auto-approve` Makefile targets |
| 10.2 | No `make up` end-to-end target |
| 10.3 | No pre-flight checks in Makefile |

### Future (nice-to-have)
| # | Issue |
|---|-------|
| 1.6 | No secrets management for Ansible |
| 4.3 | No discard/trim strategy for NVMe |
| 5.2 | No `network-config` template |
| 6.4 | No versioned image tags |
| 8.3 | No pod/service network isolation |
| 9.5 | No snapshot/restore capability |
| 10.4 | No formatting enforcement in CI |
