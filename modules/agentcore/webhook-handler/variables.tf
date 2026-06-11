variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "infra-agent"
}

variable "agent_runtime_arn" {
  type        = string
  description = "AgentCore Runtime ARN to invoke sessions on"
}

variable "github_webhook_cidrs" {
  type        = list(string)
  description = "GitHub webhook IP ranges (from https://api.github.com/meta 'hooks' field)"
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
  ]
}
