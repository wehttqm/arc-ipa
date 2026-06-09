data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = replace("${var.stack_name}_${var.agent_name}", "-", "_")
  description        = var.description
  role_arn           = aws_iam_role.agent_execution.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:${var.image_tag}"
    }
  }

  network_configuration {
    network_mode = var.network_mode
  }

  environment_variables = merge(
    {
      AWS_REGION         = var.region
      AWS_DEFAULT_REGION = var.region
    },
    var.environment_variables
  )

  depends_on = [
    aws_iam_role_policy.agent_execution,
    aws_iam_role_policy_attachment.agent_execution_managed
  ]
}
