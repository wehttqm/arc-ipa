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

# -----------------------------------------------------------------------------
# Observability policy for the agent execution role
#
# Grants CloudWatch Logs, X-Ray trace export, and CloudWatch Metrics write
# permissions to the runtime microVMs and the ADOT sidecar.
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "agent_monitoring_access" {
  name        = "${var.stack_name}-monitoring-access"
  description = "CloudWatch, X-Ray, and metrics access for the agent execution role"

  policy = templatefile("${path.module}/iam-policy.json", {
    region     = var.region
    account_id = data.aws_caller_identity.current.account_id
  })
}

resource "aws_iam_role_policy_attachment" "agent_monitoring_access" {
  role       = data.terraform_remote_state.iam.outputs.role_name
  policy_arn = aws_iam_policy.agent_monitoring_access.arn
}
