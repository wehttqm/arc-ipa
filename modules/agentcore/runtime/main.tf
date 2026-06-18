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

resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = replace("${var.stack_name}_${var.agent_name}", "-", "_")
  description        = var.description
  role_arn           = data.terraform_remote_state.iam.outputs.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${data.terraform_remote_state.ecr.outputs.repository_url}:${var.image_tag}"
    }
  }

  network_configuration {
    network_mode = var.network_mode
  }

  environment_variables = merge(
    {
      AWS_REGION         = var.region
      AWS_DEFAULT_REGION = var.region
      SESSIONS_TABLE     = data.terraform_remote_state.webhook_handler.outputs.sessions_table_name
      KILL_SWITCH_PARAM  = "/${var.stack_name}/kill-switch"
    },
    var.environment_variables
  )
}
