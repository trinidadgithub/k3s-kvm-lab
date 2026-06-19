# Implementation Plan — Lab Remediation

> Each phase produces a clean commit. Test cases validate before moving on.

---

## Phase 0 — Repository Hygiene (no Terraform changes)

*No infrastructure changes — safe to apply immediately without touching running VMs.*

| Step | Finding | Action | Test | Status |
|------|---------|--------|------|--------|
| 0.1 | 1.1 / 5.1 | Remove `cloud-init/user-data.yaml` and `cloud-init/meta-data.yaml` (static files with hardcoded password; only `.tftpl` templates are used by Terraform) | `git status` shows files deleted; `make tf-plan` unchanged | ✓ |
| 0.2 | 1.2 | Fix SSH key path in `main.tf` — use `id_ed25519` with `id_rsa` fallback via `fileexists()` | `terraform validate` passes | ✓ |
| 0.3 | 2.6 | *Deferred to Phase 1.* Provider upgrade (0.8.3 → 0.9.x) requires complete API migration of `main.tf`. Not a clean-room change. | — | ❌ → Phase 1 |
| 0.4 | 2.1 | Remove unused variables `vm_memory_mb`, `vm_vcpu`, `pool_path` from `variables.tf` and `terraform.tfvars` | `terraform validate` passes with no warnings | ✓ |
| 0.5 | 1.3 / 6.1a | Fix Packer config — replace live-server ISO install with cloud-image download + SSH-key auth + cloud-init seed ISO via `create-seed.sh`. Removed hardcoded password. | `make packer-seed` creates seed.iso | ✓ |
| 0.6 | 10.5 | Fix `destroy-vm`: add `set -euo pipefail`, argument validation, usage message. Fix `list-vms` for consistency. | `shellcheck bin/destroy-vm` passes | ✓ |
| 0.7 | 4.2 | Remove orphaned base image at `~/workspace/lab/images/ubuntu-24.04-server-cloudimg-amd64.img` (601 MB). Runtime copy at `/var/lib/libvirt/images/lab/base/` is unchanged. | `ls ~/workspace/lab/images/` shows only README | ✓ |

---

## Phase 1 — Terraform Core Fixes

*Changes to main.tf — requires `terraform apply` to update VMs.*

| Step | Finding | Action | Test |
|------|---------|--------|------|
| 1.1 | 2.2 / 2.3 | Add `libvirt_pool` resource managing the `lab` pool with correct `target.permissions`. **Remove** `local-exec` provisioners from `libvirt_volume` and `libvirt_cloudinit_disk` — pool permissions handle access | `virsh pool-dumpxml lab` matches Terraform; `terraform apply` makes no permission changes on subsequent runs |
| 1.2 | 2.4 | Add `libvirt_network` resource defining `lab-net` with static DHCP leases for all VMs. Retain `default` network for initial boot, migrate to `lab-net` | `virsh net-dumpxml lab-net` matches Terraform; `make tf-plan` clean |
| 1.3 | 2.7 | Switch `libvirt_volume` from `source` (full copy) to `base_volume_id` (backing chain). Requires importing base image as a `libvirt_volume` first | `qemu-img info` on VM disk shows `backing file` reference; disk usage drops from ~1.2 GB to ~200 MB per VM |
| 1.4 | 2.8 | Reference `libvirt_pool.lab.id` in all volume/cloudinit resources instead of hardcoded pool name | `make tf-validate` passes; `terraform apply` idempotent |
| 1.5 | 1.4 | Add `disable_root: true` to the static `user-data.yaml` (if kept) — actually this is already handled by removing the static files in 0.1; validate the template has it | Verify `cloud-init/user-data.tftpl` contains `disable_root: true` |

**Post-phase validation:**
```bash
make tf-fmt && make tf-validate
make tf-plan    # should show zero changes after apply
virsh pool-dumpxml lab | grep -E '(mode|owner|group)'
```

---

## Phase 2 — Ansible Integration

