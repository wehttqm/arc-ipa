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
