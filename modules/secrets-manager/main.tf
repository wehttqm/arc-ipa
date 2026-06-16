resource "aws_secretsmanager_secret" "github_app" {
  description = "secrets for infra agent github app"
  name        = "arc-ipa/github-app"
  tags = {
    env                        = var.env
    team                       = var.team
    owner                      = var.owner
  }
}

# resource "aws_secretsmanager_secret_version" "github_app" {
#   secret_id     = aws_secretsmanager_secret.github_app.id
#   secret_string = jsonencode({
#     app_id          = ""
#     private_key     = ""
#     installation_id = ""
#     webhook_secret  = ""
#   })
# }