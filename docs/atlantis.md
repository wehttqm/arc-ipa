# Atlantis

## Overview

Atlantis is the existing Terraform execution layer. It runs `plan` and `apply` in response to PR comments. The agent uses it exactly as a human would — by commenting on PRs. Atlantis doesn't know or care that the commenter is a bot.

## Repo Structure

There are two repos:

- **`arc-ipa-tf`** — the Terraform that the agent reads/writes and Atlantis plans/applies. This is where provisioned infrastructure lives.
- **`arc-ipa`** — the agent's own infrastructure (AgentCore runtime, IAM, ECR, Atlantis deployment), CLI, and docs.

The agent operates on `arc-ipa-tf`:

```
arc-ipa-tf/
├── modules/                    (per-resource-type directories)
│   └── s3-buckets/
│       └── terraform/
│           ├── main.tf
│           ├── variables.tf
│           ├── provider.tf
│           └── workspaces/
│               └── pf-sandbox-usw2.tfvars.json
├── standards/                  (validation rules + agent guidance)
│   ├── naming.json
│   ├── tagging.json
│   ├── outputs.json
│   ├── terraform.md
│   ├── aws-infrastructure.md
│   └── kubernetes.md
└── atlantis.yaml               (project config — maps dirs to workspaces)
```

- `modules/` — per-resource-type directories (e.g. `modules/s3-buckets/`), each containing a `terraform/` directory with configs and workspace-specific tfvars. The agent reads these to understand patterns and writes new Terraform here.
- `standards/` — JSON for machine-enforced validation, markdown for agent guidance. Updated via PR.
- `atlantis.yaml` — defines project names, workspaces, and tfvars paths.

## Role in the System

- **Executes Terraform** — the agent never runs `terraform` directly
- **Provides plan output** — the agent reads the plan from Atlantis's PR comment to verify correctness
- **Enforces GitOps** — all infrastructure changes go through PRs with full audit trail
- **Manages credentials** — Atlantis holds the IAM roles for AWS access, not the agent

## How the Agent Interacts with Atlantis

| Step | Agent Action | Atlantis Response |
|------|-------------|-------------------|
| 1 | Opens a PR with Terraform changes | Atlantis auto-plans all affected projects (posts plan output as PR comment) |
| 2 | Reads Atlantis plan comment (via webhook) | — |
| 3 | Comments `atlantis apply -p <project>` | Runs `terraform apply`, posts result as PR comment |

**Important:** The agent must NOT comment `atlantis plan` immediately after opening a PR. Autoplan is enabled — Atlantis will detect the changed files and plan automatically. The agent should only comment `atlantis plan -p <project>` if it needs to re-plan (e.g., after pushing additional commits or if the initial autoplan failed).

## Project Configuration (`atlantis.yaml`)

Each managed resource type gets a project entry in `atlantis.yaml` at the repo root:

```yaml
version: 3
projects:
  - name: s3-buckets-pf-sandbox-usw2
    dir: modules/s3-buckets/terraform
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
- `workspace` maps to the Terraform workspace
- `extra_args` passes the correct tfvars file automatically
- `autoplan` triggers on relevant file changes in the PR

## Agent → Atlantis Mapping

The agent derives the Atlantis project name from the resource type and the workspace (which comes from the environment the developer specifies and the `atlantis.yaml` config). The agent reads `atlantis.yaml` to discover the correct project name.

```
environment (from developer) → workspace in atlantis.yaml → project name
dev                                → pf-sandbox-usw2             → s3-buckets-pf-sandbox-usw2
```

## Approval Flow

| Environment | Agent Behavior |
|-------------|----------------|
| dev/staging | Agent comments `atlantis apply` immediately after clean plan |
| prod | Agent notifies approver, waits for PFND engineer to approve the PR, then comments `atlantis apply` |

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

Atlantis itself is deployed on EKS in the platform account. Its infrastructure (Helm chart, IRSA role, IAM policy) is managed in `arc-ipa` under `modules/atlantis/terraform/`.

The IRSA role determines what Atlantis can provision. Permissions must be added to `modules/atlantis/terraform/iam-policy.json` in `arc-ipa` before the agent can provision new resource types.

## Adding a New Resource Type

To enable the agent to provision a new resource type via Atlantis:

1. Add IAM permissions for the resource to `modules/atlantis/terraform/iam-policy.json` in `arc-ipa`
2. Apply the atlantis project (`atlantis plan/apply -p atlantis-pf-sandbox-usw2`)
3. Add an `atlantis.yaml` project entry in `arc-ipa-tf` for the new resource type
4. Update `standards/` in `arc-ipa-tf` with naming/tagging rules for the new type
5. The agent can now provision it