*Depends on Phase 1 (Terraform must produce known IPs for inventory).*

| Step | Finding | Action | Test |
|------|---------|--------|------|
| 2.1 | 7.1 / 7.2 / 7.5 | Replace `ansible/inventories/terraform.py` with proper dynamic inventory that reads `terraform.tfstate`, maps VMs to groups (`jumpbox`, `k3s_server`, `k3s_agents`) | `ansible-inventory -i inventories/terraform.py --list` returns 3 hosts with correct groups |
| 2.2 | 7.4 | Create `ansible/group_vars/k3s_server.yml` and `ansible/group_vars/k3s_agents.yml` with skeleton vars (k3s_version, download URL) | `ansible-inventory --graph` shows group structure |
| 2.3 | 7.3 | Populate `playbooks/site.yaml` with baseline tasks (common packages, sshd config, sysctl, NTP). Populate `jumpbox.yaml` with tooling install (kubectl, helm). Populate `k3s-server.yaml` / `k3s-agent.yaml` with k3s install | `make ansible-ping` reaches all 3 VMs; `make ansible-site` completes |
| 2.4 | 8.4 | Add k3s token generation and distribution to Ansible roles | k3s cluster forms and `kubectl get nodes` shows all 3 |

**Post-phase validation:**
```bash
make ansible-ping
make ansible-site
ssh ubuntu@$(terraform output -json vm_ips | jq -r '.jumpbox') kubectl get nodes
```

---

## Phase 3 — Packer Golden Image Pipeline

| Step | Finding | Action | Test |
|------|---------|--------|------|
| 3.1 | 6.1 / 6.2 | Implement working Packer build: download cloud image, inject SSH key, install baseline packages, apply security hardening, output version-tagged qcow2 to pool base dir | `make packer-build` produces a .qcow2 in `/var/lib/libvirt/images/lab/base/` |
| 3.2 | 6.3 | Pin `iso_checksum` to a specific SHA256 hash instead of `file:` URL | `make packer-validate` passes |
| 3.3 | 6.4 | Introduce version-tagged output filename (e.g., `ubuntu-24.04-lab-v1.0.0.qcow2`) and update Terraform `base_volume_id` to reference it | `terraform plan` shows volume source change |
| 3.4 | 5.3 | Remove `package_update: true` and baseline packages from cloud-init template — they're now baked into the golden image | `terraform apply` produces VM that boots without network package download |

**Post-phase validation:**
```bash
make packer-build
ls -l /var/lib/libvirt/images/lab/base/
qemu-img info /var/lib/libvirt/images/lab/base/ubuntu-24.04-lab-v1.0.0.qcow2
```

---

## Phase 4 — Hardening and Operations

| Step | Finding | Action | Test |
|------|---------|--------|------|
| 4.1 | 1.5 | Narrow AppArmor rule from `** rwk` to `**/*.{qcow2,iso} rwk,` | `sudo aa-status` shows no denials; `virsh start <vm>` succeeds |
| 4.2 | 9.1 | Write full rebuild procedure to `docs/rebuild.md` covering: package install, pool creation, base image copy, AppArmor, network DHCP leases, terraform init/apply, ansible | Review document for completeness |
| 4.3 | 9.2 / 9.3 | Add `terraform state pull > /var/lib/libvirt/images/lab/terraform-state-backup.json` to Makefile. Document `prevent_destroy` lifecycle for production-critical volumes | `make tf-backup` creates a dated backup |
| 4.4 | 10.1 / 10.2 / 10.3 | Add `tf-apply-auto`, `tf-destroy-auto` Makefile targets. Add `make up` (packer → tf → ansible). Add pre-flight check target `make check` | `make check` fails gracefully if prerequisites missing |
| 4.5 | 3.3 | Set `autostart = true` on Terraform `libvirt_domain` resources, or document start-sequence in the rebuild doc | `virsh list --all` shows VMs with autostart flag |
| 4.6 | 3.1 / 8.3 | Create isolated `lab-net` bridge network for workload traffic, separate from management NAT | VMs can communicate across networks; CNI can be tested |
| 4.7 | 4.4 / 9.5 | Implement snapshot wrapper script `bin/vm-snapshot` using `virsh snapshot-create-as` | Snapshot created and restorable |

