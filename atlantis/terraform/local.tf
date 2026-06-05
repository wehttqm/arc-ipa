locals {
  github_app_key = try(
    jsondecode(data.aws_secretsmanager_secret_version.github_app_private_key.secret_string)["private-key"],
    data.aws_secretsmanager_secret_version.github_app_private_key.secret_string
  )

  github_webhook_secret = try(
    jsondecode(data.aws_secretsmanager_secret_version.github_webhook_secret.secret_string)["webhook_secret"],
    data.aws_secretsmanager_secret_version.github_webhook_secret.secret_string
  )
}
