# Agent Tools

All tools are defined in `infra-agent/tools/`, one function per file, decorated with `@tool` from the Strands SDK. All GitHub operations target `arc-ipa-tf` and authenticate via the GitHub App installation token.

## Tool Inventory

| Tool | Purpose | Backed By |
|------|---------|-----------|
| `validate_request` | Check request against standards before writing Terraform | GitHub API → reads `standards/` from `arc-ipa-tf` |
| `lookup_standard` | Load a reference standard on demand (kubernetes, debugging, planning) | GitHub API → reads `standards/references/` from `arc-ipa-tf` |
| `list_files` | List files and directories in `arc-ipa-tf` | GitHub Contents API |
| `read_file` | Read any file in `arc-ipa-tf` | GitHub Contents API |
| `write_file` | Create or update any file in `arc-ipa-tf` | GitHub Contents API |
| `create_pull_request` | Open a PR on `arc-ipa-tf` | GitHub API |
| `merge_pull_request` | Merge a PR (squash/merge/rebase) | GitHub API |
| `update_pull_request` | Change PR state (open/closed) | GitHub API |
| `comment_on_pr` | Post a comment on a PR (triggers Atlantis) | GitHub Issues API |
| `read_pr_comments` | Read comments on a PR | GitHub Issues API |
| `list_pull_requests` | List PRs with optional filters | GitHub API |
| `list_commits` | View commit history, optionally filtered by file | GitHub API |
| `wait_for_atlantis` | Wait for Atlantis plan/apply to complete | Async task + webhook |
| MCP tools | External integrations (Atlassian/Jira) | MCP over Streamable HTTP |

## Tool Details

### `validate_request`

**Inputs:**
- `resource_type` — e.g. `s3_bucket`, `lambda`, `k8s_namespace`
- `team`
- `purpose`
- `environment` — target environment (`dev`, `staging`, `prod`) — developer provides

**Behavior:**
1. Validates environment is known
2. Reads `standards/naming.json` → generates name from pattern, validates length
3. Reads `standards/tagging.json` → confirms all required tags can be resolved
4. Returns pass/fail with resolved name and approval requirement

### `lookup_standard`

**Inputs:**
- `name` (str, optional) — reference filename (e.g. `kubernetes.md`). Empty to list available.

**Returns:** If no name given, lists available references in `standards/references/`. If name given, returns the file content with frontmatter stripped.

**Note:** Core standards (`terraform.md`, `aws-infrastructure.md`) are in `prompts/` and injected into the system prompt at boot — this tool is ONLY for on-demand references.

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
- `description` — PR description
- `base` (str) — target branch (defaults to `main`)

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
- `body` — comment text (e.g. `atlantis apply -p s3-buckets-pf-sandbox-usw2`)

**Returns:** Comment ID.

### `read_pr_comments`

**Inputs:**
- `pr_number`

**Returns:** List of comments on the PR.

### `list_pull_requests`

**Inputs:**
- `state` (str) — `open`, `closed`, or `all` (default: open)
- `search` (str) — optional keyword to filter PRs by title

**Returns:** Formatted list of PRs with number, state, title, and branch name.

### `list_commits`

**Inputs:**
- `path` (str) — file path to filter commits for (empty for all)
- `branch` (str) — branch to list from (defaults to main)
- `limit` (int) — number of commits (defaults to 10)

**Returns:** Formatted list with short SHA, date, author, and first line of message.

### `wait_for_atlantis`

> **Note:** This tool is NOT a `@tool` decorator tool — it's a raw ToolSpec/ToolResult handler (custom tool protocol).

**Inputs:**
- `repo_full_name` (str) — full repo name e.g. `wehttqm/arc-ipa-tf`
- `pr_number` (int) — PR number
- `event_type` (str) — `plan` or `apply` (default: plan)

**Behavior:** Registers an async task (HEALTHY_BUSY), stores session mapping in DynamoDB (key: `{repo_full_name}#{pr_number}`, value: session_id), and sets `stop_event_loop=True` so the agent loop terminates after this tool. Session resumes automatically via webhook.

### MCP Tools

External integrations connect via MCP (Model Context Protocol) using **streamable HTTP transport**.

**Currently integrated:** Atlassian (Jira read/search via `https://mcp.atlassian.com/v2/mcp`)

**Tool whitelist:**
- `getAccessibleAtlassianResources`
- `atlassianUserInfo`
- `getJiraIssue`
- `getJiraIssueRemoteIssueLinks`
- `getVisibleJiraProjects`
- `lookupJiraAccountId`
- `searchJiraIssuesUsingJql`

**Auth:** The CLI provides OAuth tokens at session init; the agent-side uses a `TokenHolder` pattern for mid-session token refresh.

**Configuration:** The `MCP_REGISTRY` dict maps token keys to server URLs and tool filters. See `tools/mcp.py` for the client setup.
