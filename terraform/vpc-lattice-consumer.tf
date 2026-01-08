# ------------------------------------------------------------------------------
# PROVIDER CONFIGURATION
# ------------------------------------------------------------------------------
# Required to READ the secret from the Central Account.
provider "aws" {
  alias  = "central_network_reader"
  region = var.region
  assume_role {
    # This Role must exist in the Central Account and trust this Consumer Account
    role_arn = var.vpc_lattice_consumer ? "arn:aws:iam::${var.central_account_id}:role/CentralNetworkSecretsReader" : null
  }
}

# ------------------------------------------------------------------------------
# 1. DISCOVERY (Read Secret from Central Account)
# ------------------------------------------------------------------------------
data "aws_secretsmanager_secret" "network_info_secret" {
  count    = var.vpc_lattice_consumer ? 1 : 0
  provider = aws.central_network_reader
  name     = "service_network_info"
}

data "aws_secretsmanager_secret_version" "network_info" {
  count     = var.vpc_lattice_consumer ? 1 : 0
  provider  = aws.central_network_reader
  secret_id = data.aws_secretsmanager_secret.network_info_secret[0].id
}

locals {
  # Safely decode the secret only if it was fetched
  service_network = var.vpc_lattice_consumer ? jsondecode(data.aws_secretsmanager_secret_version.network_info[0].secret_string) : { id = "" }
}

# ------------------------------------------------------------------------------
# 2. VPC ASSOCIATION
# ------------------------------------------------------------------------------
module "vpc_lattice_consumer_association" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "1.1.0"

  count = var.vpc_lattice_consumer ? 1 : 0

  service_network = {
    identifier = local.service_network.id
  }

  vpc_associations = {
    vpc1 = {
      vpc_id             = var.vpc_id
      security_group_ids = [aws_security_group.lattice_client_sg[0].id]
    }
  }
}

# ------------------------------------------------------------------------------
# 3. CLIENT SECURITY GROUP
# ------------------------------------------------------------------------------
resource "aws_security_group" "lattice_client_sg" {
  count = var.vpc_lattice_consumer ? 1 : 0

  name        = "lattice-client-sg"
  description = "Allow HTTPS to VPC Lattice Service Network"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "Allow Lattice Link-Local Traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # AWS Lattice uses this specific link-local range
    cidr_blocks = ["169.254.171.0/24"]
  }
}

# Helper data source to get VPC CIDR
data "aws_vpc" "selected" {
  id = var.vpc_id
}

#######################################
# Test EC2
#######################################

module "app_ec2_instance_webserver" {
  source      = "git::https://github.com/organization/cloud-aws-terraform-ec2.git?ref=v3.1.2"
  count       = var.vpc_lattice_consumer ? 1 : 0
  project     = var.project
  environment = var.environment

  # Core EC2 configuration
  instance_name      = "test-ec2-webserver"
  instance_count     = 1
  instance_type      = "t3.micro"
  ec2_os             = "Linux"
  subnet_id          = var.private_subnets[0]
  security_group_ids = [aws_security_group.app_ec2_sg[0].id]
  use_golden_ami     = false
  ami_id             = "ami-0b3e7dd7b2a99b08d"
  backup_enabled_tag = var.backup_retention_policy
}

resource "aws_security_group" "app_ec2_sg" {
  count = var.vpc_lattice_consumer ? 1 : 0

  name        = "app-ec2-sg"
  description = "Security group for application EC2 instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
