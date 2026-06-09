output "agent_runtime_id" {
  description = "ID of the agent runtime"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "agent_runtime_arn" {
  description = "ARN of the agent runtime"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.agent.repository_url
}

output "agent_execution_role_arn" {
  description = "ARN of the agent execution role"
  value       = aws_iam_role.agent_execution.arn
}
