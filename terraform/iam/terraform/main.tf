# -----------------------------------------------------------------------------
# Agent Execution Role
#
# The central IAM role assumed by the AgentCore Runtime service. Component-specific
# permissions are defined in each component's own iam-policy.json and attached via
# aws_iam_role_policy_attachment referencing this role's name output.
#
# Components that attach policies to this role:
#   - ecr           (image pull)
#   - monitoring    (CloudWatch logs, X-Ray traces, metrics)
#   - identity      (workload access tokens, OAuth2 token vault)
#   - runtime       (Bedrock invocation, Marketplace, SecretsManager, DynamoDB)
#   - memory        (AgentCore Memory read/write)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "agent_execution" {
  name = "${var.stack_name}-agent-execution-role"

  assume_role_policy = templatefile("${path.module}/assume-role-policy.json", {
    account_id = data.aws_caller_identity.current.id
    region     = data.aws_region.current.region
  })
}

resource "aws_iam_role_policy_attachment" "agent_execution_managed" {
  role       = aws_iam_role.agent_execution.name
  policy_arn = "arn:aws:iam::aws:policy/BedrockAgentCoreFullAccess"
}

resource "aws_iam_role_policy_attachment" "agent_execution_readonly" {
  role       = aws_iam_role.agent_execution.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
