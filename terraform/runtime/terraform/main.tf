resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = replace("${var.stack_name}_${var.agent_name}", "-", "_")
  description        = var.description
  role_arn           = data.terraform_remote_state.iam.outputs.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${data.terraform_remote_state.ecr.outputs.repository_url}:${var.image_tag}"
    }
  }

  network_configuration {
    network_mode = var.network_mode
  }

  lifecycle { 
    # important: Prevents Terraform from resetting the container tag back to ":latest"
    # during infra updates when GHA has pushed a specific Git SHA tag instead.
    ignore_changes = [ 
      agent_runtime_artifact[0].container_configuration[0].container_uri
     ]
  }

  environment_variables = local.environment_variables 
}

# -----------------------------------------------------------------------------
# Runtime policy for the agent execution role
#
# Grants Bedrock model invocation, Marketplace subscription access,
# SecretsManager reads, and DynamoDB writes for webhook session registration.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "agent_runtime_access" {
  name        = "${var.stack_name}-runtime-access"
  description = "Bedrock, Marketplace, SecretsManager, and DynamoDB access for the agent"

  policy = templatefile("${path.module}/iam-policy.json", {
    region     = data.aws_region.current.region
    account_id = data.aws_caller_identity.current.account_id
    stack_name = var.stack_name
  })
}

resource "aws_iam_role_policy_attachment" "agent_runtime_access" {
  role       = data.terraform_remote_state.iam.outputs.role_name
  policy_arn = aws_iam_policy.agent_runtime_access.arn
}

# -----------------------------------------------------------------------------
# SSM parameters for CI/CD discovery
#
# The GHA workflow reads these at deploy time instead of hardcoding runtime names
# or ECR repos. Single source of truth lives in terraform.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "runtime_name" {
  name        = "/${var.stack_name}/runtime/name"
  type        = "String"
  value       = aws_bedrockagentcore_agent_runtime.this.agent_runtime_name
  description = "AgentCore Runtime name for CI/CD deployment"
}
