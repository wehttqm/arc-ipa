locals {
  name_prefix = "arc-agent-${var.environment}"

  common_tags = {
    Team        = "platform"
    Environment = var.environment
    Application = "arc-agent"
    ManagedBy   = "terraform"
    Repository  = "arc-ipa-tf"
  }
}
