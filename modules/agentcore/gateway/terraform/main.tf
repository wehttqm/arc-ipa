# -----------------------------------------------------------------------------
# AgentCore Gateway — GitHub MCP target with per-user 3LO
#
# This module creates:
#   1. IAM role for the gateway (assumed by bedrock-agentcore.amazonaws.com)
#   2. The gateway itself (MCP protocol, IAM inbound auth)
#   3. A GitHub MCP target with OAuth AUTHORIZATION_CODE outbound auth
#
# The gateway acts as a proxy between the agent and GitHub's MCP server,
# handling per-user token acquisition via the Token Vault automatically.
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-building-adding-targets-authorization.html
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "identity" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore-identity/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "terraform-state-backend"
  }
}

locals {
  github_credential_provider_arn = data.terraform_remote_state.identity.outputs.github_credential_provider_arn
}

# -----------------------------------------------------------------------------
# IAM Role for the Gateway
# -----------------------------------------------------------------------------

resource "aws_iam_role" "gateway" {
  name = "${local.name_prefix}-gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "gateway_identity" {
  name = "agentcore-identity-access"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetWorkloadAccessToken"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/${local.name_prefix}-gateway-*",
        ]
      },
      {
        Sid    = "GetResourceTokens"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetResourceOauth2Token",
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:*",
        ]
      },
      {
        Sid    = "ReadCredentialSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          # The credential provider stores its client_secret in Secrets Manager.
          # Use a wildcard suffix since the secret ID is auto-generated.
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:bedrock-agentcore-identity*",
        ]
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# AgentCore Gateway — CUSTOM_JWT inbound auth
#
# The agent authenticates to the Gateway with a bearer JWT minted by the Teams
# bot (the OIDC issuer). See the authorizer_configuration block below.
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name     = "${local.name_prefix}-gateway"
  role_arn = aws_iam_role.gateway.arn

  # Inbound auth: the Teams bot acts as a minimal OIDC issuer. It mints a
  # short-lived RS256 JWT per user (sub = user id) that the agent forwards as
  # the bearer token when calling this gateway's MCP endpoint. The gateway
  # validates the token's signature against the bot's JWKS (fetched from the
  # discovery URL) plus iss/exp/aud before proxying to targets.
  # Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
  authorizer_type = "CUSTOM_JWT"

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = var.jwt_discovery_url
      allowed_audience = var.jwt_allowed_audience
    }
  }

  protocol_type = "MCP"

  protocol_configuration {
    mcp {
      supported_versions = ["2025-03-26", "2025-06-18", "2025-11-25"]

      # Required for MCP elicitation (the URL-mode 3LO consent prompt the
      # gateway forwards to the agent when a user has no GitHub token yet).
      # Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-mcp-elicitation.html
      streaming_configuration {
        enable_response_streaming = true
      }
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Gateway Target: GitHub MCP — per-user 3LO (Authorization Code Grant)
#
# NOT managed by Terraform. The AWS provider's create-waiter treats
# CREATE_PENDING_AUTH as an error, but that's the expected state for an
# AUTHORIZATION_CODE target until a real user authorizes at runtime.
#
# The target is created by the setup script (scripts/create-gateway-target.sh)
# which calls the AWS CLI and does NOT block on READY.
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-building-adding-targets-authorization.html
# -----------------------------------------------------------------------------
