# Developer Interface

## Overview

A Python CLI that connects developers to the infrastructure provisioning agent. It's a thin wrapper around the AgentCore SDK — handles auth, sets account context, and streams the conversation. The agent does the heavy lifting.

## Installation

```bash
pip install infra-agent
```

Distributed via internal PyPI. Single dependency: `bedrock-agentcore` SDK.

## Usage

```bash
# Specify account explicitly
infra-agent --account aws-pf-sandbox

# Use account from config
infra-agent
```

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--account` | Yes (or set in config) | Target AWS account alias (must exist in `account-mapping.json`) |
| `--verbose` | No | Show tool calls and agent reasoning |

## Configuration

Optional config file to avoid passing `--account` every time:

```yaml
# ~/.config/infra-agent/config.yaml
account: aws-pf-sandbox
```

Project-level config (`.infra-agent.yaml` in repo root) takes precedence over global config.

## Authentication

Uses the developer's existing AWS credentials — no separate auth system.

1. Developer has already run `aws sso login` (standard workflow)
2. CLI reads credentials from the environment / AWS profile
3. Caller identity (email, account) is derived from `sts:GetCallerIdentity`
4. Identity is passed to AgentCore as session context

No API keys, no OAuth, no extra tokens.

## How It Works

```
CLI starts
  ↓
1. Read --account (flag → project config → global config)
2. Validate account exists in account-mapping.json
3. Get caller identity from AWS STS
4. Open AgentCore session via InvokeAgentRuntime (streaming)
5. Pass session context: { account, user_email }
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

## Session Context

The CLI passes these to AgentCore at session start. The agent receives them as immutable facts.

| Field | Source | Example |
|-------|--------|---------|
| `user_email` | STS / SSO identity | `matthew.falcone@arcteryx.com` |
| `account` | `--account` flag or config | `aws-pf-sandbox` |

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
@click.option("--account", required=False)
@click.option("--verbose", is_flag=True)
def main(account, verbose):
    account = account or load_config_account()
    validate_account(account)

    user_email = get_caller_identity()

    client = BedrockAgentCoreClient()
    session = client.create_session(
        agent_id=AGENT_ID,
        context={"account": account, "user_email": user_email}
    )

    click.echo(f"Connected | Account: {account} | User: {user_email}")
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
$ infra-agent --account aws-pf-sandbox

Connected | Account: aws-pf-sandbox | User: matthew.falcone@arcteryx.com
Type your request (Ctrl+C to exit)

> I need an S3 bucket for raw event ingestion

I can help with that. Which team are you on?

> ecomm

✓ Validated. Here's what I'll provision:

  Bucket: arcteryx-ecomm-sandbox-raw-event-ingestion
  Account: aws-pf-sandbox
  Workspace: pf-sandbox-usw2
  Tags: team=ecomm, environment=sandbox, managed-by=agentcore, ...

  Want me to create the PR?

> yes

Done. PR #247 created: github.com/arcteryx-platform/infra-provisioning/pull/247
Waiting for Atlantis plan...

✓ Plan succeeded: 1 to add, 0 to change, 0 to destroy.
Applying...

✓ Applied. Your bucket is provisioned.
  ARN: arn:aws:s3:::arcteryx-ecomm-sandbox-raw-event-ingestion
  PR: #247 (merged)
```
