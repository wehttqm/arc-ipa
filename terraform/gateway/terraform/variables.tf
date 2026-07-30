variable "environment" {
  type        = string
  description = "Deployment environment (e.g. sandbox, dev, prod)"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

# --- Inbound CUSTOM_JWT authorizer (issuer = the Teams bot) ---

variable "jwt_discovery_url" {
  type        = string
  description = "OIDC discovery URL of the inbound JWT issuer (the Teams bot). Must end with /.well-known/openid-configuration"

  validation {
    condition     = can(regex(".+/\\.well-known/openid-configuration$", var.jwt_discovery_url))
    error_message = "jwt_discovery_url must end with /.well-known/openid-configuration"
  }
}

variable "jwt_allowed_audience" {
  type        = list(string)
  description = "Allowed 'aud' values for inbound JWTs (the audience the bot stamps into tokens minted for the gateway)."
  default     = ["arc-agent-gateway"]
}
