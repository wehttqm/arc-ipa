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
