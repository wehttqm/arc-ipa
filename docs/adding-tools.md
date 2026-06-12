# Adding Tools to the Infra Agent

This guide covers how to add new tools to the infra-agent. Each tool is a single Python file in `infra-agent/tools/` that exposes one function decorated with `@tool` from the Strands SDK.

## Current Tools

| Tool | Description |
|------|-------------|
| `read_file` | Read a file from arc-ipa-tf |
| `write_file` | Create/update a file on a branch |
| `list_files` | List files in a directory |
| `create_pull_request` | Open a new PR |
| `merge_pull_request` | Merge a PR (squash/merge/rebase) |
| `update_pull_request` | Change PR state (open/closed) |
| `comment_on_pr` | Post a comment (e.g. trigger Atlantis) |
| `read_pr_comments` | Read comments on a PR |
| `list_pull_requests` | List PRs with optional filters |
| `wait_for_atlantis` | Wait for Atlantis plan/apply to complete |
| `validate_request` | Validate a provisioning request against standards |
| `get_mcp_tools` | Load MCP-based tools (Jira, etc.) |

## File Structure

```
infra-agent/tools/
├── __init__.py          # Exports all tools
├── your_new_tool.py     # One tool per file
├── read_file.py
├── write_file.py
└── ...
```

## Step 1: Create the Tool File

Create a new file in `infra-agent/tools/`. The file should contain a single function decorated with `@tool`.

```python
"""Tool: brief description of what it does."""

from strands import tool
from github_app import github_api  # if interacting with GitHub


@tool
def your_tool_name(param1: str, param2: int = 0) -> str:
    """One-line summary of what this tool does.

    This docstring becomes the tool description the LLM sees when deciding
    whether to call your tool. Be specific about what it does and when to use it.

    Args:
        param1: Description of param1
        param2: Description of param2 (defaults to 0)
    """
    # Implementation here
    return "result string"
```

### Requirements

- **One tool per file.** File name should match the function name.
- **Use type hints** on all parameters and the return type. The agent uses these to build the tool schema.
- **Docstring is critical.** The first line + Args section is what the LLM reads to decide when/how to call your tool. Be precise.
- **Return a string.** The agent passes the return value back into the conversation.
- **Use `github_api()`** from `github_app.py` for any GitHub API calls (it handles auth via the GitHub App).

## Step 2: Export from `__init__.py`

Add your import to `infra-agent/tools/__init__.py`:

```python
from .your_tool_name import your_tool_name
```

## Step 3: Register in `agent.py`

Add the tool to the imports and the `tools` list in `agent.py`:

```python
from tools import (
    ...,
    your_tool_name,
)

tools = [
    ...,
    your_tool_name,
] + get_mcp_tools()
```

## Step 4: Update the System Prompt (if needed)

If your tool changes the agent's workflow (e.g. adds a new step to the provisioning process), update `SYSTEM_PROMPT` in `agent.py` to reference when/how the agent should use it.

## Example: Minimal Tool

```python
"""Tool: check if a Terraform workspace is locked."""

from strands import tool
from github_app import github_api


@tool
def check_workspace_lock(workspace: str) -> str:
    """Check whether an Atlantis workspace is currently locked.

    Args:
        workspace: The workspace name (e.g. 's3-buckets-pf-sandbox-usw2')
    """
    resp = github_api("GET", f"issues?labels=atlantis/lock/{workspace}")
    issues = resp.json()
    if issues:
        return f"Workspace '{workspace}' is LOCKED (PR #{issues[0]['number']})"
    return f"Workspace '{workspace}' is unlocked"
```

## MCP Tools (External Services)

For integrations that use MCP (Model Context Protocol) rather than direct API calls, add them in `tools/mcp.py`. The config (URLs, auth) is stored in AWS Secrets Manager under `arc-ipa/mcp`.

## Testing Locally

Use `test_local.py` to test your tool in isolation:

```bash
python test_local.py
```

This runs the agent locally without AgentCore so you can verify tool behavior before deploying.
