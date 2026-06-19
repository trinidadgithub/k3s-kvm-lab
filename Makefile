PACKER_DIR=packer
TF_DIR=terraform
ANSIBLE_DIR=ansible

.PHONY: packer-init packer-fmt packer-validate packer-build
.PHONY: tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy
.PHONY: ansible-ping ansible-site

packer-init:
	cd $(PACKER_DIR) && packer init .

packer-fmt:
	cd $(PACKER_DIR) && packer fmt .

packer-validate:
	cd $(PACKER_DIR) && packer validate .

packer-build:
	cd $(PACKER_DIR) && packer build .

tf-init:
	cd $(TF_DIR) && terraform init

tf-fmt:
	cd $(TF_DIR) && terraform fmt

tf-validate:
	cd $(TF_DIR) && terraform validate

tf-plan:
	cd $(TF_DIR) && terraform plan

tf-apply:
	cd $(TF_DIR) && terraform apply

tf-destroy:
	cd $(TF_DIR) && terraform destroy

ansible-ping:
	cd $(ANSIBLE_DIR) && ansible all -m ping -i inventories/terraform.py

ansible-site:
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventories/terraform.py playbooks/site.yaml
