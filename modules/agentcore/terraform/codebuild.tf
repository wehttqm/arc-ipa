resource "aws_codebuild_project" "agent_image" {
  name         = "${var.stack_name}-agent-build"
  service_role = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_LARGE"
    image                       = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
    type                        = "ARM_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.agent.name
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.image_tag
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.agent_source.id}/${aws_s3_object.agent_source.key}"
    buildspec = file("${path.module}/buildspec.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${var.stack_name}-agent-build"
    }
  }
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "${var.stack_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "CodeBuildPolicy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:log-group:/aws/codebuild/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.agent.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.agent_source.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.agent_source.arn
      }
    ]
  })
}

# Wait for IAM propagation before building
resource "time_sleep" "wait_for_iam" {
  depends_on      = [aws_iam_role_policy.codebuild]
  create_duration = "10s"
}

# Wait for image to be available in ECR after build
resource "time_sleep" "wait_for_image" {
  depends_on      = [null_resource.trigger_build]
  create_duration = "5s"
}

# Trigger build when source code changes
resource "null_resource" "trigger_build" {
  triggers = {
    source_code_md5 = data.archive_file.agent_source.output_md5
    ecr_repository  = aws_ecr_repository.agent.id
    buildspec       = filemd5("${path.module}/buildspec.yml")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build-image.sh \"${aws_codebuild_project.agent_image.name}\" \"${data.aws_region.current.name}\" \"${aws_ecr_repository.agent.name}\" \"${var.image_tag}\" \"${aws_ecr_repository.agent.repository_url}\""
  }

  depends_on = [
    time_sleep.wait_for_iam,
    aws_codebuild_project.agent_image,
    aws_ecr_repository.agent,
    aws_s3_object.agent_source
  ]
}
