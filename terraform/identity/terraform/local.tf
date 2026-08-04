locals {
  name_prefix    = "arc-agent-${var.environment}"
  github_app     = jsondecode(data.aws_secretsmanager_secret_version.github_app.secret_string)
  atlassian_app  = jsondecode(data.aws_secretsmanager_secret_version.atlassian_app.secret_string)

  # The bot's OAuth callback — used as the return URL for all 3LO providers.
  # Must match what's registered on each OAuth app and on the workload identity's
  # AllowedResourceOauth2ReturnUrls.
  oauth_callback_url = var.oauth_callback_url

  common_tags = {
    Team        = "platform"
    Environment = var.environment
    Application = "arc-agent"
    ManagedBy   = "terraform"
    Repository  = "arc-ipa-tf"
  }
}
