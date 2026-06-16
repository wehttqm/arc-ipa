"""Base abstraction for MCP authentication providers.

Each MCP integration that needs per-user credentials implements an
``MCPProvider``. The CLI:

  1. calls ``is_configured()`` to decide whether to consider the provider,
  2. calls ``get_token_silent()`` to reuse cached/refreshable creds with no
     user interaction,
  3. and only calls ``authenticate()`` (which may open a browser) when an
     interactive login is actually required — after asking the user.

Adding a new MCP later is just: subclass ``MCPProvider`` and append an instance
to ``REGISTRY`` in ``mcp_auth/__init__.py``.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional


class MCPProvider(ABC):
    #: Human-facing name shown in prompts, e.g. "Atlassian".
    name: str = "unknown"

    #: Key the backend agent expects in the WebSocket init message,
    #: e.g. "atlassian_token".
    token_key: str = "token"

    #: Whether authenticate() requires user interaction (e.g. a browser). When
    #: True, the CLI asks the user before calling authenticate().
    interactive: bool = True

    @abstractmethod
    def is_configured(self) -> bool:
        """Return True if the server-side config (e.g. OAuth client creds)
        needed to use this provider exists. Should never raise."""

    @abstractmethod
    def get_token_silent(self) -> Optional[str]:
        """Return a valid token using only cached/refreshable credentials,
        without any user interaction. Return None if an interactive login is
        required (or if silent acquisition fails)."""

    @abstractmethod
    def authenticate(self) -> Optional[str]:
        """Run the interactive login flow (may open a browser) and return a
        token, or None if it failed or was cancelled."""
