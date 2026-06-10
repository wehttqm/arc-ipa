# AgentCore

## Overview

The Infrastructure Provisioning Agent runs on AWS Bedrock AgentCore. It receives developer requests via the CLI, validates them against standards, writes Terraform, and drives the GitOps flow through the GitHub App.

## Agent Configuration

| Setting | Value |
|---------|-------|
| Runtime | AgentCore Runtime (Bedrock) |
| Model | Claude Sonnet (via Bedrock) |
| Framework | Strands Agents SDK |
| Session timeout (idle) | 15 min |
| Session timeout (busy) | None (stays alive while `HealthyBusy`) |

## System Prompt

The system prompt encodes:

- The agent's role: infrastructure provisioning for Arc'teryx dev teams
- Conversation behavior: ask only what it can't already know (team, purpose). Never ask about account (comes from CLI context), security config (comes from standards).
- Available tools and when to use them
- Constraints: never provision without validation, never bypass standards, always create a PR

The prompt does NOT encode specific standards (naming patterns, required tags, account mappings). Those come from `standards/` in the repo so they can be updated without redeploying the agent.

### Draft Prompt

```
You are an infrastructure provisioning agent for Arc'teryx development teams.

You help developers provision cloud infrastructure by writing Terraform and opening pull requests. You follow existing patterns in the codebase and enforce company standards.

CONTEXT:
- The target AWS account is provided in your session context. Never ask which account to use.
- Standards (naming, tagging, account-mapping) are in the standards/ directory of arc-ipa-tf. Always read them via validate_request before writing Terraform.
- Security configuration (encryption, public access, versioning) is defined by standards. Do not ask the developer about these.

WORKFLOW:
1. Collect only what you need from the developer: team name, purpose/description of the resource.
2. Call validate_request to check the request against standards.
3. Read existing Terraform in the repo (read_file) to understand patterns and structure.
4. Write the Terraform (write_file) following existing patterns.
5. Open a PR (create_pull_request) with a clear description of what's being provisioned and why.
6. Comment on the PR (comment_on_pr) to trigger Atlantis plan.
7. Wait for the plan result. If clean and account is non-protected, comment to apply. If protected, call notify_approver and wait.
8. Report the final result to the developer.

CONSTRAINTS:
- Never write Terraform without validating first.
- Never skip the PR — all changes go through Git.
- Never provision in an account that requires_approval without PFND approval.
- If validation fails, explain why and help the developer fix the request.
- If the Terraform plan fails, report the error clearly — do not retry without developer input.
```

## Tools

| Tool | Purpose | Backed By |
|------|---------|-----------|
| `validate_request` | Check request against standards before writing Terraform | Lambda → reads `standards/` from `arc-ipa-tf` via GitHub API |
| `list_files` | List files and directories in `arc-ipa-tf` | Lambda → GitHub Contents API |
| `read_file` | Read any file in `arc-ipa-tf` | Lambda → GitHub Contents API |
| `write_file` | Create or update any file in `arc-ipa-tf` | Lambda → GitHub Contents API |
| `create_pull_request` | Commit changes to a branch and open a PR on `arc-ipa-tf` | Lambda → GitHub API |
| `comment_on_pr` | Post a comment on a PR (triggers Atlantis) | Lambda → GitHub Issues API |
| `notify_approver` | Notify PFND engineer for protected environments | Lambda → Jira API |

All GitHub operations target `arc-ipa-tf` and go through the GitHub App's installation token — the tools don't hold their own credentials.

### Tool: `validate_request`

**Inputs:**
- resource_type (e.g., `s3_bucket`, `k8s_namespace`)
- team
- purpose
- account (from session context)

**Behavior:**
1. Reads `standards/naming.json` from `arc-ipa-tf` → validates name pattern
2. Reads `standards/tagging.json` from `arc-ipa-tf` → confirms all required tags can be derived
3. Reads `standards/account-mapping.json` from `arc-ipa-tf` → confirms account exists, resolves workspace
4. Returns pass/fail with specific errors

### Tool: `list_files`

**Inputs:**
- path (relative to `arc-ipa-tf` repo root, empty string for root)
- ref (branch, defaults to main)

**Returns:** list of files and directories at the given path

Used by the agent to discover existing modules, explore repo structure, and understand what patterns are already in place before writing new Terraform.

### Tool: `read_file`

**Inputs:**
- path (relative to `arc-ipa-tf` repo root)

**Returns:** file contents as string

Used by the agent to read existing Terraform in `arc-ipa-tf` before modifying it, or to read standards files.

### Tool: `write_file`

**Inputs:**
- path (relative to `arc-ipa-tf` repo root)
- content (full file contents)

**Returns:** success/failure

Used to create new `.tf` files or modify existing ones in `arc-ipa-tf`.

### Tool: `create_pull_request`

**Inputs:**
- branch_name (auto-generated: `agent/{date}-{resource-type}-{team}-{purpose}`)
- files (list of path + content pairs already written via `write_file`)
- title
- description (structured: who requested, what resource, validation results)

**Returns:** PR number, PR URL

### Tool: `comment_on_pr`

**Inputs:**
- pr_number
- body (e.g., `atlantis plan -p s3-pf-sandbox-usw2`)

**Returns:** comment ID

Used to trigger Atlantis plan/apply after PR creation or after receiving webhook callback.

### Tool: `notify_approver`

**Inputs:**
- pr_url
- request_summary
- requester
- plan_output

**Behavior:** Creates a Jira ticket in the PFND project with the request details and a link to the PR.

## Session Lifecycle

```
1. CLI opens session → AgentCore creates runtime session
2. User sends message → agent processes, calls tools
3. Agent creates PR → calls add_async_task("waiting_for_atlantis")
4. Agent responds to user ("PR created, waiting for plan")
5. Session reports HealthyBusy → stays alive
6. GitHub App webhook fires → InvokeAgentRuntime on same session
7. Agent resumes with plan result → comments apply (or reports error)
8. GitHub App webhook fires again → apply result
9. Agent responds to user ("provisioned, here's your ARN")
10. Agent calls complete_async_task() → session goes Healthy
11. Session idles → auto-terminates after 15 min
```

## Async Model

AgentCore Runtime supports long-running agents natively:

- `add_async_task(task_name)` — marks the session as busy, prevents idle timeout
- `complete_async_task(task_id)` — marks done, session returns to idle
- `/ping` endpoint reports `HealthyBusy` while tasks are active

The same session can be re-invoked multiple times. Each invocation shares session memory, so the agent retains full context (which user, which PR, what state) across webhook callbacks.

**Reference:** [Handle asynchronous and long running agents with Amazon Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-long-run.html)

## Error Handling

| Scenario | Agent Behavior |
|----------|----------------|
| Validation fails | Returns specific error, suggests fix, does not create PR |
| Terraform plan fails | Reads Atlantis plan output from webhook, reports error to user with details |
| Apply fails | Reports error to user, PR stays open for manual intervention |
| GitHub API failure | Retries, then reports error to user |
| Session timeout while waiting | GitHub App can create a new session and resume from PR state |
