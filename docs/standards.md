# Standards

## Overview

Standards are the rules the agent enforces: how resources are named, what tags are required, and what security invariants must hold. They live as files in `arc-ipa-tf/standards/` so they're versioned, reviewable, and updatable via PR without redeploying the agent.

Standards are surfaced to the agent in two tiers:
- **Machine-enforced (JSON):** `validate_request` loads these and gates provisioning deterministically (naming patterns, required tags, name-length limits).
- **Agent-context (Markdown):** `terraform.md` and `aws-infrastructure.md` are injected into the system prompt at boot. They shape how the agent writes Terraform but aren't pass/fail gates.

## How the Agent Reads Standards

**JSON standards** — read by `validate_request` via the GitHub Contents API from `arc-ipa-tf` main:

```
Developer request → validate_request tool → read_file("standards/naming.json")
                                          → read_file("standards/tagging.json")
                                          → pass/fail
```

**Markdown standards** — loaded once at agent boot by `standards.py`, stripped of IDE frontmatter, and appended to the system prompt. The agent also has a `read_standard` tool for situational docs (kubernetes, debugging, planning).

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
| `{env}` | Developer provides (dev/staging/prod) |
| `{purpose}` | Developer provides |
| `{service}` | Developer provides |

The agent rejects requests that would produce names exceeding AWS length limits.

### `standards/tagging.json`

Defines required tags and auto-applied tags.

```json
{
  "required": ["team", "environment", "application", "managed-by"],
  "auto_applied": {
    "managed-by": "agentcore",
    "provisioned-date": "{date}"
  },
  "tag_sources": {
    "team": "developer_input",
    "environment": "developer_input",
    "application": "developer_input",
    "managed-by": "auto"
  }
}
```

- **required** — every provisioned resource must have these. The agent blocks provisioning if any are missing.
- **auto_applied** — the agent adds these without asking the developer.
- **tag_sources** — tells the agent where each tag value comes from.

### `standards/outputs.json`

Defines required Terraform outputs per resource type. The agent always includes these so it can report ARNs back to the developer.

### `standards/terraform.md`

Arc'teryx Terraform conventions: file structure, `yamlencode()` for Helm, IAM policy extraction, tagging patterns, remote state, Atlantis workflow, module thresholds. Injected into agent context at boot.

### `standards/aws-infrastructure.md`

AWS infrastructure standards: security rules (KMS, TLS, least-privilege IAM), naming convention, required tags, VPC CIDR allocation, EKS standards, environment checklist. Injected into agent context at boot.

### `standards/kubernetes.md`

Kubernetes specialist knowledge. Available on-demand via `read_standard("kubernetes.md")`.

## Updating Standards

1. Open a PR on `arc-ipa-tf` that modifies files in `standards/`
2. Team reviews the change
3. Merge to main
4. Agent immediately reads the new standards on next request (no redeploy needed)

## Validation Logic

The `validate_request` tool performs these checks in order:

| # | Check | Failure Message |
|---|-------|-----------------|
| 1 | Environment is valid (dev/staging/prod) | "Unknown environment: {env}. Valid: dev, prod, staging" |
| 2 | Resource type has a naming pattern | "Unsupported resource type: {type}" |
| 3 | Generated name fits within AWS length limits | "Name '{name}' exceeds S3 bucket limit of 63 characters" |
| 4 | All required tags can be resolved | "Missing required tag: {tag}." |

If any check fails, the agent reports the error and helps the developer correct it. It never proceeds to write Terraform with invalid inputs.
