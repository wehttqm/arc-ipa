# Standards

## Overview

Standards are the rules the agent enforces: how resources are named, what tags are required, and which accounts map to which environments. They live as JSON files in `arc-ipa-tf` (the `standards/` directory) so they're versioned, reviewable, and updatable via PR without redeploying the agent.

## How the Agent Reads Standards

The agent's `validate_request` tool reads standards files from `arc-ipa-tf` via the `read_file` tool (GitHub Contents API). It always reads from the default branch — so standards take effect as soon as a PR updating them is merged.

```
Developer request → validate_request tool → read_file("standards/naming.json")
                                          → read_file("standards/tagging.json")
                                          → read_file("standards/account-mapping.json")
                                          → pass/fail
```

## Files

### `standards/naming.json`

Defines naming patterns per resource type. The agent interpolates variables from the request context.

```json
{
  "s3_bucket": "arcteryx-{team}-{env}-{purpose}",
  "lambda": "arcteryx-{team}-{env}-{purpose}-fn",
  "k8s_namespace": "{team}-{env}-{service}"
}
```

**Variables available:**
| Variable | Source |
|----------|--------|
| `{team}` | Developer provides |
| `{env}` | Resolved from account-mapping.json |
| `{purpose}` | Developer provides |
| `{service}` | Developer provides |

The agent rejects requests that would produce names not matching the pattern, or names exceeding AWS length limits.

### `standards/tagging.json`

Defines required tags and auto-applied tags.

```json
{
  "required": ["team", "environment", "cost-center", "application", "managed-by"],
  "auto_applied": {
    "managed-by": "agentcore",
    "provisioned-date": "{date}"
  },
  "tag_sources": {
    "team": "developer_input",
    "environment": "account-mapping.json",
    "cost-center": "developer_input",
    "application": "developer_input",
    "managed-by": "auto"
  }
}
```

- **required** — every provisioned resource must have these. The agent blocks provisioning if any are missing.
- **auto_applied** — the agent adds these without asking the developer.
- **tag_sources** — tells the agent where each tag value comes from (developer input, derived from account, or automatic).

### `standards/account-mapping.json`

Maps account aliases to account IDs, environments, Terraform workspaces, and approval requirements.

```json
{
  "aws-pf-sandbox": {
    "account_id": "529088297181",
    "environment": "sandbox",
    "workspace": "pf-sandbox-usw2",
    "region": "us-west-2",
    "requires_approval": false
  },
  "aws-preprod-omni": {
    "account_id": "123456789012",
    "environment": "preprod",
    "workspace": "preprod-omni-usw2",
    "region": "us-west-2",
    "requires_approval": false
  },
  "aws-prod-omni": {
    "account_id": "345678901234",
    "environment": "prod",
    "workspace": "prod-omni-usw2",
    "region": "us-west-2",
    "requires_approval": true
  }
}
```

This file is the single source of truth for:
- Which accounts exist and are valid targets
- What workspace Atlantis uses for each account
- Whether the agent can auto-apply or must wait for approval
- What `{env}` value to use in naming/tagging

The CLI `--account` flag must match a key in this file. If it doesn't, the agent rejects the session upfront.

## Updating Standards

1. Open a PR on `arc-ipa-tf` that modifies files in `standards/`
2. Team reviews the change
3. Merge to main
4. Agent immediately reads the new standards on next request (no redeploy needed)

## Validation Logic

The `validate_request` tool performs these checks in order:

| # | Check | Failure Message |
|---|-------|-----------------|
| 1 | Account exists in account-mapping.json | "Unknown account: {account}. Valid accounts: ..." |
| 2 | Resource type has a naming pattern | "Unsupported resource type: {type}" |
| 3 | Generated name matches pattern and length limits | "Name '{name}' exceeds S3 bucket limit of 63 characters" |
| 4 | All required tags can be resolved | "Missing required tag: cost-center. Provide your team's cost center." |
| 5 | Account/environment consistency | "Account {account} is {env}, but you requested a prod resource" |

If any check fails, the agent reports the error and asks the developer to correct it. It never proceeds to write Terraform with invalid inputs.