**Post-phase validation:**
```bash
make check
make tf-plan
make tf-backup
ls /var/lib/libvirt/images/lab/terraform-state-*.json
```

---

## Phase 5 — Future / Stretch

| Step | Finding | Action | Test |
|------|---------|--------|------|
| 5.1 | 8.1 | Add `k3s-worker2` VM (2 GB RAM, 2 vCPU) to Terraform locals for HA scheduling | `kubectl get nodes` shows 4 nodes |
| 5.2 | 1.6 | Introduce `ansible-vault` for secrets — encrypt k3s token, SSH key paths | `ansible-vault view` works |
| 5.3 | 4.3 | Enable `lazy_refcounts=on` and `discard=unmap` on libvirt volumes | `qemu-img check` shows lazy refcounts enabled |
| 5.4 | 10.4 | Add `.pre-commit-config.yaml` with `terraform fmt` and `shellcheck` hooks | `git commit` triggers pre-commit checks |
| 5.5 | 5.2 | Add `network-config` to cloud-init for static IP assignment | VM boots with static IP even without DHCP |
| 5.6 | 9.5 | Automate daily libvirt snapshots via systemd timer + `vm-snapshot` | `systemctl status lab-snapshot.timer` shows last run |

---

## Dependency Graph

```
Phase 0 (no infra deps)
  ├── 0.1 Remove static cloud-init
  ├── 0.2 Fix SSH key path
  ├── 0.3 Fix version constraint
  ├── 0.4 Remove unused vars
  ├── 0.5 Fix Packer config
  ├── 0.6 Fix destroy-vm script
  └── 0.7 Remove orphaned base image
        │
Phase 1 (Terraform changes → requires apply)
  ├── 1.1 Pool resource + remove local-exec
  ├── 1.2 Network resource + DHCP leases
  ├── 1.3 Backing chains
  └── 1.4 Pool reference cleanup
        │
Phase 2 (depends on Phase 1 — IPs known)
  ├── 2.1 Dynamic inventory
  ├── 2.2 Group vars
  ├── 2.3 Populate playbooks
  └── 2.4 K3s token/roles
        │
Phase 3 (independent of Phase 2)
  ├── 3.1 Working Packer build
  ├── 3.2 Pin checksum
  ├── 3.3 Version tags
  └── 3.4 Remove package_update from cloud-init
        │
Phase 4 (depends on Phase 1+2+3)
  ├── 4.1 AppArmor hardening
  ├── 4.2 Rebuild docs
  ├── 4.3 State backup + destroy guards
  ├── 4.4 Makefile improvements
  ├── 4.5 Autostart
  ├── 4.6 Network isolation
  └── 4.7 Snapshot workflow
        │
Phase 5 (stretch, no blockers)
  ├── 5.1 Add worker2
  ├── 5.2 Ansible vault
  ├── 5.3 Lazy refcounts
  ├── 5.4 Pre-commit hooks
  ├── 5.5 Static network config
  └── 5.6 Automated snapshots
```

---

## Commit Strategy

Each step above = one commit. Commit message format:

```
phase-N: short description

Details if needed. Closes finding #X.Y.
```

Phases 0 and 1 must complete before any `terraform apply`, since Phase 0 is purely cleanup and Phase 1 restructures how Terraform manages resources. Once we reach Phase 1, we'll run `terraform apply` once after all Phase 1 steps are done.

---

## How We'll Work

1. I'll propose the next step from the plan.
2. You confirm or adjust.
3. I implement, you review.
4. We run the test case.
5. We commit.
6. Repeat.

Does this ordering work for you? Any steps you'd like to reorder, skip, or add?
