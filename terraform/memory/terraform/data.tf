data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# The agent's runtime execution role, which needs data-plane access to the memory.
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
