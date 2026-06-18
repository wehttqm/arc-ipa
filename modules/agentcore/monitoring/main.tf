data "terraform_remote_state" "runtime" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/runtime/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "iam" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/iam/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

# Lambda to enable kill switch when token limit is breached
resource "aws_lambda_function" "kill_switch" {
  function_name    = "${var.stack_name}-kill-switch"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.kill_switch.arn
  filename         = data.archive_file.kill_switch.output_path
  source_code_hash = data.archive_file.kill_switch.output_base64sha256

  environment {
    variables = {
      KILL_SWITCH_PARAM = aws_ssm_parameter.kill_switch.name
      COOLDOWN_MINUTES  = var.cooldown_minutes
    }
  }
}

resource "aws_ssm_parameter" "kill_switch" {
  name  = "/${var.stack_name}/kill-switch"
  type  = "String"
  value = "false"

  lifecycle {
    ignore_changes = [value]
  }
}

data "archive_file" "kill_switch" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/kill_switch.zip"
}

resource "aws_iam_role" "kill_switch" {
  name = "${var.stack_name}-kill-switch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "kill_switch" {
  name = "kill-switch"
  role = aws_iam_role.kill_switch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = aws_ssm_parameter.kill_switch.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kill_switch.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm.arn
}

resource "aws_sns_topic" "alarm" {
  name = "${var.stack_name}-token-limit-alarm"
}

resource "aws_sns_topic_subscription" "kill_switch" {
  topic_arn = aws_sns_topic.alarm.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.kill_switch.arn
}

# CloudWatch alarm
resource "aws_cloudwatch_metric_alarm" "input_token_daily_limit" {
  alarm_name          = "${var.stack_name}-input-tokens-daily-limit"
  alarm_description   = "Triggers when daily input tokens on AgentCore exceeds ${var.alarm_threshold}, stops the runtime endpoint"
  comparison_operator = var.alarm_comparison_operator
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_threshold

  metric_name = "InputTokenCount"
  namespace   = "AWS/Bedrock"
  statistic   = var.alarm_statistic
  period      = var.alarm_period

  dimensions = {
    ModelId = var.model_id
  }

  alarm_actions = [aws_sns_topic.alarm.arn]
}
