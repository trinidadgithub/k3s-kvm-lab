#!/usr/bin/env python3
import json
from pathlib import Path

ssh_key = Path("~/.ssh/id_ed25519").expanduser()
if not ssh_key.exists():
    ssh_key = Path("~/.ssh/id_rsa").expanduser()

inventory = {
    "all": {
        "vars": {
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": str(ssh_key),
            "ansible_ssh_common_args": "-o StrictHostKeyChecking=accept-new",
        },
        "children": ["jumpboxes", "k3s_server", "k3s_agents"],
    },
    "jumpboxes": {
        "hosts": ["jumpbox"],
    },
    "k3s_server": {
        "hosts": ["k3s-master"],
    },
    "k3s_agents": {
        "hosts": ["k3s-worker1"],
    },
    "_meta": {
        "hostvars": {
            "jumpbox": {"ansible_host": "192.168.123.10"},
            "k3s-master": {"ansible_host": "192.168.123.11"},
            "k3s-worker1": {"ansible_host": "192.168.123.12"},
        }
    },
}

print(json.dumps(inventory, indent=2))
