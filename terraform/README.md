# AgentCore Terraform

## Deploy Order

Modules must be applied in dependency order. Modules at the same level can be applied in parallel.

```
1. iam, secrets-manager
2. ecr, gateway, identity, monitoring, memory
3. runtime
```

- `iam` and `secrets-manager` are roots — no dependencies on other modules.
- `identity` reads the `arc-ipa/github-app` secret at plan time, so `secrets-manager` must be applied first (the secret must exist, even if the value is populated manually).
- All tier-2 modules attach IAM policies to the execution role via `data.terraform_remote_state.iam`.
- `runtime` depends on all other modules — it reads remote state outputs from ecr, gateway, identity, monitoring, memory, and secrets-manager to build its environment variables.

### First-time bootstrap

```bash
# From each module's terraform/ directory:
terraform init
terraform workspace new pf-sandbox-usw2   # or select existing
terraform apply -var-file=workspaces/pf-sandbox-usw2.tfvars.json
```

Apply in the order above. After the first apply, Atlantis handles plans and applies via PR.

### Destroying

Reverse the deploy order: `runtime` first, then tier 2, then `iam` and `secrets-manager` last.


# After Deploy

When all the terraform has been applied, there are some thing that still need to be taken care of:

- Agentcore Identity Outbound Auth: determine variables needed by credential providers here. For example, the "github" outbound auth contains a callback URL that needs to be set on the github app. 
- Teams app: update variables (ex. the agent runtime ARN)