# GitHub App

## Overview

A GitHub App provides the agent's identity on GitHub and acts as the event bridge between Atlantis and AgentCore. It is installed on `arc-ipa-tf` and has two roles:

1. **Outbound:** All agent GitHub operations (branches, commits, PRs, comments) on `arc-ipa-tf` are performed as the app
2. **Inbound:** Receives webhooks when Atlantis comments on `arc-ipa-tf` PRs, and re-invokes the agent session with the result

## Why a GitHub App

- **Clean identity** — PRs and comments show as authored by the app (e.g., "infra-agent[bot]"), not a personal token
- **Scoped permissions** — fine-grained access to `arc-ipa-tf`, not org-wide
- **Webhooks built-in** — the app receives events without needing separate webhook config
- **No shared secrets** — authenticates via private key + JWT, not a long-lived PAT

## Permissions Required

| Permission | Access | Used For |
|------------|--------|----------|
| Contents | Read & Write | Read files, create branches, commit files |
| Pull requests | Read & Write | Open PRs, read PR details |
| Issues | Read & Write | Post comments on PRs (Atlantis commands) |
| Metadata | Read | Required baseline |

## Webhook Events

The app subscribes to:

| Event | Filter | Purpose |
|-------|--------|---------|
| `issue_comment` | Created | Detect Atlantis plan/apply output comments |

## Inbound Flow (Webhook → AgentCore)

```
GitHub fires issue_comment event
         ↓
API Gateway receives payload
         ↓
Lambda handler:
  1. Verify webhook signature (X-Hub-Signature-256)
  2. Check: is the comment author the Atlantis bot?
  3. If no → ignore
  4. Parse Atlantis comment for status:
     - "Ran Plan for project X" → plan output
     - "Plan Failed" → plan error
     - "Applied successfully" → apply success
     - "Apply Failed" → apply error
  5. Look up the AgentCore session ID (stored in PR description or labels)
  6. Call InvokeAgentRuntime with:
     - session_id
     - payload: { event: "atlantis_result", status: "plan_succeeded", output: "..." }
```

## Outbound Flow (Agent → GitHub)

All agent tools (`read_file`, `write_file`, `create_pull_request`, `comment_on_pr`) target `arc-ipa-tf` and authenticate as the GitHub App:

```
Agent tool invoked
         ↓
Lambda handler:
  1. Generate JWT from app private key
  2. Exchange JWT for installation access token
  3. Call GitHub API with installation token
  4. Return result to agent
```

Installation tokens expire after 1 hour and are scoped to the repos where the app is installed.

## Session Tracking

The agent needs to know which AgentCore session corresponds to which PR. Options:

1. **PR description** — embed session ID in the PR body (hidden in an HTML comment)
2. **PR label** — add a label like `agentcore-session:abc123`
3. **External mapping** — DynamoDB table mapping PR number → session ID

Recommendation: option 1 (PR description) is simplest and requires no extra infra.

## Infrastructure

| Component | Implementation |
|-----------|---------------|
| Webhook receiver | Lambda + API Gateway (HTTPS endpoint) |
| App credentials | Private key stored in Secrets Manager |
| Deployment | Part of the agent's Terraform in `arc-ipa` |

## App Registration

1. Create the app in the Arc'teryx GitHub org settings
2. Set homepage URL, webhook URL (API Gateway endpoint)
3. Generate and store private key in Secrets Manager
4. Install the app on `arc-ipa-tf`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Webhook signature invalid | Reject (401) |
| Comment is not from Atlantis | Ignore (200) |
| Session ID not found for PR | Log warning, skip |
| AgentCore session expired | Create new session, reconstruct context from PR description (contains account, user, resource details, session ID) |
| GitHub API rate limit | Retry with backoff |
