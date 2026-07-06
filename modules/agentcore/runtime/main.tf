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

  lifecycle {
    # important: Prevents Terraform from resetting the container tag back to ":latest"
    # during infra updates when GHA has pushed a specific Git SHA tag instead.
    ignore_changes = [ image_uri ]
  }

  environment_variables = merge(
    {
      AWS_REGION         = var.region
      AWS_DEFAULT_REGION = var.region
      SESSIONS_TABLE     = data.terraform_remote_state.webhook_handler.outputs.sessions_table_name
      KILL_SWITCH_ALARM  = "${var.stack_name}-input-tokens-daily-limit"

      # --- ADOT / CloudWatch GenAI observability activation ---
      # This is a bring-your-own-container runtime (custom Dockerfile runs
      # `opentelemetry-instrument`), which bypasses the agentcore toolkit that
      # would otherwise inject these. Without them the AWS OpenTelemetry distro
      # does NOT wire span export to the CloudWatch OTLP/Transaction Search
      # destination, so LOGS still reach CloudWatch (Invocations view) but SPANS
      # are dropped (empty Traces view / empty `aws/spans` log group).
      #
      # Do NOT set OTEL_EXPORTER_OTLP_ENDPOINT / _LOGS_HEADERS here: for a
      # runtime-hosted agent the runtime owns that destination; overriding it
      # would misroute telemetry.
      AGENT_OBSERVABILITY_ENABLED = "true"             # activates the ADOT GenAI pipeline
      OTEL_PYTHON_DISTRO          = "aws_distro"       # use AWS Distro for OpenTelemetry
      OTEL_PYTHON_CONFIGURATOR    = "aws_configurator" # AWS configurator for the ADOT SDK
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    },
    var.environment_variables
  )
}
