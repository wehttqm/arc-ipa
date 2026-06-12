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

See [tools.md](tools.md) for the full tool inventory and detailed specifications.

See [adding-tools.md](adding-tools.md) for instructions on adding new tools.

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
