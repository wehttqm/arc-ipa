# Atlantis Configuration Files

This directory contains configuration files that control which Terraform projects and workspaces Atlantis will plan/apply.

## Files

### `enabled_contexts.json`

Lists the workspace contexts (environments) that Atlantis should process. The `gen-atlantis.py` script will only generate projects for workspaces matching these context names.

**Example:**

```json
["pf-sandbox-usw2", "omni-prod-use1", "ecomm-dev-usw2"]
```

**Behavior:**

- If empty (`[]`), **all** workspaces will be processed
- If populated, only workspaces containing any of these strings will be processed

### `skip_components.json`

Lists the component names that Atlantis should skip. Components are the directory names containing Terraform projects (e.g., `vpc`, `eks`, `karpenter`).

**Example:**

```json
["test", "experimental", "deprecated"]
```

**Behavior:**

- Components listed here will be completely skipped by Atlantis
- Useful for excluding test projects or components under development

## How It Works

When a PR is opened/updated:

1. Atlantis runs pre-workflow hooks from `repos.yaml`:
   - **Git credentials hook**: Configures git to use GitHub App token authentication for private module access. The hook generates a JWT from the GitHub App credentials, exchanges it for an installation access token, and configures git to use this token.
   - **Config generator hook**: Runs `gen-atlantis.py` to discover projects
2. The `gen-atlantis.py` script scans the repository for all `*.tfvars.json` files
3. For each tfvars file found:
   - Extracts the component name and workspace context
   - Checks if the component is in `skip_components.json` (skip if true)
   - Checks if the context matches any pattern in `enabled_contexts.json` (skip if no match)
   - Generates an Atlantis project config if all checks pass
4. Writes the generated config to `atlantis.yaml` in the repo root
5. Atlantis uses this config to run plans only for the included projects

### Private Module Access

Atlantis is configured to access private Terraform modules from GitHub repositories using GitHub App authentication. The pre-workflow hook in `repos.yaml` automatically:

1. Generates a JWT from the GitHub App credentials (`ATLANTIS_GH_APP_ID`, `ATLANTIS_GH_APP_KEY`)
2. Exchanges the JWT for an installation access token via the GitHub API
3. Configures git to use this token for authentication:

```bash
git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"
```

This allows Terraform to pull modules using sources like:

```hcl
module "example" {
  source = "git::https://github.com/arcteryx-pf/arcteryx-terraform-modules.git//module-name?ref=v1.0.0"
}
```

**Required Environment Variables**:

- `ATLANTIS_GH_APP_ID` - GitHub App ID
- `ATLANTIS_GH_APP_KEY` - GitHub App private key (PEM format)
- `ATLANTIS_GH_APP_INSTALLATION_ID` - Installation ID for the target organization

## Directory Structure Expected

The script expects this directory structure:

```
repo-root/
├── atlantis/
│   └── conf/
│       ├── enabled_contexts.json
│       └── skip_components.json
├── component/
│   └── terraform/
│       └── workspaces/
│           ├── pf-sandbox-usw2.tfvars.json
│           └── omni-prod-use1.tfvars.json
└── sandbox-local/
    └── component/
        └── terraform/
            └── workspaces/
                └── pf-sandbox-usw2.tfvars.json
```

## Examples

### Enable only sandbox environment

```json
// enabled_contexts.json
["pf-sandbox"]
```

This will process:

- ✅ `pf-sandbox-usw2`
- ✅ `pf-sandbox-use1`
- ❌ `omni-prod-use1`
- ❌ `ecomm-dev-usw2`

### Skip experimental components

```json
// skip_components.json
["test", "experimental"]
```

This will skip:

- ❌ `test/terraform/`
- ❌ `experimental/terraform/`
- ✅ `vpc/terraform/`
- ✅ `eks/terraform/`

### Process all workspaces except test

```json
// enabled_contexts.json
[]

// skip_components.json
["test"]
```

This processes **all** workspaces in **all** components except the `test` component.

## Updating Configuration

To update which projects Atlantis processes:

1. Edit `enabled_contexts.json` or `skip_components.json`
2. Commit and push changes
3. Open a new PR or update an existing one
4. Atlantis will automatically use the new configuration

**Note:** These files are checked into the repository and read by Atlantis from the checked-out code, so changes take effect immediately in new PRs.
