# Terraform module aws-nocode-webserver

Provisions a simple nginx webserver with sample HashiCafe website in AWS EC2, using a base AMI registered in [HCP Packer](https://cloud.hashicorp.com/products/packer).

Enabled for Terraform Cloud [no-code provisioning](https://developer.hashicorp.com/terraform/cloud-docs/no-code-provisioning/module-design).

For no-code provisioning, AWS credentials must be supplied to the workspace via environment variables (e.g. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). Also requires HCP connection credentials (`HCP_CLIENT_ID` and `HCP_CLIENT_SECRET`).
