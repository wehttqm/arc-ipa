# -----------------------------------------------------------------------------
# GitHub App secret (contains OAuth client_id + client_secret alongside app_id,
# private_key, and installation_id used elsewhere).
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "github_app" {
  secret_id = "arc-ipa/github-app"
}

locals {
  github_app = jsondecode(data.aws_secretsmanager_secret_version.github_app.secret_string)
}

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
