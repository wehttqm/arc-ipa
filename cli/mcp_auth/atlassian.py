"""Atlassian (Rovo) remote MCP server auth provider.

Authenticates against Atlassian's hosted MCP server using the MCP OAuth 2.1
flow (metadata discovery, dynamic client registration, authorization-code +
PKCE). No pre-shared client credentials or Secrets Manager are needed — the
client self-registers and the issued token is scoped to the MCP server itself,
so it's accepted by the server's Bearer auth.
"""

from __future__ import annotations

import os
from typing import Optional

from .base import MCPProvider
from .oauth import McpOAuthClient, McpOAuthConfig

MCP_URL = "https://mcp.atlassian.com/v2/mcp"
REDIRECT_PORT = 19827

# Requested scopes — must be a subset of the server's advertised scopes_supported.
# offline_access yields a refresh token; read:me backs the user-info tool.
SCOPES = [
    "read:jira-work",
    # "write:jira-work",
    "search:confluence",
    "read:confluence-user",
    "read:page:confluence",
    # "write:page:confluence",
    "read:space:confluence",
    "read:comment:confluence",
    # "write:comment:confluence",
    "read:me",
    "offline_access",
]

_CLI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN_FILE = os.path.join(_CLI_DIR, ".atlassian_mcp_token.json")
CLIENT_FILE = os.path.join(_CLI_DIR, ".atlassian_mcp_client.json")


class AtlassianProvider(MCPProvider):
    name = "Atlassian"
    token_key = "atlassian_token"
    interactive = True

    def __init__(self) -> None:
        self._client = McpOAuthClient(
            McpOAuthConfig(
                mcp_url=MCP_URL,
                redirect_port=REDIRECT_PORT,
                scopes=SCOPES,
                token_file=TOKEN_FILE,
                client_file=CLIENT_FILE,
            )
        )

    def is_configured(self) -> bool:
        # No external configuration needed: the client self-registers via DCR.
        return True

    def get_token_silent(self) -> Optional[str]:
        return self._client.get_token_silent()

    def authenticate(self) -> Optional[str]:
        return self._client.authenticate()
