output "memory_id" {
  description = "Memory ID — set as MEMORY_ID on the runtime so the session manager can find it"
  value       = aws_bedrockagentcore_memory.this.id
}

output "memory_arn" {
  description = "ARN of the AgentCore Memory"
  value       = aws_bedrockagentcore_memory.this.arn
}

output "memory_name" {
  description = "Name of the AgentCore Memory"
  value       = aws_bedrockagentcore_memory.this.name
}

output "memory_execution_role_arn" {
  description = "ARN of the role the memory service assumes for strategy extraction"
  value       = aws_iam_role.memory_execution.arn
}

output "strategy_ids" {
  description = "Map of strategy name to strategy ID for the configured long-term strategies"
  value       = { for k, s in aws_bedrockagentcore_memory_strategy.this : k => s.memory_strategy_id }
}

output "agent_memory_access_policy_arn" {
  description = "ARN of the policy granting the agent execution role access to this memory"
  value       = aws_iam_policy.agent_memory_access.arn
}
