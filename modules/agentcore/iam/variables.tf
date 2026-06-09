variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "infra-agent"
}

variable "repository_arn" {
  type        = string
  description = "ARN of the ECR repository for image pull permissions"
}
