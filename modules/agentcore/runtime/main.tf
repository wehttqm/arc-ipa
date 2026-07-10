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

  lifecycle {
    # important: Prevents Terraform from resetting the container tag back to ":latest"
    # during infra updates when GHA has pushed a specific Git SHA tag instead.
    ignore_changes = [ 
      agent_runtime_artifact[0].container_configuration[0].container_uri
     ]
  }

  environment_variables = merge(
    {
      AWS_REGION         = var.region
      AWS_DEFAULT_REGION = var.region
      SESSIONS_TABLE     = data.terraform_remote_state.webhook_handler.outputs.sessions_table_name
      DD_API_KEY_NAME    = data.terraform_remote_state.secrets_manager.outputs.datadog_terraform_key_secret_name
      KILL_SWITCH_ALARM  = "${var.stack_name}-input-tokens-daily-limit"
    },
    var.environment_variables
  ) 
}
