# Agent Tools

All tools are defined in `infra-agent/tools/`, one function per file, decorated with `@tool` from the Strands SDK. All GitHub operations target `arc-ipa-tf` and authenticate via the GitHub App installation token.

For instructions on adding new tools, see [adding-tools.md](adding-tools.md).

## Tool Inventory

| Tool | Purpose | Backed By |
|------|---------|-----------|
| `validate_request` | Check request against standards before writing Terraform | GitHub API → reads `standards/` from `arc-ipa-tf` |
| `list_files` | List files and directories in `arc-ipa-tf` | GitHub Contents API |
| `read_file` | Read any file in `arc-ipa-tf` | GitHub Contents API |
| `write_file` | Create or update any file in `arc-ipa-tf` | GitHub Contents API |
| `create_pull_request` | Open a PR on `arc-ipa-tf` | GitHub API |
| `merge_pull_request` | Merge a PR (squash/merge/rebase) | GitHub API |
| `update_pull_request` | Change PR state (open/closed) | GitHub API |
| `comment_on_pr` | Post a comment on a PR (triggers Atlantis) | GitHub Issues API |
| `read_pr_comments` | Read comments on a PR | GitHub Issues API |
| `list_pull_requests` | List PRs with optional filters | GitHub API |
| `wait_for_atlantis` | Wait for Atlantis plan/apply to complete | Async task + webhook |
| `get_mcp_tools` | Load MCP-based integrations (Jira) | MCP over Streamable HTTP |

## Tool Details

### `validate_request`

**Inputs:**
- `resource_type` — e.g. `s3_bucket`, `k8s_namespace`
- `team`
- `purpose`
- `account` — from session context

**Behavior:**
1. Reads `standards/naming.json` → validates name pattern
2. Reads `standards/tagging.json` → confirms all required tags can be derived
3. Reads `standards/account-mapping.json` → confirms account exists, resolves workspace
4. Returns pass/fail with specific errors

### `list_files`

**Inputs:**
- `path` — relative to repo root (empty string for root)
- `ref` — branch (defaults to main)

**Returns:** List of files and directories at the given path.

### `read_file`

**Inputs:**
- `path` — relative to repo root
- `ref` — branch (defaults to main)

**Returns:** File contents as string.

### `write_file`

**Inputs:**
- `path` — relative to repo root
- `content` — full file contents
- `branch` — target branch (created from main if it doesn't exist)
- `message` — commit message

**Returns:** Confirmation with commit SHA.

### `create_pull_request`

**Inputs:**
- `branch` — source branch
- `title`
- `body` — PR description

**Returns:** PR number and URL.

### `merge_pull_request`

**Inputs:**
- `pr_number` — the PR to merge
- `merge_method` — `squash` (default), `merge`, or `rebase`

**Returns:** Confirmation with merge commit SHA.

### `update_pull_request`

**Inputs:**
- `pr_number` — the PR to update
- `state` — `open` or `closed`

**Returns:** Confirmation of new state.

### `comment_on_pr`

**Inputs:**
- `pr_number`
- `body` — comment text (e.g. `atlantis plan -p s3-buckets-pf-sandbox-usw2`)

**Returns:** Comment ID.

### `read_pr_comments`

**Inputs:**
- `pr_number`

**Returns:** List of comments on the PR.

### `list_pull_requests`

**Inputs:**
- `state` — `open`, `closed`, or `all` (defaults to open)

**Returns:** List of PRs matching the filter.

### `wait_for_atlantis`

**Inputs:**
- `pr_number` — the PR to watch
- `event_type` — `plan` or `apply`

**Behavior:** Registers an async task (marks session as `HealthyBusy`) and waits for the GitHub App webhook to deliver the Atlantis result. The webhook Lambda re-invokes the same session via AgentCore session affinity.

### MCP Tools

External integrations (currently Jira) connect via MCP (Model Context Protocol). Configuration is stored in AWS Secrets Manager (`arc-ipa/mcp`). See `tools/mcp.py` for the client setup.
