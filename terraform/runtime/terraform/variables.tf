variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type = string
}

variable "agent_name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.agent_name))
    error_message = "Agent name must start with a letter, max 48 characters, alphanumeric and underscores only."
  }
}

variable "description" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "network_mode" {
  type = string

  validation {
    condition     = contains(["PUBLIC", "PRIVATE"], var.network_mode)
    error_message = "Network mode must be PUBLIC or PRIVATE."
  }
}

variable "oauth_callback_url" {
  type        = string
  description = "The OAuth callback URL for the agent's workload identity (external to terraform — the bot's public endpoint)"
}
