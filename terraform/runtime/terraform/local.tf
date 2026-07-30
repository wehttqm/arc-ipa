# -----------------------------------------------------------------------------
# Runtime Environment Variables
#
# All env vars injected into the AgentCore Runtime microVM. Add new variables
# here rather than inline in the resource block.
#
# Values are pulled from the owning component's remote state rather than passed
# as variables, so renaming a resource upstream cannot leave a stale copy here.
# -----------------------------------------------------------------------------

locals {
  environment_variables = {
    AWS_REGION                      = var.region
    AWS_DEFAULT_REGION              = var.region
    DD_API_KEY_NAME                 = data.terraform_remote_state.secrets_manager.outputs.datadog_terraform_key_secret_name
    KILL_SWITCH_ALARM               = data.terraform_remote_state.monitoring.outputs.alarm_name
    GITHUB_CREDENTIAL_PROVIDER_NAME = data.terraform_remote_state.identity.outputs.github_credential_provider_name
    OAUTH_CALLBACK_URL              = var.oauth_callback_url
    GATEWAY_ENDPOINT                = data.terraform_remote_state.gateway.outputs.gateway_url
    MEMORY_ID                       = data.terraform_remote_state.memory.outputs.memory_id
  }
}
