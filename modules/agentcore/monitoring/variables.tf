variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "infra-agent"
}

variable "model_id" {
  type        = string
  description = "The Bedrock model ID to monitor"
}

variable "alarm_threshold" {
  type        = number
  description = "Input token count threshold to trigger the alarm"
}

variable "alarm_period" {
  type        = number
  description = "Evaluation period in seconds"
}

variable "alarm_evaluation_periods" {
  type        = number
  description = "Number of periods to evaluate before triggering"
}

variable "alarm_statistic" {
  type        = string
  description = "Statistic to apply to the metric"
}

variable "alarm_comparison_operator" {
  type        = string
  description = "Comparison operator for the alarm"
}

variable "cooldown_minutes" {
  type        = number
  description = "Duration in minutes the kill switch stays active after alarm triggers"
  default     = 60
}
