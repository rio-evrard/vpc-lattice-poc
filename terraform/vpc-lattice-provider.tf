# ------------------------------------------------------------------------------
# PROVIDER CONFIGURATION
# ------------------------------------------------------------------------------
# The Aliased Provider manages resources in the CENTRAL NETWORK account.
# We need this to register our service in the Central Secrets Manager registry.
provider "aws" {
  alias  = "central_network_writer"
  region = var.region
  assume_role {
    # This role must exist in the Central Account and trust this Service Account
    role_arn = var.vpc_lattice_provider ? "arn:aws:iam::${var.central_account_id}:role/CentralNetworkSecretsWriter" : null
  }
}

# ------------------------------------------------------------------------------
# 1. VPC LATTICE SERVICE
# ------------------------------------------------------------------------------
module "vpc_lattice_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "1.1.0"

  count = var.vpc_lattice_provider ? 1 : 0

  services = {
    lambdaservice = {
      name      = "lambda-service"
      auth_type = "AWS_IAM" # <--- Security Overlay
      auth_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Action    = "*"
            Effect    = "Allow"
            Principal = "*"
            Resource  = "*"
          }
        ]
      })

      listeners = {
        https_listener = {
          name     = "httpslistener"
          port     = 443
          protocol = "HTTPS"
          default_action_forward = {
            target_groups = {
              lambdatarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambdatarget = {
      type = "LAMBDA"
      targets = {
        lambdafunction = { id = aws_lambda_function.lambda[0].arn }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# 2. RAM SHARE (Layer 1 Sharing)
# ------------------------------------------------------------------------------
resource "aws_ram_resource_share" "lattice_service_share" {
  count = var.vpc_lattice_provider ? 1 : 0

  name                      = "lattice-service-share-lambda"
  allow_external_principals = true
  tags = {
    Name = "lattice-service-share"
  }
}

resource "aws_ram_principal_association" "central_account_association" {
  count = var.vpc_lattice_provider ? 1 : 0

  principal          = var.central_account_id
  resource_share_arn = aws_ram_resource_share.lattice_service_share[0].arn
}

resource "aws_ram_resource_association" "service_association" {
  for_each = var.vpc_lattice_provider ? module.vpc_lattice_service[0].services : {}

  resource_arn       = each.value.attributes.arn
  resource_share_arn = aws_ram_resource_share.lattice_service_share[0].arn
}

# ------------------------------------------------------------------------------
# 3. REGISTRATION HOOK (Secrets Manager)
# ------------------------------------------------------------------------------
locals {
  # Safe navigation using 'try' to avoid errors during 'plan' phase when count is 0
  service_registration_payload = {
    service_id    = try(module.vpc_lattice_service[0].services["lambdaservice"].attributes.id, "")
    ram_share_arn = try(aws_ram_resource_share.lattice_service_share[0].arn, "")
  }
}

data "aws_secretsmanager_secret" "central_registry" {
  count    = var.vpc_lattice_provider ? 1 : 0
  provider = aws.central_network_writer
  name     = "vpclattice_services"
}

resource "aws_secretsmanager_secret_version" "register_service" {
  count = var.vpc_lattice_provider ? 1 : 0

  provider      = aws.central_network_writer
  secret_id     = data.aws_secretsmanager_secret.central_registry[0].id
  secret_string = jsonencode(local.service_registration_payload)
}



# ------------------------------------------------------------------------------
# LAMBDA FUNCTION (BACKEND SERVICE)
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda" {
  count = var.vpc_lattice_provider ? 1 : 0

  function_name    = "lattice-service-lambda"
  role             = aws_iam_role.lambda_role[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  timeout = 30
}

# ------------------------------------------------------------------------------
# LAMBDA PERMISSION (ALLOW LATTICE TO INVOKE)
# ------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_lattice" {
  count = var.vpc_lattice_provider ? 1 : 0

  statement_id  = "AllowExecutionFromVPCLattice"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda[0].function_name
  principal     = "vpc-lattice.amazonaws.com"

  # Link permission specifically to the Lattice Target Group ARN
  source_arn = module.vpc_lattice_service[0].target_groups["lambdatarget"].arn
}

# ------------------------------------------------------------------------------
# IAM ROLE & LOGGING
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  count = var.vpc_lattice_provider ? 1 : 0
  name  = "lattice-service-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  count      = var.vpc_lattice_provider ? 1 : 0
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ------------------------------------------------------------------------------
# PACKAGE SOURCE CODE
# ------------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  count       = var.vpc_lattice_provider ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_function.py"
  output_path = "${path.module}/scripts/lambda_function.zip"
}
