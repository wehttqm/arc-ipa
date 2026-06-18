# Developer Interface

## Overview

A Python CLI that connects developers to the infrastructure provisioning agent. It's a thin wrapper around the AgentCore SDK — handles auth, sets environment context, and streams the conversation. The agent does the heavy lifting.

## Installation

```bash
pip install infra-agent
```

Distributed via internal PyPI. Single dependency: `bedrock-agentcore` SDK.

## Usage

```bash
infra-agent
```

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--verbose` | No | Show tool calls and agent reasoning |

## Configuration

No configuration required. The agent collects environment, team, and purpose during the conversation.

## Authentication

Uses the developer's existing AWS credentials — no separate auth system.

1. Developer has already run `aws sso login` (standard workflow)
2. CLI reads credentials from the environment / AWS profile
3. Caller identity (email) is derived from `sts:GetCallerIdentity`
4. Identity is passed to AgentCore for audit trail

No API keys, no OAuth, no extra tokens.

## How It Works

```
CLI starts
  ↓
1. Read --env (flag → project config → global config)
2. Validate environment is valid (dev/staging/prod)
3. Get caller identity from AWS STS
4. Open AgentCore session via WebSocket
5. Pass user identity: { user_email }
  ↓
Conversation loop:
  - User types → send to agent session
  - Agent responds → stream to terminal
  - Agent goes async (waiting for Atlantis) → print status, keep session open
  - Webhook callback triggers agent → new response streams to terminal
  ↓
Session ends on:
  - User types "exit" / Ctrl+C
  - Agent completes task and session idles out (15 min)
```

## User Identity

The CLI passes user identity at session start for audit trail and Jira attribution.

| Field | Source | Example |
|-------|--------|---------|
| `user_email` | STS / SSO identity | `matthew.falcone@arcteryx.com` |

The target environment (dev/staging/prod) is collected by the agent during the conversation, not set at session level. This allows a single session to handle multiple environments.

## Async Behavior

When the agent creates a PR and waits for Atlantis:

1. CLI prints: "PR created. Waiting for Atlantis plan..."
2. Terminal stays open, session stays alive (`HealthyBusy`)
3. When webhook fires and agent resumes, response streams to the terminal
4. If the user disconnects (Ctrl+C), the agent still completes — result is visible on the PR

The CLI is not required to stay open for the agent to finish. The GitHub App + Atlantis flow completes independently.

## Implementation

```python
import click
from bedrock_agentcore.runtime import BedrockAgentCoreClient

@click.command()
@click.option("--verbose", is_flag=True)
def main(verbose):
    user_email = get_caller_identity()

    client = BedrockAgentCoreClient()
    session = client.create_session(
        agent_id=AGENT_ID,
        context={"user_email": user_email}
    )

    click.echo(f"Connected | User: {user_email}")
    click.echo("Type your request (Ctrl+C to exit)\n")

    while True:
        user_input = click.prompt(">", prompt_suffix=" ")
        for chunk in session.invoke_stream(prompt=user_input):
            click.echo(chunk, nl=False)
        click.echo()
```

This is illustrative — exact SDK methods depend on AgentCore API shape. But the point is it's ~50 lines of real code.

## What the CLI Does NOT Do

- No Terraform execution
- No direct AWS resource creation
- No state management
- No standards validation (agent does this)
- No GitHub operations (GitHub App does this)

It's a terminal into the agent. That's it.

## Example Session

```
$ infra-agent

Connected | User: matthew.falcone@arcteryx.com
Type your request (Ctrl+C to exit)

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

> yes

Done. Your bucket is provisioned.
  ARN: arn:aws:s3:::arcteryx-ecomm-dev-raw-event-ingestion
```
