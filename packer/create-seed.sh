#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${DIR}/seed.iso"
PUBKEY="${HOME}/.ssh/id_ed25519.pub"

if [[ ! -f "$PUBKEY" ]]; then
  PUBKEY="${HOME}/.ssh/id_rsa.pub"
fi

if [[ ! -f "$PUBKEY" ]]; then
  echo "No SSH public key found. Create one with: ssh-keygen -t ed25519"
  exit 1
fi

KEY=$(cat "$PUBKEY")

USER_DATA=$(mktemp)
META_DATA=$(mktemp)

cat > "$USER_DATA" <<EOF
#cloud-config
hostname: packer-build
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${KEY}
ssh_pwauth: false
disable_root: true
EOF

cat > "$META_DATA" <<EOF
instance-id: iid-packer
local-hostname: packer-build
EOF

cloud-localds "$OUT" "$USER_DATA" "$META_DATA"
rm -f "$USER_DATA" "$META_DATA"

echo "Seed ISO created: $OUT"
