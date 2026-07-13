# Implementation Plan: Teams Bot + Identity

**Author:** Matthew Falcone  
**Date:** June 26, 2026  
**Status:** Draft

---

## Overview

Extend the Infrastructure Provisioning Agent to support a Microsoft Teams bot interface alongside the existing CLI and integrate user identity. The agent code remains largely unchanged — Teams access is achieved through a thin adapter service that calls the existing HTTP entrypoint.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AgentCore Runtime                         │
│                                                                  │
│  ┌──────────────┐     ┌──────────────────┐                      │
│  │  WebSocket   │     │  HTTP Entrypoint  │                      │
│  │  (CLI path)  │     │  (Teams + Webhook)│                      │
│  └──────┬───────┘     └────────┬──────────┘                      │
│         │                      │                                  │
│         └──────────┬───────────┘                                  │
│                    ▼                                              │
│             Agent (Strands SDK)                                   │
│             ├── Tools (GitHub, Atlantis, Jira MCP)               │
│             ├── Standards                                         │
└─────────────────────────────────────────────────────────────────┘
        ▲ WebSocket              ▲ HTTP invoke
        │                        │
   ┌────┴─────┐         ┌───────┴────────┐
   │  CLI     │         │  Teams Bot     │
   │  (user   │         │  (Azure Bot    │
   │  OAuth)  │         │  Framework)    │
   └──────────┘         └───────┬────────┘
                                │
                        ┌───────┴────────┐
                        │  Microsoft     │
                        │  Teams         │
                        └────────────────┘
```

---

## Phase 1: Agent HTTP Entrypoint (Prompt Support)

**Goal:** Allow the agent to be invoked synchronously via HTTP with a prompt, enabling non-WebSocket clients (Teams bot).

### 1.1 Extend the HTTP entrypoint

**File:** `infra-agent/agent.py`

Add a `"prompt"` path to the existing `@app.entrypoint`:

```python
@app.entrypoint
async def invoke(payload, context):
    if not isinstance(payload, dict):
        return {"error": "Invalid payload"}

    # Existing: webhook resume (Atlantis)
    if "webhook" in payload:
        # ... unchanged ...

    # New: synchronous prompt (Teams bot or any HTTP caller)
    if "prompt" in payload:
        init_data = payload.get("init", {})
        if "atlassian_token" not in init_data:
            token = _get_service_mcp_token()
            if token:
                init_data["atlassian_token"] = token
        agent, _ = _create_agent(init_data)
        result = agent(payload["prompt"], limits=INVOCATION_LIMITS)
        return {"response": str(result)}

    return {"error": "Unsupported payload"}
```

### 1.2 Service account token for MCP

**File:** `infra-agent/agent.py`

```python
def _get_service_mcp_token() -> str | None:
    try:
        secret = boto3.client("secretsmanager").get_secret_value(
            SecretId="arc-ipa/atlassian-service-account"
        )
        return json.loads(secret["SecretString"])["token"]
    except Exception:
        return None
```

Store an Atlassian API token (or OAuth client_credentials token) in Secrets Manager at `arc-ipa/atlassian-service-account`.

### 1.3 Session continuity for HTTP callers

The HTTP entrypoint receives `context.session_id` from the caller (Teams bot passes `{user_aad_oid}-{conversation_id}`). AgentCore routes repeat invocations with the same session ID to the same runtime instance, preserving conversation state.

---

## Phase 2: Identity

**Goal:** Know which user is making each request for audit, rate limiting, and per-user session binding.

### 2.1 Teams path — user identity from Azure AD

The Teams Bot Framework SDK validates the Microsoft-signed JWT on every incoming activity. The bot extracts:
- `activity.from_property.aad_object_id` — Azure AD user OID
- `activity.from_property.name` — display name

Pass this to AgentCore:

```python
client.invoke_agent_runtime(
    agentRuntimeArn=RUNTIME_ARN,
    runtimeSessionId=f"{user_aad_oid}-{convo_id}",
    runtimeUserId=user_aad_oid,  # X-Amzn-Bedrock-AgentCore-Runtime-User-Id
    payload=json.dumps({"prompt": text}),
)
```

### 2.2 CLI path — user identity from IAM

Add user ID derivation from the STS caller identity:

```python
# cli.py — at connection time
sts = boto3.client("sts")
user_id = sts.get_caller_identity()["UserId"]
ws_url, headers = client.generate_ws_connection(
    runtime_arn=arn,
    session_id=session_id,
    user_id=user_id,
)
```

### 2.3 IAM — allow `InvokeAgentRuntimeForUser`

**File:** `arc-ipa/modules/agentcore/iam/main.tf` (or the invoker's IAM policy)

The Teams bot's execution role needs:

```json
{
  "Effect": "Allow",
  "Action": [
    "bedrock-agentcore:InvokeAgentRuntime",
    "bedrock-agentcore:InvokeAgentRuntimeForUser"
  ],
  "Resource": "<runtime ARN>"
}
```

### 2.4 Agent-side: user context available

The agent receives `context.user_id` on both WebSocket and HTTP paths. This can be logged, included in Jira tickets, and used for audit trails in CloudWatch traces.

---

## Phase 3: Teams Bot Service

**Goal:** A lightweight service that bridges Microsoft Teams and the AgentCore HTTP entrypoint.

### 3.1 Bot registration

- Register via `@microsoft/teams.cli` CLI tool (`teams app create`)
- Requires Entra ID app registration permissions (see PFND-6041)
- Configure messaging endpoint URL (points to the bot's webhook)

### 3.2 Bot implementation

**Runtime:** Lambda behind API Gateway, or ECS task  
**Framework:** Teams SDK v2 (`microsoft-teams-apps` package, GA for Python)

> **Note:** `botbuilder-python` was archived in Dec 2025 and is no longer maintained. Teams SDK v2 is the recommended replacement. It includes a built-in HTTP server (no aiohttp needed).

```python
from microsoft_teams.api import MessageActivity
from microsoft_teams.apps import ActivityContext, App
import boto3, json, os

