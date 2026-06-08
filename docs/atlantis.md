# Atlantis

## Overview

Atlantis is the existing Terraform execution layer. It runs `plan` and `apply` in response to PR comments. The agent uses it exactly as a human would — by commenting on PRs. Atlantis doesn't know or care that the commenter is a bot.

## Repo Structure

The IaC repo that the agent writes to and Atlantis plans/applies from:

```
arcteryx-platform/infra-provisioning
├── modules/                    (existing Terraform modules — agent calls these)
├── environments/
│   └── {account}/              (per-account Terraform configs)
├── standards/                  (validation rules as code)
│   ├── naming.json
│   ├── tagging.json
│   └── account-mapping.json
└── atlantis.yaml               (project config — maps dirs to workspaces)
```

- `modules/` — existing Terraform modules. Agent reads these to understand patterns, inputs, and structure. Uses them as reference when writing new Terraform or modifying existing configs.
- `environments/` — per-account configs (provider, backend, variables).
- `standards/` — the agent reads these at runtime for validation. Updated via PR.
- `atlantis.yaml` — defines project names, workspaces, and tfvars paths.

The agent writes files into the same directories a human would — the PR (authored by the GitHub App) identifies it as agent-generated.

## Role in the System

- **Executes Terraform** — the agent never runs `terraform` directly
- **Provides plan output** — the agent reads the plan from Atlantis's PR comment to verify correctness
- **Enforces GitOps** — all infrastructure changes go through PRs with full audit trail
- **Manages credentials** — Atlantis holds the IAM roles for AWS access, not the agent

## How the Agent Interacts with Atlantis

| Step | Agent Action | Atlantis Response |
|------|-------------|-------------------|
| 1 | Opens a PR with Terraform changes | Auto-plans (if `autoplan` enabled) or waits for comment |
| 2 | Comments `atlantis plan -p <project>` | Runs `terraform plan`, posts output as PR comment |
| 3 | Reads Atlantis plan comment (via webhook) | — |
| 4 | Comments `atlantis apply -p <project>` | Runs `terraform apply`, posts result as PR comment |

## Project Configuration (`atlantis.yaml`)

Each managed resource type gets a project entry in `atlantis.yaml` at the repo root:

```yaml
version: 3
projects:
  - name: s3-buckets-pf-sandbox-usw2
    dir: s3-buckets/terraform
    workspace: pf-sandbox-usw2
    autoplan:
      when_modified:
        - "**/*.tf"
        - "workspaces/pf-sandbox-usw2.tfvars.json"
      enabled: true
    workflow: default

workflows:
  default:
    plan:
      steps:
        - init
        - plan:
            extra_args:
              - "-var-file=workspaces/pf-sandbox-usw2.tfvars.json"
    apply:
      steps:
        - apply
```

Key points:
- `name` is what the agent passes to `-p` in comments
- `workspace` maps to the Terraform workspace (resolved from `account-mapping.json`)
- `extra_args` passes the correct tfvars file automatically
- `autoplan` triggers on relevant file changes in the PR

## Agent → Atlantis Mapping

Atlantis doesn't know about AWS accounts — it only knows project names. The agent's CLI context gives it an account (`aws-pf-sandbox`), but Atlantis needs a project name (`s3-buckets-pf-sandbox-usw2`) to know which workspace and tfvars to use. This mapping bridges the gap between what the developer provides and what Atlantis requires.

```
account (from CLI)  →  account-mapping.json  →  workspace  →  project name
aws-pf-sandbox      →  pf-sandbox-usw2       →  s3-buckets-pf-sandbox-usw2
```

Without this, the agent would have to hardcode or guess project names, which breaks if workspaces are added or renamed.

## Approval Flow

| Account Flag | Agent Behavior |
|-------------|----------------|
| `requires_approval: false` | Agent comments `atlantis apply` immediately after clean plan |
| `requires_approval: true` | Agent calls `notify_approver`, waits for PFND engineer to approve the PR, then comments `atlantis apply` |

For protected environments, the PR requires a GitHub review approval before Atlantis will accept the apply comment. This is configured via Atlantis `apply_requirements`:

```yaml
projects:
  - name: s3-buckets-prod-usw2
    apply_requirements:
      - approved
```

## What the Agent Sees from Atlantis

Atlantis posts structured comments on PRs. The GitHub App webhook parses these:

**Successful plan:**
```
Ran Plan for project: `s3-buckets-pf-sandbox-usw2`

<details><summary>Show Output</summary>

Terraform will perform the following actions:

  + aws_s3_bucket.example

Plan: 1 to add, 0 to change, 0 to destroy.

</details>
```

**Failed plan:**
```
**Plan Failed** for project: `s3-buckets-pf-sandbox-usw2`

<details><summary>Show Output</summary>

Error: ...

</details>
```

**Successful apply:**
```
Applied successfully for project: `s3-buckets-pf-sandbox-usw2`
```

## Atlantis Infrastructure

Atlantis itself is deployed on EKS in the platform account. Its infrastructure (Helm chart, IRSA role, IAM policy) is managed in `atlantis/terraform/` in this repo.

The IRSA role (`pf-sandbox-platform-dev-atlantis-irsa`) determines what Atlantis can provision. Permissions must be added to `atlantis/terraform/iam-policy.json` before the agent can provision new resource types.

## Adding a New Resource Type

To enable the agent to provision a new resource type via Atlantis:

1. Add IAM permissions for the resource to `atlantis/terraform/iam-policy.json`
2. Apply the atlantis project (`atlantis plan/apply -p atlantis-pf-sandbox-usw2`)
3. Add an `atlantis.yaml` project entry for the new resource type
4. Update `standards/` with naming/tagging rules for the new type
5. The agent can now provision it
