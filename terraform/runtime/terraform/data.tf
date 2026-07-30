data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

data "terraform_remote_state" "ecr" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/ecr/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "webhook_handler" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/webhook-handler/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "secrets_manager" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/secrets-manager/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "gateway" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/gateway/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "identity" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/identity/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "monitoring" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/monitoring/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}

data "terraform_remote_state" "memory" {
  backend   = "s3"
  workspace = terraform.workspace
  config = {
    bucket               = "arcteryx-pf-sandbox"
    key                  = "agentcore/memory/terraform.tfstate"
    region               = "us-west-2"
    workspace_key_prefix = "agentcore"
  }
}
