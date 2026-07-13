# AgentCore

## Overview

The Infrastructure Provisioning Agent runs on AWS Bedrock AgentCore. It receives developer requests via the CLI, validates them against standards, writes Terraform, and drives the GitOps flow through the GitHub App.

## Agent Configuration

| Setting | Value |
|---------|-------|
| Runtime | AgentCore Runtime (Bedrock) |
| Model | Claude Sonnet 4 (us.anthropic.claude-sonnet-4-6 via Bedrock cross-region inference) |
| Framework | Strands Agents SDK |
| Conversation Manager | SlidingWindowConversationManager (window_size=40, truncate results) |
| Invocation Limits | 30 turns, 1M tokens per turn |
| Prompt Caching | CacheConfig(strategy="auto"), tools cached by default |
| Session timeout (idle) | 15 min |
| Session timeout (busy) | None (stays alive while `HealthyBusy`) |

## System Prompt

The system prompt encodes:

- The agent's role: infrastructure provisioning for Arc'teryx dev teams
- Conversation behavior: ask only what it can't already know (team, purpose). Never ask about environment (comes from CLI context), security config (comes from standards).
- Available tools and when to use them
- Constraints: never provision without validation, never bypass standards, always create a PR

At boot time, the core markdown standards (`terraform.md`, `aws-infrastructure.md`) are appended to the system prompt so the agent always writes Terraform with those conventions in context.

Domain-specific references (from `standards/references/`) are listed by filename and description in the system prompt so the agent knows what's available to look up on demand. The `accounts.json` environments are also appended so the agent has full account context without needing to ask.

## Tools

See [tools.md](tools.md) for the full tool inventory and detailed specifications.

## Session Lifecycle

```
1. CLI opens WebSocket → runtime accepts connection
2. CLI sends init message (MCP tokens) → agent instance created with injected standards
3. Runtime sends init_ack → CLI enters interaction loop
4. User sends prompt → run_turn streams response back over WebSocket
5. Agent creates PR → calls wait_for_atlantis (registers async task, stores session in DynamoDB)
6. wait_for_atlantis sets stop_event_loop=True → agent turn ends, session reports HealthyBusy
7. Webhook Lambda fires → calls invoke_agent_runtime (HTTP entrypoint) with same session_id
8. Session affinity routes to same process → payload delivered via in-process asyncio.Queue
9. WebSocket handler receives from queue → sends async_complete frame to CLI → runs new turn
10. Agent resumes with plan/apply result → streams response to CLI
11. Session idles → auto-terminates after timeout
```

## Async Model

AgentCore Runtime supports long-running agents natively:

- `add_async_task(task_name)` — marks the session as busy, prevents idle timeout
- `complete_async_task(task_id)` — marks done, session returns to idle
- `/ping` endpoint reports `HealthyBusy` while tasks are active

The same session can be re-invoked multiple times. Each invocation shares session memory, so the agent retains full context (which user, which PR, what state) across webhook callbacks.

The in-process queue bridge (keyed by session_id) is what enables the HTTP entrypoint to deliver webhook payloads to the live WebSocket handler — AgentCore session affinity routes both to the same runtime instance.

**Reference:** [Handle asynchronous and long running agents with Amazon Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-long-run.html)

## Error Handling

| Scenario | Agent Behavior |
|----------|----------------|
| Validation fails | Returns specific error, suggests fix, does not create PR |
| Terraform plan fails | Reads Atlantis plan output from webhook, reports error to user with details |
| Apply fails | Reports error to user, PR stays open for manual intervention |
| GitHub API failure | Retries, then reports error to user |
| Session timeout while waiting | GitHub App can create a new session and resume from PR state |

## Telemetry

The agent exports OpenTelemetry traces to Datadog for full observability.

**Setup** (`telemetry.py`, imported first for side effects):
- Resolves Datadog API key from Secrets Manager (`DD_API_KEY_NAME` env var)
- Sets OTEL env vars: OTLP traces protocol (http/protobuf), endpoint (otlp.datadoghq.com), headers (dd-api-key + dd-otlp-source=llmobs)
- Configures `StrandsTelemetry().setup_otlp_exporter()`

**Per-turn tracing** (`turn.py`):
- Each turn opens a fresh root span detached from the WebSocket ASGI span
- Baggage (session.id, routing attributes) is preserved so Datadog groups traces into sessions
- Span attributes: service.name, repo, tags, session.id

**What you see in Datadog:**
- APM traces per turn (not per session) — each exports individually
- LLM Observability: token counts, latency, model ID (GenAI semantic conventions)
- Tool call spans nested under agent turns
- Error recording on failed turns

## Kill Switch

A CloudWatch alarm-backed cooldown mechanism (`kill_switch.py`). When the configured alarm (`KILL_SWITCH_ALARM` env var) is in ALARM state, all turns are refused with a "Token limit exceeded — cooldown active" message. This prevents runaway cost if the agent enters a loop.

The check runs at the start of every turn before any model invocation.
