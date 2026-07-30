output "alarm_name" {
  description = "CloudWatch alarm name for the kill switch (agent reads this via DescribeAlarms)"
  value       = aws_cloudwatch_metric_alarm.input_token_daily_limit.alarm_name
}
