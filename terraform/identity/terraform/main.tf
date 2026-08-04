# -----------------------------------------------------------------------------
# GitHub OAuth2 Credential Provider (per-user 3LO)
#
# Uses the built-in GithubOauth2 vendor — no discovery URL needed.
# Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagentcore_oauth2_credential_provider
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/identity-idps.html
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_oauth2_credential_provider" "github" {
  name                       = "${local.name_prefix}-github"
  credential_provider_vendor = "GithubOauth2"

  oauth2_provider_config {
    github_oauth2_provider_config {
      client_id     = local.github_app["client_id"]
      client_secret = local.github_app["client_secret"]
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Atlassian OAuth2 Credential Provider (per-user 3LO)
#
# Uses CustomOAuth vendor with Atlassian's authorization and token endpoints.
# The user consents once; AgentCore Identity vaults the refresh token and
# handles rotation. Actions in Jira/Confluence are attributed to the real user.
#
# Prerequisites:
#   1. Create an OAuth 2.0 (3LO) app at https://developer.atlassian.com/console/myapps/
#   2. Add scopes: read:me, read:jira-user, read:jira-work, write:jira-work,
#      read:confluence-content.all, offline_access
#   3. Set callback URL to the bot's OAuth callback
#   4. Store client_id and client_secret in Secrets Manager at arc-ipa/atlassian-app
#
# Ref: https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/identity-getting-started-custom.html
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_oauth2_credential_provider" "atlassian" {
  name                       = "${local.name_prefix}-atlassian"
  credential_provider_vendor = "CustomOauth2"

  oauth2_provider_config {
    custom_oauth2_provider_config {
      client_id     = local.atlassian_app["client_id"]
      client_secret = local.atlassian_app["client_secret"]

      oauth_discovery {
        authorization_server_metadata {
          issuer                 = "https://auth.atlassian.com"
          authorization_endpoint = "https://auth.atlassian.com/authorize"
          token_endpoint         = "https://auth.atlassian.com/oauth/token"
          response_types         = ["code"]
        }
      }
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Workload Identity — session-binding callback for 3LO
#
# Registers the bot's OAuth callback URL so AgentCore Identity can redirect the
# user's browser there after consent. The callback verifies the user session and
# calls CompleteResourceTokenAuth to store the token in the vault.
#
# NOTE: For agents deployed on Runtime, a workload identity is auto-created.
# If you need to manage an existing one, import it first:
#   terraform import aws_bedrockagentcore_workload_identity.agent <name>
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/oauth2-authorization-url-session-binding.html
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_workload_identity" "agent" {
  name = var.workload_identity_name
}

# -----------------------------------------------------------------------------
# Identity access policy for the agent execution role
#
# Grants the runtime role permission to fetch workload access tokens (for
# machine-to-machine auth) and per-user OAuth2 tokens (for outbound 3LO).
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html#gateway-outbound-auth-oauth
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "agent_identity_access" {
  name        = "${local.name_prefix}-identity-access"
  description = "Workload access tokens and OAuth2 token vault access for the agent"

  policy = templatefile("${path.module}/iam-policy.json", {
    region     = var.region
    account_id = data.aws_caller_identity.current.account_id
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "agent_identity_access" {
  role       = data.terraform_remote_state.iam.outputs.role_name
  policy_arn = aws_iam_policy.agent_identity_access.arn
}
