locals {
  name_prefix = "arc-agent-${var.environment}"
  github_app  = jsondecode(data.aws_secretsmanager_secret_version.github_app.secret_string)

  common_tags = {
    Team        = "platform"
    Environment = var.environment
    Application = "arc-agent"
    ManagedBy   = "terraform"
    Repository  = "arc-ipa-tf"
  }
}
