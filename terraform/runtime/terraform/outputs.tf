output "agent_runtime_id" {
  value = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
}

output "agent_runtime_arn" {
  value = aws_bedrockagentcore_agent_runtime.this.agent_runtime_arn
}

output "agent_runtime_name" {
  description = "The runtime name (used by CI/CD to find the runtime for deployment)"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_name
}
