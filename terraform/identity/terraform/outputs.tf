output "github_credential_provider_arn" {
  description = "ARN of the GitHub OAuth2 credential provider"
  value       = aws_bedrockagentcore_oauth2_credential_provider.github.credential_provider_arn
}

output "github_credential_provider_name" {
  description = "Name of the GitHub OAuth2 credential provider (used in @requires_access_token)"
  value       = aws_bedrockagentcore_oauth2_credential_provider.github.name
}

output "atlassian_credential_provider_arn" {
  description = "ARN of the Atlassian OAuth2 credential provider"
  value       = aws_bedrockagentcore_oauth2_credential_provider.atlassian.credential_provider_arn
}

output "atlassian_credential_provider_name" {
  description = "Name of the Atlassian OAuth2 credential provider (used in @requires_access_token)"
  value       = aws_bedrockagentcore_oauth2_credential_provider.atlassian.name
}

output "workload_identity_name" {
  description = "Name of the agent workload identity"
  value       = aws_bedrockagentcore_workload_identity.agent.name
}

output "workload_identity_arn" {
  description = "ARN of the agent workload identity"
  value       = aws_bedrockagentcore_workload_identity.agent.workload_identity_arn
}