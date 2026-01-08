# ------------------------------------------------------------------------------
# 1. VPC LATTICE SERVICE NETWORK (The Backbone)
# ------------------------------------------------------------------------------
module "vpclattice_service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "1.1.0"

  service_network = {
    name      = var.service_network_name
    auth_type = "AWS_IAM"
    # Basic policy: Allow authenticated AWS principals. 
    # Real Zero Trust happens at the Service level (Provider) or detailed Auth Policies here.
    auth_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action    = "*"
        Effect    = "Allow"
        Principal = "*"
        Resource  = "*"
      }]
    })
  }
}

# ------------------------------------------------------------------------------
# 2. RAM SHARE (Layer 1 Sharing)
# ------------------------------------------------------------------------------
# Share the Service Network with the entire Organization (or specific accounts)
resource "aws_ram_resource_share" "network_share" {
  name                      = "lattice-service-network-share"
  allow_external_principals = true
}

resource "aws_ram_resource_association" "network_association" {
  resource_arn       = module.vpclattice_service_network.service_network.arn
  resource_share_arn = aws_ram_resource_share.network_share.arn
}

# Example: Share with entire Org (Preferred for simplifying management)
resource "aws_ram_principal_association" "org_association" {
  # You can pass the Org ARN or specific OU ARN here
  principal          = var.share_principal_arn
  resource_share_arn = aws_ram_resource_share.network_share.arn
}

# ------------------------------------------------------------------------------
# 3. CONSUMER INFO SECRET (For Discovery)
# ------------------------------------------------------------------------------
# The Central account publishes the Network ID here so Consumers can "find" it.

resource "aws_secretsmanager_secret" "service_network_info" {
  name        = "service_network_info"
  description = "Public info for Consumers to discover the Lattice Service Network"
  kms_key_id  = aws_kms_key.secrets_key.arn
}

resource "aws_secretsmanager_secret_version" "service_network_info_val" {
  secret_id = aws_secretsmanager_secret.service_network_info.id
  secret_string = jsonencode({
    id  = module.vpclattice_service_network.service_network.id
    arn = module.vpclattice_service_network.service_network.arn
  })
}

# Policy: Allow CONSUMERS to READ this secret
resource "aws_secretsmanager_secret_policy" "consumer_read_policy" {
  secret_arn = aws_secretsmanager_secret.service_network_info.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowConsumersToRead"
      Effect    = "Allow"
      Principal = { AWS = var.consumer_account_principals } # List of Consumer Account Root ARNs
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "*"
    }]
  })
}

# ------------------------------------------------------------------------------
# 4. PROVIDER REGISTRY SECRET (The "Drop Box")
# ------------------------------------------------------------------------------
# Providers write their Service IDs here. Automation (Lambda) would watch this.

resource "aws_secretsmanager_secret" "provider_registry" {
  name        = "vpclattice_services"
  description = "Registry where Providers publish their Service IDs"
  kms_key_id  = aws_kms_key.secrets_key.arn
}

# Policy: Allow PROVIDERS to WRITE to this secret
resource "aws_secretsmanager_secret_policy" "provider_write_policy" {
  secret_arn = aws_secretsmanager_secret.provider_registry.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowProvidersToWrite"
      Effect    = "Allow"
      Principal = { AWS = var.provider_account_principals } # List of Provider Account Root ARNs
      Action    = ["secretsmanager:PutSecretValue", "secretsmanager:GetSecretValue"]
      Resource  = "*"
    }]
  })
}

# ------------------------------------------------------------------------------
# 5. KMS KEY (Encryption)
# ------------------------------------------------------------------------------
resource "aws_kms_key" "secrets_key" {
  description             = "KMS Key for Lattice Secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "Allow Consumer and Provider Access"
        Effect    = "Allow"
        Principal = { AWS = concat(var.consumer_account_principals, var.provider_account_principals) }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
