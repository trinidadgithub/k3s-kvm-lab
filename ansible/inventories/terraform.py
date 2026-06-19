#!/usr/bin/env python3
import json

inventory = {
    "all": {
        "hosts": [],
        "vars": {
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": "~/.ssh/id_ed25519",
        },
    },
    "_meta": {"hostvars": {}},
}

print(json.dumps(inventory, indent=2))
