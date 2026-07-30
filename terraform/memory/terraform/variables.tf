variable "environment" {
  type        = string
  description = "Deployment environment (e.g. sandbox, dev, prod)"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "arc-pf-agent"
  description = "Stack name, used to find the agent execution role to grant access to"
}

# --- Short-term memory (conversation history) ---

variable "event_expiry_days" {
  type        = number
  default     = 30
  description = <<-EOT
    Days before raw conversation events expire. This is the retention window for
    chat history: past it, a Teams thread the user returns to starts cold.
  EOT

  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365
    error_message = "event_expiry_days must be between 7 and 365."
  }
}

variable "description" {
  type    = string
  default = "Conversation history and long-term memory for the Arc'teryx infra agent"
}

variable "encryption_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for memory data. Null uses AWS managed encryption."
}

# --- Long-term memory (optional) ---

variable "long_term_strategies" {
  type = list(object({
    name               = string
    type               = string
    namespace_template = string
    description        = optional(string)
  }))
  default     = []
  description = <<-EOT
    Long-term memory strategies to attach. Empty (the default) means short-term
    only: conversation history survives, nothing is extracted or summarized by a
    model. Each strategy invokes a model on your events and costs accordingly, so
    add them deliberately.

    Namespace templates may interpolate {actorId}, {sessionId} and
    {memoryStrategyId}; actorId is the agent's runtimeUserId (entra+<oid>) and
    sessionId is the Teams conversation id.

    Example:
      [{
        name               = "user_preferences"
        type               = "USER_PREFERENCE"
        namespace_template = "/strategies/{memoryStrategyId}/actors/{actorId}"
      }]
  EOT

  validation {
    condition = alltrue([
      for s in var.long_term_strategies :
      contains(["SEMANTIC", "SUMMARIZATION", "USER_PREFERENCE", "EPISODIC"], s.type)
    ])
    error_message = "Strategy type must be SEMANTIC, SUMMARIZATION, USER_PREFERENCE or EPISODIC. CUSTOM strategies need a configuration block and are not supported by this module."
  }

  validation {
    condition     = length(var.long_term_strategies) <= 6
    error_message = "A memory can hold at most 6 strategies."
  }

  validation {
    condition     = length(distinct([for s in var.long_term_strategies : s.type])) == length(var.long_term_strategies)
    error_message = "Only one strategy of each built-in type is allowed per memory."
  }
}
