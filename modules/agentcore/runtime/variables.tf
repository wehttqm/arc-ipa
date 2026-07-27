variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "infra-agent"
}

variable "agent_name" {
  type    = string
  default = "InfraProvisioningAgent"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.agent_name))
    error_message = "Agent name must start with a letter, max 48 characters, alphanumeric and underscores only."
  }
}

variable "description" {
  type    = string
  default = "Infrastructure provisioning agent for Arc'teryx dev teams"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "network_mode" {
  type    = string
  default = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "PRIVATE"], var.network_mode)
    error_message = "Network mode must be PUBLIC or PRIVATE."
  }
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "github_credential_provider_name" {
  type        = string
  default     = "arc-agent-sandbox-github"
  description = "Name of the AgentCore OAuth2 credential provider for GitHub"
}

variable "oauth_callback_url" {
  type        = string
  default     = "https://xbqvzz72-3978.usw2.devtunnels.ms/oauth/callback"
  description = "The OAuth callback URL for the agent's workload identity"
}

variable "gateway_endpoint" {
  type        = string
  default     = "https://arc-agent-sandbox-gateway-i5nkiz9qf8.gateway.bedrock-agentcore.us-west-2.amazonaws.com/mcp"
  description = "The endpoint for the Arc'teryx Gateway service"
}