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
- Conversation behavior: ask only what it can't already know (team, purpose). Never ask about environment (comes from CLI context), security config (comes from standards).
- Available tools and when to use them
- Constraints: never provision without validation, never bypass standards, always create a PR

At boot time, the core markdown standards (`terraform.md`, `aws-infrastructure.md`) are appended to the system prompt so the agent always writes Terraform with those conventions in context.

## Tools

See [tools.md](tools.md) for the full tool inventory and detailed specifications.

See [adding-tools.md](adding-tools.md) for instructions on adding new tools.

## Session Lifecycle

```
1. CLI opens WebSocket → agent instance created with injected standards
2. User sends message → agent processes, calls tools
3. Agent creates PR → calls add_async_task("waiting_for_atlantis")
4. Agent responds to user ("PR created, waiting for plan")
5. Session reports HealthyBusy → stays alive
6. GitHub App webhook fires → delivered to same session via queue
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
