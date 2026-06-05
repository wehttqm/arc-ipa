variable "region" {
  type    = string
  default = "us-west-2"
}

variable "env" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "backend_bucket" {
  type = string
}

variable "atlantis_chart_version" {
  type    = string
  default = "5.20.2"
}

variable "atlantis_domain" {
  type = string
}

variable "terraform_version" {
  type    = string
  default = "v1.11.3"
}

# GitHub App
variable "github_app_id" {
  type      = string
  sensitive = true
}

variable "github_app_installation_id" {
  type      = string
  sensitive = true
}

variable "github_app_private_key_asm_name" {
  type = string
}

variable "github_webhook_secret_asm_name" {
  type = string
}

variable "repo_allowlist" {
  type = string
}

# Ingress
variable "alb_scheme" {
  type    = string
  default = "internet-facing"
}

variable "allowed_ip_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "acm_certificate_arn" {
  type = string
}
