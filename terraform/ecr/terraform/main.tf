resource "aws_ecr_repository" "agent" {
  name                 = var.stack_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = file("${path.module}/ecr-lifecycle-policy.json")
}

# -----------------------------------------------------------------------------
# ECR access policy for the agent execution role
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "agent_ecr_access" {
  name        = "${var.stack_name}-ecr-access"
  description = "ECR image pull access for the agent execution role"

  policy = templatefile("${path.module}/iam-policy.json", {
    repository_arn = aws_ecr_repository.agent.arn
  })
}

resource "aws_iam_role_policy_attachment" "agent_ecr_access" {
  role       = data.terraform_remote_state.iam.outputs.role_name
  policy_arn = aws_iam_policy.agent_ecr_access.arn
}

# -----------------------------------------------------------------------------
# SSM parameters for CI/CD discovery
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "repository_name" {
  name        = "/${var.stack_name}/ecr/repository-name"
  type        = "String"
  value       = aws_ecr_repository.agent.name
  description = "ECR repository name for CI/CD image push"
}
