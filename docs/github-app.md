# GitHub App

## Overview

A GitHub App provides the agent's identity on GitHub and acts as the event bridge between Atlantis and AgentCore. It is installed on `wehttqm/arc-ipa-tf` and has two roles:

1. **Outbound:** All agent GitHub operations (branches, commits, PRs, comments) on `wehttqm/arc-ipa-tf` are performed as the app
2. **Inbound:** Receives webhooks when Atlantis comments on `wehttqm/arc-ipa-tf` PRs, and re-invokes the agent session with the result

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
  1. Verify webhook signature (X-Hub-Signature-256) using secret from Secrets Manager
  2. Respond to ping events (return 200 'pong')
  3. Check: action == 'created'? If not, ignore
  4. Check: is comment author's login contain 'atlantis'? If not, ignore
  5. Extract repo_full_name and pr_number
  6. Build composite key: "{repo_full_name}#{pr_number}"
  7. Look up session in DynamoDB by composite key
  8. If no session found → return 200 (no one waiting)
  9. Detect event_type from comment body ('apply' if contains 'Ran Apply' or 'apply complete', else 'plan')
  10. Call bedrock-agentcore:InvokeAgentRuntime with:
      - agentRuntimeArn from env
      - runtimeSessionId from DynamoDB record
      - payload: {"webhook": {repo_full_name, pr_number, comment_body, event_type}}
  11. Delete the DynamoDB record (one-shot delivery)
```

## Outbound Flow (Agent → GitHub)

All agent tools (`read_file`, `write_file`, `create_pull_request`, `comment_on_pr`) target `wehttqm/arc-ipa-tf` and authenticate as the GitHub App via the `github_app.py` module in the agent process:

```
Agent tool invoked (e.g. read_file, create_pull_request)
         ↓
github_app.py:
  1. Load GitHub App credentials from Secrets Manager ('arc-ipa/github-app')
  2. Generate JWT (RS256, 10-min expiry) using app_id + private_key
  3. Exchange JWT for installation access token (cached, refreshed when <60s from expiry)
  4. Call GitHub API with installation token
  5. Return result to tool
```

The agent authenticates directly — no intermediate Lambda for outbound calls.

## Session Tracking

The agent uses a DynamoDB table to map PRs to AgentCore sessions:

- **Table:** `SESSIONS_TABLE` env var (default: `infra-agent-webhook-sessions`)
- **Key:** `repo_pr` (string) — format `{owner}/{repo}#{pr_number}` (e.g. `wehttqm/arc-ipa-tf#42`)
- **Attributes:** `session_id`, `task_id`, `event_type`, `ttl` (24h)
- **Write:** The `wait_for_atlantis` tool writes the record when the agent starts waiting for Atlantis
- **Read + Delete:** The webhook Lambda reads the record to find the session, then deletes it after delivering the result (one-shot delivery)

## Infrastructure

| Component | Implementation |
|-----------|----------------|
| Webhook receiver | Lambda + API Gateway (HTTPS) |
| Session mapping | DynamoDB table (repo_pr → session_id, TTL 24h) |
| App credentials (GitHub) | Secrets Manager (`arc-ipa/github-app`: app_id, private_key, installation_id) |
| Webhook secret | Secrets Manager (same or separate secret, referenced by `SECRET_NAME` env var) |

## App Registration

1. Create the app in the GitHub org settings
2. Set homepage URL, webhook URL (API Gateway endpoint)
3. Generate and store private key in Secrets Manager
4. Install the app on `wehttqm/arc-ipa-tf`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Webhook signature invalid | Reject (401) |
| Comment is not from Atlantis | Ignore (200) |
| No session found for PR | Return 200, log (no one was waiting) |
| AgentCore session expired | The webhook Lambda invokes AgentCore; if the session is gone, AgentCore handles it |
| GitHub API rate limit | Retry with backoff |
