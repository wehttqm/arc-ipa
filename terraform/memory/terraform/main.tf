# -----------------------------------------------------------------------------
# AgentCore Memory
#
# Durable store for conversation history. The agent runs on Runtime microVMs that
# are reclaimed after 15 minutes idle (max 8 hours), so in-process history dies
# with the instance while the Teams conversation id lives on. Memory keys events
# on (actorId, sessionId) — runtimeUserId and the conversation id — so a thread
# picks up where it left off on a fresh instance.
#
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory.html
# Ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-lifecycle-settings.html
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory" "this" {
  name                  = local.memory_name
  description           = var.description
  event_expiry_duration = var.event_expiry_days
  encryption_key_arn    = var.encryption_key_arn

  # Required once a strategy invokes a model on stored events. Attached
  # unconditionally so enabling long_term_strategies is a tfvars-only change.
  memory_execution_role_arn = aws_iam_role.memory_execution.arn

  tags = merge(local.common_tags, { Name = local.memory_name })
}

# -----------------------------------------------------------------------------
# Long-term strategies (opt-in via long_term_strategies)
#
# Declared as separate resources rather than inline so adding one does not
# replace the memory and lose every stored conversation.
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory_strategy" "this" {
  for_each = { for s in var.long_term_strategies : s.name => s }

  memory_id   = aws_bedrockagentcore_memory.this.id
  name        = each.value.name
  type        = each.value.type
  description = each.value.description
  namespace_templates = [each.value.namespace_template]
}

# -----------------------------------------------------------------------------
# Memory execution role — assumed by the service to run strategy extraction
# -----------------------------------------------------------------------------

resource "aws_iam_role" "memory_execution" {
  name = "${local.name_prefix}-memory-execution-role"

  assume_role_policy = templatefile("${path.module}/assume-role-policy.json", {
    account_id = data.aws_caller_identity.current.id
    region     = data.aws_region.current.region
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-memory-execution-role" })
}

resource "aws_iam_role_policy_attachment" "memory_model_inference" {
  role       = aws_iam_role.memory_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# Agent access to the memory
#
# The runtime execution role currently also carries BedrockAgentCoreFullAccess,
# which subsumes this. Declared explicitly anyway so memory access survives that
# policy being scoped down, and so the blast radius is written down: this agent
# may read and write this one memory, nothing else.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "agent_memory_access" {
  name        = "${local.name_prefix}-memory-access"
  description = "Read/write access to the agent's AgentCore Memory"

  policy = templatefile("${path.module}/iam-policy.json", {
    memory_arn = aws_bedrockagentcore_memory.this.arn
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "agent_memory_access" {
  role       = data.terraform_remote_state.iam.outputs.role_name
  policy_arn = aws_iam_policy.agent_memory_access.arn
}
