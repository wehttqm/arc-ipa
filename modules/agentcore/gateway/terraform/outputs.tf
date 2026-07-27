output "gateway_id" {
  description = "AgentCore Gateway ID"
  value       = aws_bedrockagentcore_gateway.main.gateway_id
}

output "gateway_arn" {
  description = "AgentCore Gateway ARN"
  value       = aws_bedrockagentcore_gateway.main.gateway_arn
}

output "gateway_url" {
  description = "Gateway MCP endpoint URL (pass to agent as GATEWAY_ENDPOINT env var)"
  value       = aws_bedrockagentcore_gateway.main.gateway_url
}

output "gateway_role_arn" {
  description = "IAM role ARN used by the gateway"
  value       = aws_iam_role.gateway.arn
}

output "github_credential_provider_arn" {
  description = "ARN of the GitHub OAuth2 credential provider (from identity module remote state)"
  value       = local.github_credential_provider_arn
}

output "oauth_callback_url" {
  description = "OAuth callback URL configured for the gateway target"
  value       = var.oauth_callback_url
}
