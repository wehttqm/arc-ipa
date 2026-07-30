# -----------------------------------------------------------------------------
# GitHub App secret (contains OAuth client_id + client_secret alongside app_id,
# private_key, and installation_id used elsewhere).
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "github_app" {
  secret_id = "arc-ipa/github-app"
}

data "aws_caller_identity" "current" {}

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
