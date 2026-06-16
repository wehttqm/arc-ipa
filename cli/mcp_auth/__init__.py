"""Modular MCP authentication.

To add a new MCP integration: implement an ``MCPProvider`` (see ``base.py``;
``oauth.py`` provides a reusable OAuth 2.0 client) and append an instance to
``REGISTRY`` below. No CLI changes are required — the CLI discovers configured
providers, reuses silent tokens, and prompts before any interactive login.
"""

from __future__ import annotations

import asyncio
from typing import Awaitable, Callable, Optional

from .atlassian import AtlassianProvider
from .base import MCPProvider

#: All known MCP providers. Append new ones here.
REGISTRY: list[MCPProvider] = [
    AtlassianProvider(),
]

# An async callable that asks the user a yes/no question. Returns True (yes),
# False (no), or None (cancelled).
ConfirmFn = Callable[[str], Awaitable[Optional[bool]]]


async def resolve_provider_tokens(
    confirm: ConfirmFn,
    notify: Optional[Callable[[str], None]] = None,
) -> dict[str, str]:
    """Collect auth tokens for every configured MCP provider.

    For each provider that is configured:
      * reuse a silent (cached/refreshed) token if available;
      * otherwise, if the provider needs interactive login, ask the user via
        ``confirm`` before running ``authenticate()``.

    ``notify`` is an optional sync callback for status messages. A single
    provider failing never blocks the others or the CLI.

    Returns ``{token_key: token}`` to merge into the init message.
    """
    tokens: dict[str, str] = {}

    def _say(msg: str) -> None:
        if notify:
            notify(msg)

    for provider in REGISTRY:
        try:
            # Cache-first: a valid token is usable without contacting Secrets
            # Manager or any cloud credentials. This must run before any
            # is_configured() check so an expired AWS session can't disable a
            # perfectly good cached token.
            token = await asyncio.to_thread(provider.get_token_silent)

            if token is None and provider.interactive:
                # No usable token — an interactive login is needed, which does
                # require client credentials (is_configured()).
                if not await asyncio.to_thread(provider.is_configured):
                    _say(
                        f"{provider.name}: no cached token and credentials are "
                        f"unavailable (check your AWS session); skipping."
                    )
                    continue
                answer = await confirm(f"Authenticate with {provider.name}?")
                if answer is None:
                    _say(f"Skipped {provider.name} authentication.")
                    continue
                if answer:
                    _say(f"Opening browser to authenticate with {provider.name}…")
                    token = await asyncio.to_thread(provider.authenticate)
                    if not token:
                        _say(f"{provider.name} authentication did not complete.")
                else:
                    _say(f"Skipped {provider.name} authentication.")

            if token:
                tokens[provider.token_key] = token
                _say(f"{provider.name} connected.")
        except Exception as exc:  # never let one provider break startup
            _say(f"{provider.name} authentication failed: {exc}")

    return tokens
