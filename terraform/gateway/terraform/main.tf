# -----------------------------------------------------------------------------
# AgentCore Gateway
#
# This module creates:
#   1. IAM role for the gateway (assumed by bedrock-agentcore.amazonaws.com)
#   2. The gateway itself (MCP protocol, CUSTOM_JWT inbound auth)
#
# Scope: targets where the *agent's* identity is sufficient -- Lambda, API
# Gateway stages, internal MCP servers on SigV4, and third-party APIs using
# machine-to-machine or API-key auth. Services that need the *user's* identity
# (GitHub, Atlassian) do not belong here; those go through AgentCore Identity 3LO
# in the agent. See infra-agent/connectors/.
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM Role for the Gateway
# -----------------------------------------------------------------------------

resource "aws_iam_role" "gateway" {
  name = "${local.name_prefix}-gateway"

  assume_role_policy = templatefile("${path.module}/assume-role-policy.json", {
    account_id = data.aws_caller_identity.current.account_id
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "gateway_identity" {
  name = "agentcore-identity-access"
  role = aws_iam_role.gateway.id

  policy = templatefile("${path.module}/iam-policy.json", {
    region      = var.region
    account_id  = data.aws_caller_identity.current.account_id
    name_prefix = local.name_prefix
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

      # Required for MCP elicitation, and for any target that streams responses.
      # Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-mcp-elicitation.html
      streaming_configuration {
        enable_response_streaming = true
      }
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Gateway Targets
#
# None are managed here yet. Add targets for services where the agent's own
# identity is sufficient (Lambda, SigV4 APIs, M2M/API-key services).
#
# OAuth AUTHORIZATION_CODE (per-user) targets are now supported by the agent: it
# handles the JSON-RPC -32042 URL-mode elicitation the gateway returns when the
# caller has not consented, sends the user the authorization link, and the bot
# completes session binding with CompleteResourceTokenAuth
# (infra-agent/capabilities/elicitation.py, teams-bot/src/app.py). Before adding
# one, four things have to line up:
#
#   1. defaultReturnUrl on the target = the bot's ${PUBLIC_BASE_URL}/oauth/callback.
#   2. That URL registered as an allowed resource OAuth2 return URL on the
#      workload identity, or the redirect after consent is rejected.
#   3. This gateway role needs bedrock-agentcore:GetResourceOauth2Token plus
#      secretsmanager:GetSecretValue on the
#      bedrock-agentcore-identity!default/oauth2/* prefix. iam-policy.json
#      currently only covers the API-key path (GetResourceApiKey +
#      .../apikey/*), which is what outbound API-key targets need.
#   4. Prefer creating the target with an upfront mcpToolSchema. Without one the
#      gateway has to authorize before it can even list tools, which turns every
#      cold start into a consent prompt.
#
# Also note a target whose outbound auth cannot resolve can fail the whole
# gateway's MCP initialize, which costs the agent every gateway tool, not just
# that target's.
#
# GitHub and Atlassian still run through AgentCore Identity 3LO in the agent
# (infra-agent/capabilities/federation.py). Moving them here is now possible --
# see infra-agent/docs/IMPROVEMENTS.md §0 -- but it is a migration, not a
# prerequisite.
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-building-adding-targets-authorization.html
# -----------------------------------------------------------------------------
