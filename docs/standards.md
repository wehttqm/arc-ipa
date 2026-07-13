# Standards

## Overview

Standards are the rules the agent enforces: how resources are named, what tags are applied, and what security invariants must hold. They live as files in `arc-ipa-tf/standards/` so they're versioned, reviewable, and updatable via PR without redeploying the agent.

Standards are surfaced to the agent in three tiers:
- **Machine-enforced (JSON):** Files in `policies/` are loaded by `validate_request` and gate provisioning deterministically (naming patterns, name-length limits, environment validation).
- **Agent-context (Markdown prompts):** Files in `prompts/` are injected into the system prompt at boot. They shape how the agent writes Terraform but aren't pass/fail gates.
- **On-demand references (Markdown):** Files in `references/` are available via the `lookup_standard` tool for situational context (kubernetes, debugging, planning).

## Directory Structure

```
standards/
├── policies/          (machine-enforced JSON)
│   ├── accounts.json
│   ├── naming.json
│   └── tagging.json
├── prompts/           (always injected into system prompt)
│   ├── terraform.md
│   └── aws-infrastructure.md
└── references/        (on-demand via lookup_standard tool)
    ├── kubernetes.md
    ├── infra-planning.md
    └── debugging.md
```

## How the Agent Reads Standards

**JSON standards** — read by `validate_request` from the `policies/` subdirectory via the GitHub Contents API from `arc-ipa-tf` main:

```
Developer request → validate_request tool → read_file("standards/policies/naming.json")
                                          → read_file("standards/policies/accounts.json")
                                          → read_file("standards/policies/tagging.json")
                                          → pass/fail
```

**Markdown prompts** — loaded once at agent boot by `standards.py`. The `load_standards()` function:
1. Loads all files in `prompts/` (stripped of frontmatter, concatenated) and appends them to the system prompt
2. Loads `accounts.json` and formats it as available environments
3. Builds a references index from `references/` (filename + description extracted from frontmatter)

**Markdown references** — loaded on-demand via the `lookup_standard` tool when the agent needs situational context (e.g., Kubernetes knowledge, debugging guides, infrastructure planning).

## Files

### `policies/accounts.json`

Maps environment names to Atlantis workspace and approval requirements.

```json
{
  "sandbox": {
    "workspace": "pf-sandbox-usw2",
    "requires_approval": false
  }
}
```

The agent validates the developer's requested environment against this file. Unknown environments are rejected with a list of valid options.

### `policies/naming.json`

Defines naming patterns per resource type. Each entry is an object with a `format` pattern and a `max_length` constraint. The agent interpolates variables from the request context.

```json
{
  "s3_bucket": { "format": "arcteryx-{team}-{env}-{purpose}", "max_length": 63 },
  "lambda": { "format": "arcteryx-{team}-{env}-{purpose}-fn", "max_length": 64 },
  "k8s_namespace": { "format": "{team}-{env}-{service}", "max_length": 63 },
  "iam_role": { "format": "{team}-{env}-{purpose}-role", "max_length": 64 },
  "security_group": { "format": "{team}-{env}-{purpose}-sg", "max_length": 255 },
  "eks_cluster": { "format": "{team}-{env}-eks", "max_length": 100 },
  "vpc": { "format": "{team}-{env}-vpc", "max_length": 255 }
}
```

**Variables available:**
| Variable | Source |
|----------|--------|
| `{team}` | Developer provides |
| `{env}` | Developer provides |
| `{purpose}` | Developer provides |
| `{service}` | Developer provides |

The agent rejects requests that would produce names exceeding the `max_length` for that resource type.

### `policies/tagging.json`

Defines tags that are automatically applied to every provisioned resource.

```json
{
  "auto_applied": {
    "ManagedBy": "terraform",
    "Repository": "arc-ipa-tf"
  }
}
```

The `validate_request` tool assembles the full tag set by combining:
- **From developer inputs:** Team, Environment, and Application tags
- **From auto_applied:** Tags defined in this file (applied without asking the developer)

### `prompts/terraform.md`

Arc'teryx Terraform conventions: file structure, `yamlencode()` for Helm, IAM policy extraction, tagging patterns, remote state, Atlantis workflow, module thresholds. Injected into agent context at boot.

### `prompts/aws-infrastructure.md`

AWS infrastructure standards: security rules (KMS, TLS, least-privilege IAM), naming convention, required tags, VPC CIDR allocation, EKS standards, environment checklist. Injected into agent context at boot.

### `references/kubernetes.md`

Kubernetes specialist knowledge. Available on-demand via `lookup_standard("kubernetes.md")`.

### `references/infra-planning.md`

Infrastructure planning guidance. Available on-demand via `lookup_standard("infra-planning.md")`.

### `references/debugging.md`

Debugging guides and troubleshooting patterns. Available on-demand via `lookup_standard("debugging.md")`.

## Updating Standards

1. Open a PR on `arc-ipa-tf` that modifies files in `standards/`
2. Team reviews the change
3. Merge to main
4. Agent immediately reads the new standards on next request (no redeploy needed)

## Validation Logic

The `validate_request` tool performs these checks in order:

| # | Check | Failure Message |
|---|-------|-----------------|
| 1 | Environment exists in accounts.json | "Unknown environment: {env}. Valid: sandbox, ..." |
| 2 | Resource type exists in naming.json | "Unsupported resource type: {type}" |
| 3 | Generated name (from format pattern) doesn't exceed max_length | "Name '{name}' exceeds {type} limit of {max_length} characters" |

If any check fails, the agent reports the error and helps the developer correct it. It never proceeds to write Terraform with invalid inputs.
