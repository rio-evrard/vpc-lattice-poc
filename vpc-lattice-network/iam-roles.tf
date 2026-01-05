# ------------------------------------------------------------------------------
# 1. WRITER ROLE (For Service Providers)
# ------------------------------------------------------------------------------
# This role allows Provider Accounts to "Publish" their service info.

resource "aws_iam_role" "secrets_writer" {
  name = "CentralNetworkSecretsWriter"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowProvidersToAssume"
      Effect = "Allow"
      Principal = {
        AWS = var.provider_account_principals # List of Provider Root ARNs
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Policy: Write Access to the "Provider Registry" Secret
resource "aws_iam_policy" "writer_policy" {
  name        = "CentralNetworkSecretsWriterPolicy"
  description = "Allows writing to the Lattice Provider Registry"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteToRegistry"
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy"
        ]
        Resource = aws_secretsmanager_secret.provider_registry.arn
      },
      {
        Sid    = "UseKMSKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "writer_attach" {
  role       = aws_iam_role.secrets_writer.name
  policy_arn = aws_iam_policy.writer_policy.arn
}


# ------------------------------------------------------------------------------
# 2. READER ROLE (For Consumers)
# ------------------------------------------------------------------------------
# This role allows Consumer Accounts to "Discover" the Network ID.

resource "aws_iam_role" "secrets_reader" {
  name = "CentralNetworkSecretsReader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowConsumersToAssume"
      Effect = "Allow"
      Principal = {
        AWS = var.consumer_account_principals # List of Consumer Root ARNs
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Policy: Read Access to the "Service Network Info" Secret
resource "aws_iam_policy" "reader_policy" {
  name        = "CentralNetworkSecretsReaderPolicy"
  description = "Allows reading the Lattice Service Network Info"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadNetworkInfo"
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy"
        ]
        Resource = aws_secretsmanager_secret.service_network_info.arn
      },
      {
        Sid    = "UseKMSKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "reader_attach" {
  role       = aws_iam_role.secrets_reader.name
  policy_arn = aws_iam_policy.reader_policy.arn
}