RUNTIME_ARN = os.environ["AGENT_RUNTIME_ARN"]
ac_client = boto3.client("bedrock-agentcore", region_name="us-west-2")

app = App()

@app.on_message
async def on_message(context: ActivityContext, activity: MessageActivity):
    user_id = activity.from_property.aad_object_id
    convo_id = activity.conversation.id
    text = activity.text

    # Send typing indicator
    await context.send_typing()

    response = ac_client.invoke_agent_runtime(
        agentRuntimeArn=RUNTIME_ARN,
        runtimeSessionId=f"{user_id}-{convo_id}",
        runtimeUserId=user_id,
        payload=json.dumps({"prompt": text}),
    )

    reply = json.loads(response["body"])["response"]
    await context.send_message(reply)
```

### 3.3 Long-running operations (Atlantis wait)

When the agent calls `wait_for_atlantis`, it blocks the HTTP response. Options:

**Option A: Timeout + proactive message**
- Bot sets a 30s timeout on the invoke call
- If it times out, send "⏳ Provisioning in progress — I'll message you when it's done"
- When the Atlantis webhook resumes the session, the agent calls a `notify_teams` tool that posts a proactive message back to the conversation

**Option B: Fire-and-forget pattern**
- Bot sends prompt, immediately replies "Working on it…"
- Agent runs async, posts result via Teams proactive messaging API when complete

Recommended: **Option A** — keeps the simple request/response for fast operations, only goes async for Atlantis waits.

### 3.4 `notify_teams` tool (new agent tool)

```python
@tool
def notify_teams(conversation_id: str, message: str) -> str:
    """Post a proactive message to a Teams conversation."""
    # Uses Microsoft Bot Framework's proactive messaging API
    # Requires stored conversation reference from the original activity
    ...
```

### 3.5 Infrastructure

| Resource | Purpose |
|----------|---------|
| Lambda + API Gateway (or ECS) | Bot webhook endpoint |
| Secrets Manager | Microsoft App ID + Secret |
| DynamoDB table | Conversation references (for proactive messaging) |
| IAM role | `bedrock-agentcore:InvokeAgentRuntime*` on the runtime ARN |

---

## Phase Summary

| Phase | Scope | Agent code changes | New infrastructure |
|-------|-------|-------------------|-------------------|
| 1 — HTTP entrypoint | Accept prompts via HTTP | ~15 lines in `agent.py` | Secrets Manager entry (Atlassian service account) |
| 2 — Identity | User ID on all paths | 0 lines (context already available) | IAM policy update |
| 3 — Teams bot | New adapter service | 0 lines (optional `notify_teams` tool) | Lambda/ECS, API GW, Azure Bot registration |

---

## What stays unchanged

- WebSocket handler (CLI)
- All existing tools (GitHub, Atlantis, standards, MCP)
- System prompt and standards loading
- Kill switch / monitoring
- Webhook handler Lambda (Atlantis → agent resume)
- `arc-ipa-tf` repo (Terraform the agent writes)

---

## Open Questions

1. **Teams tenant restriction** — Should the bot be restricted to the Arc'teryx Azure AD tenant only, or allow partner tenants?
2. **Approval flow in Teams** — For production provisioning (US-5), should the approval notification go to a Teams channel instead of Slack/Jira?
3. **Conversation history** — Should the Teams bot support `--resume` style session continuity across multiple conversations, or treat each Teams thread as ephemeral?
4. **Rate limiting** — Per-user invocation limits enforced at the bot level, agent level, or both?
