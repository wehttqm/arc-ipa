# Developer Interface

## Overview

A Python CLI that connects developers to the infrastructure provisioning agent over a WebSocket connection to AgentCore. It uses `rich` for live markdown rendering in the terminal and `prompt_toolkit` for interactive input (including arrow-key selectors for confirmation prompts). The agent does the heavy lifting — the CLI handles auth, token management, streaming display, and session lifecycle.

## Installation

The CLI lives in `arc-ipa/cli/` and is not distributed via PyPI. Install dependencies from the requirements file:

```bash
cd arc-ipa/cli
pip install -r requirements.txt
```

### Dependencies

| Package | Purpose |
|---------|---------|
| `bedrock-agentcore` | AgentCore runtime client (WebSocket URL + auth headers) |
| `websockets` | WebSocket connection to AgentCore |
| `rich` | Live markdown rendering, panels, and terminal formatting |
| `prompt_toolkit` | Interactive input and arrow-key yes/no selector |
| `psutil` | System stats displayed in the startup banner |
| `mcp_auth` (local) | MCP OAuth token resolution for Atlassian integration |

## Prerequisites

### 1. Configure AWS SSO

The CLI authenticates to AgentCore using AWS credentials from the `pf-sandbox` account (`529088297181`). Set up an SSO profile if you haven't already:

```bash
aws configure sso
```

When prompted:
| Field | Value |
|-------|-------|
| SSO session name | `arcteryx` (or your preferred name) |
| SSO start URL | Your organization's AWS SSO start URL |
| SSO region | `us-west-2` |
| Account | `529088297181` (pf-sandbox) |
| Role | Select the role your team has been granted |
| CLI default region | `us-west-2` |
| CLI profile name | e.g. `pf-sandbox` |

Then log in:

```bash
aws sso login --profile pf-sandbox
```

### 2. Set Environment Variables

The CLI requires the following environment variable:

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENT_RUNTIME_ARN` | **Yes** | The ARN of the AgentCore runtime to connect to |
| `AWS_PROFILE` | Recommended | The SSO profile name (if not using default) |

Set them in your shell (or add to `.zshrc` / `.bashrc`):

```bash
export AGENT_RUNTIME_ARN="arn:aws:bedrock-agentcore:..."
export AWS_PROFILE="pf-sandbox"
```

The runtime ARN is an output of the `modules/agentcore/runtime` Terraform module. If the runtime is redeployed, the ARN may change — check `terraform output agent_runtime_arn` in that module.

### 3. Verify Access

Confirm your credentials work before launching the CLI:

```bash
aws sts get-caller-identity --profile pf-sandbox
```

You should see your assumed role ARN in account `529088297181`. If this fails, re-run `aws sso login`.

## Usage

```bash
python cli.py
```

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--resume SESSION_ID` | No | Resume a previous session by its ID |

## Configuration

