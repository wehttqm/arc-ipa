locals {
  name_prefix = "arc-agent-${var.environment}"

  # CreateMemory name pattern is [a-zA-Z][a-zA-Z0-9_]{0,47} — no hyphens.
  memory_name = replace("${local.name_prefix}_memory", "-", "_")

  common_tags = {
    Team        = "platform"
    Environment = var.environment
    Application = "arc-agent"
    ManagedBy   = "terraform"
    Repository  = "arc-ipa-tf"
  }
}
