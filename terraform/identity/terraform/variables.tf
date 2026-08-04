variable "environment" {
  type        = string
  description = "Deployment environment (e.g. sandbox, dev, prod)"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

# --- Workload Identity / Session Binding ---

variable "workload_identity_name" {
  type        = string
  description = "Name for the agent's workload identity (matches the Runtime-created identity if importing)"
}

variable "oauth_callback_url" {
  type        = string
  description = "Bot's OAuth callback URL for 3LO return redirects (e.g. https://your-bot.azurewebsites.net/oauth/callback)"
}
