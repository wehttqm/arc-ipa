# DynamoDB table: maps repo + PR number → AgentCore session ID
# Key format: "{owner}/{repo}#{pr_number}" (e.g. "acme/infra#42")
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.stack_name}-webhook-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "repo_pr"

  attribute {
    name = "repo_pr"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# IAM role for the webhook Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.stack_name}-webhook-handler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "webhook-handler"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.sessions.arn
      },
      {
        Effect = "Allow"
        Action = ["bedrock-agentcore:InvokeAgentRuntime"]
        Resource = [
          var.agent_runtime_arn,
          "${var.agent_runtime_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = data.aws_secretsmanager_secret.github_app.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:*:*"
      }
    ]
  })
}

data "aws_secretsmanager_secret" "github_app" {
  name = "arc-ipa/github-app"
}

# Lambda function
resource "aws_lambda_function" "webhook" {
  function_name    = "${var.stack_name}-webhook-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SESSIONS_TABLE    = aws_dynamodb_table.sessions.name
      SECRET_NAME       = "arc-ipa/github-app"
      AGENT_RUNTIME_ARN = var.agent_runtime_arn
      AWS_REGION_NAME   = var.region
    }
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/index.zip"
}

# WAF: restrict to GitHub webhook IP ranges
# Source: https://api.github.com/meta → "hooks" field
resource "aws_wafv2_ip_set" "github_hooks" {
  name               = "${var.stack_name}-github-hooks"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.github_webhook_cidrs
}

resource "aws_wafv2_web_acl" "webhook" {
  name  = "${var.stack_name}-webhook-acl"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "allow-github-hooks"
    priority = 1
    action {
      allow {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.github_hooks.arn
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "github-hooks-allowed"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "webhook-acl"
  }
}

resource "aws_wafv2_web_acl_association" "webhook" {
  resource_arn = aws_api_gateway_stage.webhook.arn
  web_acl_arn  = aws_wafv2_web_acl.webhook.arn
}

# API Gateway REST API (v1 — required for WAF association)
resource "aws_api_gateway_rest_api" "webhook" {
  name = "${var.stack_name}-webhook"
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.webhook.id
  resource_id             = aws_api_gateway_resource.webhook.id
  http_method             = aws_api_gateway_method.webhook.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook.invoke_arn
}

resource "aws_api_gateway_deployment" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  depends_on  = [aws_api_gateway_integration.lambda]
}

resource "aws_api_gateway_stage" "webhook" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  deployment_id = aws_api_gateway_deployment.webhook.id
  stage_name    = "live"
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/*"
}