See [Prerequisites](#prerequisites) above. The CLI requires a valid AWS SSO session and the `AGENT_RUNTIME_ARN` environment variable. No additional config files are needed — the agent collects environment, team, and purpose during the conversation.

## Authentication

The CLI uses two authentication mechanisms:

### AWS Credentials (AgentCore Connection)

1. Developer has already run `aws sso login` (standard workflow)
2. CLI reads credentials from the environment / AWS profile
3. `AgentCoreRuntimeClient` uses these to generate a signed WebSocket URL + auth headers
4. Caller identity (from STS) is passed implicitly through the connection headers

### MCP OAuth Tokens (Atlassian Integration)

1. At startup, CLI calls `resolve_provider_tokens()` from the `mcp_auth` package
2. This checks for cached tokens first; if expired or missing, launches interactive browser-based OAuth
3. Resolved tokens are sent to the agent in the WebSocket init message
4. Before each user prompt, tokens are silently refreshed via `provider.get_token_silent()`
5. Refreshed tokens are sent as `{"token_refresh": {key: token}}` messages over the WebSocket

## How It Works

```
CLI starts
  ↓
1. Parse args (--resume)
2. Generate session ID (or reuse from --resume)
3. Get WebSocket URL + auth headers from AgentCoreRuntimeClient
4. Display banner (ASCII art, session info, system stats)
5. Resolve MCP provider tokens (cached or interactive OAuth)
6. Open WebSocket connection (with SSL)
7. Send init message (MCP tokens) → wait for init_ack
  ↓
Interaction loop (races user input vs server frames):
  - User types → send as {"prompt": text} → render streamed response
  - Server pushes async_complete → render 'resuming…' banner → render turn
  - Agent asks "Ready to provision?" → present arrow-key Yes/No selector
  - Token refresh happens silently before each send
  ↓
Session ends on:
  - User types exit/quit or Ctrl+C/Ctrl+D
  - WebSocket closes
  - Prints resume command for later
```

## Session Resume

Sessions can be resumed using the `--resume` flag with the session ID printed at exit:

```bash
python cli.py --resume abc123def4560
```

AgentCore routes the resumed connection to the same runtime instance (if still alive) preserving full conversation context. This is useful when:
- The CLI was closed during an Atlantis wait
- A long-running operation needs to be checked on later
- Network interruption disconnected the session

## User Identity

User identity is derived from AWS credentials (STS caller identity) and passed implicitly through the AgentCore WebSocket connection headers. No explicit `user_email` field is sent — AgentCore extracts the caller identity from the signed request.

## Async Behavior

When the agent creates a PR and waits for Atlantis:

1. CLI prints: "PR created. Waiting for Atlantis plan..."
2. Terminal stays open, session stays alive (`HealthyBusy`)
3. When webhook fires and agent resumes, the server pushes an `async_complete` frame
4. CLI renders a "resuming…" banner and streams the new turn
5. If the user disconnects (Ctrl+C), the agent still completes — result is visible on the PR

The CLI is not required to stay open for the agent to finish. The GitHub App + Atlantis flow completes independently. Use `--resume` to reconnect later.

## Implementation

The CLI is ~450 lines of Python. Key architectural components:

| Component | Responsibility |
|-----------|---------------|
| `TurnRenderer` | Handles live markdown rendering via `rich`, tool call display (spinner + name), and turn lifecycle (start/stream/end) |
| `_interaction_loop` | Main loop that races `prompt_async` (user input) against `frame_q` (server-pushed frames) for bidirectional communication |
| `_drive_turn` | Renders a complete agent turn and handles the confirmation flow if triggered |
| `needs_confirmation` | Regex-based detection of "ready to provision?" in agent output to trigger the yes/no selector |
| `prompt_yes_no` | Arrow-key navigable yes/no selector built with `prompt_toolkit`, used for provisioning confirmation |

The WebSocket protocol uses JSON frames:
- **Outbound:** `{"prompt": text}`, `{"token_refresh": {key: token}}`, init message with MCP tokens
- **Inbound:** Streamed turn chunks, `init_ack`, `async_complete`, tool call notifications

## What the CLI Does NOT Do

- No Terraform execution
- No direct AWS resource creation
- No state management
- No standards validation (agent does this)
- No GitHub operations (GitHub App does this)

It's a terminal into the agent. That's it.

## Example Session

```
$ python cli.py

 ╔══════════════════════════════════════╗
 ║   Infrastructure Provisioning Agent  ║
 ╚══════════════════════════════════════╝
 Session: abc123def4560
 System: macOS | 16 GB RAM | 8 cores

> I need an S3 bucket for raw event ingestion

I can help with that. A few questions:
- Which team?
- Which environment (dev, staging, or prod)?

> ecomm, dev

I'll provision this:

  Bucket: arcteryx-ecomm-dev-raw-event-ingestion
  Environment: dev
  Tags: team=ecomm, environment=dev, managed-by=terraform, ...

  Ready to provision?

  → Yes
    No

Done. Your bucket is provisioned.
  ARN: arn:aws:s3:::arcteryx-ecomm-dev-raw-event-ingestion

$ # Later, to resume:
$ python cli.py --resume abc123def4560
```
