output "github_app_secret_name" {
  value = aws_secretsmanager_secret.github_app.name
}

output "datadog_terraform_key_secret_name" {
  value = aws_secretsmanager_secret.datadog_terraform_key.name
}
