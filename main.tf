terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.46.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.env
      department  = "TPMM"
      application = "HashiCafe website"
    }
  }
}

locals {
  timestamp = timestamp()
}

resource "random_integer" "product" {
  min = 0
  max = length(var.hashi_products) - 1
  keepers = {
    "timestamp" = local.timestamp
  }
}

data "hcp_packer_iteration" "ubuntu-webserver" {
  bucket_name = var.packer_bucket
  channel     = var.packer_channel
}

data "hcp_packer_image" "ubuntu-webserver" {
  bucket_name    = var.packer_bucket
  cloud_provider = "aws"
  iteration_id   = data.hcp_packer_iteration.ubuntu-webserver.ulid
  region         = var.region
}

resource "aws_vpc" "hashicafe" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-${var.region}"
  }

  lifecycle {
    postcondition {
      condition     = self.enable_dns_hostnames == true
      error_message = "VPC must have DNS hostnames enabled."
    }
  }
}

resource "aws_subnet" "hashicafe" {
  vpc_id     = aws_vpc.hashicafe.id
  cidr_block = var.subnet_prefix

  tags = {
    Name = "${var.prefix}-subnet"
  }
}

resource "aws_security_group" "hashicafe" {
  name = "${var.prefix}-security-group"

  vpc_id = aws_vpc.hashicafe.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.prefix}-security-group"
  }
}

resource "aws_internet_gateway" "hashicafe" {
  vpc_id = aws_vpc.hashicafe.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "hashicafe" {
  vpc_id = aws_vpc.hashicafe.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hashicafe.id
  }
}

resource "aws_route_table_association" "hashicafe" {
  subnet_id      = aws_subnet.hashicafe.id
  route_table_id = aws_route_table.hashicafe.id
}

resource "aws_instance" "hashicafe" {
  ami                         = data.hcp_packer_image.ubuntu-webserver.cloud_image_id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.hashicafe.id
  vpc_security_group_ids      = [aws_security_group.hashicafe.id]
  key_name                    = aws_key_pair.hashicafe.key_name

  user_data = <<-EOF
    #!/bin/bash

    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
    apt-get -qy update
    apt-get -qy -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install nginx
    systemctl enable nginx --now
    ufw allow http
    mkdir -p /var/www/html/img
    chown -R ubuntu:ubuntu /var/www/html
  EOF

  tags = {
    Name = "${var.prefix}-hashicafe-instance"
  }

  lifecycle {
    precondition {
      condition     = data.hcp_packer_image.ubuntu-webserver.region == var.region
      error_message = "The selected image must be in the same region as the deployed resources."
    }

    postcondition {
      condition     = self.ami == data.hcp_packer_image.ubuntu-webserver.cloud_image_id
      error_message = "A newer source AMI is available in the HCP Packer channel, please re-deploy."
    }

    postcondition {
      condition     = self.public_dns != ""
      error_message = "EC2 instance must be in a VPC that has public DNS hostnames enabled."
    }
  }
}

resource "aws_eip" "hashicafe" {}

resource "aws_eip_association" "hashicafe" {
  instance_id   = aws_instance.hashicafe.id
  allocation_id = aws_eip.hashicafe.id
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

resource "null_resource" "configure-web-app" {
  depends_on = [aws_eip_association.hashicafe]

  triggers = {
    build_number = local.timestamp
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.hashicafe.private_key_pem
    host        = aws_eip.hashicafe.public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    # We need to wait for cloud-init to finish so permissions are correct.
    inline = ["/usr/bin/cloud-init status --wait"]
  }

  provisioner "file" {
    content = templatefile("files/index.html", {
      product_name  = var.hashi_products[random_integer.product.result].name
      product_color = var.hashi_products[random_integer.product.result].color
      product_image = var.hashi_products[random_integer.product.result].image_file
    })
    destination = "/var/www/html/index.html"
  }

  provisioner "file" {
    source      = "files/img/"
    destination = "/var/www/html/img"
  }
}

resource "tls_private_key" "hashicafe" {
  algorithm = "RSA"
}

resource "aws_key_pair" "hashicafe" {
  key_name   = "${var.prefix}-hashicafe-sshkey"
  public_key = tls_private_key.hashicafe.public_key_openssh
}
