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

# CloudWatch alarm — agent checks this directly via DescribeAlarms
resource "aws_cloudwatch_metric_alarm" "input_token_daily_limit" {
  alarm_name          = "${var.stack_name}-input-tokens-daily-limit"
  alarm_description   = "Triggers when daily input tokens on AgentCore exceeds ${var.alarm_threshold}"
  comparison_operator = var.alarm_comparison_operator
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.alarm_threshold

  metric_name = "CacheWriteInputTokenCount"
  namespace   = "AWS/Bedrock"
  statistic   = var.alarm_statistic
  period      = var.alarm_period

  dimensions = {
    ModelId = var.model_id
  }

  alarm_actions = [aws_sns_topic.alarm.arn]
}

resource "aws_sns_topic" "alarm" {
  name = "${var.stack_name}-token-limit-alarm"
}
