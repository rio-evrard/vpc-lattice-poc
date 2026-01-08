# ------------------------------------------------------------------------------
# 1. THE AUTOMATION LAMBDA (The "Glue")
# # ------------------------------------------------------------------------------
resource "aws_lambda_function" "associator" {
  function_name    = "lattice-auto-associator"
  role             = aws_iam_role.associator_role.arn
  handler          = "associator.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  filename         = "${path.module}/associator.zip"
  source_code_hash = filebase64sha256("${path.module}/associator.zip")

  environment {
    variables = {
      SERVICE_NETWORK_ID  = module.vpclattice_service_network.service_network.id
      REGISTRY_SECRET_ARN = aws_secretsmanager_secret.provider_registry.arn
    }
  }
}

# ------------------------------------------------------------------------------
# 2. IAM PERMISSIONS
# ------------------------------------------------------------------------------
resource "aws_iam_role" "associator_role" {
  name = "LatticeAssociatorRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "associator_policy" {
  name = "LatticeAssociatorPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow reading the "Phone Book"
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.provider_registry.arn
      },
      {
        # Allow decrypting the secret
        Action   = ["kms:Decrypt"]
        Effect   = "Allow"
        Resource = aws_kms_key.secrets_key.arn
      },
      {
        # Allow Associating Services to the Network
        Action = [
          "vpc-lattice:CreateServiceNetworkServiceAssociation",
          "vpc-lattice:GetServiceNetworkServiceAssociation",
          "vpc-lattice:ListServiceNetworkServiceAssociations"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Basic Logging
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_associator" {
  role       = aws_iam_role.associator_role.name
  policy_arn = aws_iam_policy.associator_policy.arn
}

# ------------------------------------------------------------------------------
# 3. EVENT TRIGGER (CloudTrail / EventBridge)
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "secret_update" {
  name        = "capture-lattice-secret-update"
  description = "Trigger automation when a Provider registers a service"

  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["PutSecretValue", "UpdateSecret"]
      requestParameters = {
        secretId = [aws_secretsmanager_secret.provider_registry.arn]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.secret_update.name
  target_id = "TriggerAssociator"
  arn       = aws_lambda_function.associator.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.associator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.secret_update.arn
}
