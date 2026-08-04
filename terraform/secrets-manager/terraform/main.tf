resource "aws_secretsmanager_secret" "github_app" {
  description = "secrets for infra agent github app"
  name        = "arc-ipa/github-app"
  tags = {
    env                        = var.env
    team                       = var.team
    owner                      = var.owner
  }
}

resource "aws_secretsmanager_secret" "atlassian_app" {
  description = "secrets for infra agent atlassian app"
  name        = "arc-ipa/atlassian-app"
  tags = {
    env                        = var.env
    team                       = var.team
    owner                      = var.owner
  }
}



resource "aws_secretsmanager_secret" "datadog_terraform_key" {
  description = "Datadog API key for OTEL trace export"
  name        = "arc-ipa/datadog-terraform-key"
  tags = {
    env   = var.env
    team  = var.team
    owner = var.owner
  }
}