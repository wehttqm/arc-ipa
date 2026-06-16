"""MCP OAuth 2.1 client for remote (HTTP) MCP servers.

Implements the authorization flow the MCP spec requires for HTTP servers, the
same shape a compliant MCP client (e.g. an mcp.json-driven client) performs:

  1. Discover the server's OAuth metadata: protected-resource metadata
     (RFC 9728) -> authorization-server metadata (RFC 8414 / OIDC).
  2. Dynamically register a public client (RFC 7591) if we don't have one
     cached — no pre-shared client secret needed.
  3. Run the authorization-code flow with PKCE (RFC 7636) in the browser,
     passing the RFC 8707 ``resource`` indicator so the issued token's audience
     is the MCP server itself (not a different API).
  4. Exchange the code for tokens, cache them, and refresh silently.

Tokens minted this way are accepted by the MCP server's Bearer auth, unlike a
classic 3LO token minted for a different audience.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import time
import webbrowser
from dataclasses import dataclass, field
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional
from urllib.parse import urlencode, urlparse, parse_qs

import requests

_EXPIRY_BUFFER_SECONDS = 60
_HTTP_TIMEOUT = 20


@dataclass
class McpOAuthConfig:
    #: The MCP server endpoint, e.g. "https://mcp.atlassian.com/v2/mcp".
    mcp_url: str
    redirect_port: int
    #: OAuth scopes to request (must be a subset of the server's
    #: scopes_supported). Include "offline_access" to get a refresh token.
    scopes: list[str]
    #: Cache file for issued tokens.
    token_file: str
    #: Cache file for the dynamically-registered client.
    client_file: str
    #: Human-facing client name sent during dynamic registration.
    client_name: str = "arc-ipa-cli"

    @property
    def redirect_uri(self) -> str:
        return f"http://localhost:{self.redirect_port}/callback"


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


class McpOAuthClient:
    def __init__(self, config: McpOAuthConfig):
        self.cfg = config

    # ----- token cache -------------------------------------------------------

    def _load_tokens(self) -> Optional[dict]:
        return self._load_json(self.cfg.token_file)

    def _save_tokens(self, data: dict) -> None:
        data = dict(data)
        data["obtained_at"] = int(time.time())
        self._save_json(self.cfg.token_file, data)

    @staticmethod
    def _is_fresh(tokens: dict) -> bool:
        expires_in = tokens.get("expires_in", 3600)
        obtained_at = tokens.get("obtained_at", 0)
        return time.time() < obtained_at + expires_in - _EXPIRY_BUFFER_SECONDS

    @staticmethod
    def _load_json(path: str) -> Optional[dict]:
        if not os.path.isfile(path):
            return None
        try:
            with open(path) as f:
                return json.load(f)
        except (ValueError, OSError):
            return None

    @staticmethod
    def _save_json(path: str, data: dict) -> None:
        with open(path, "w") as f:
            json.dump(data, f)
        os.chmod(path, 0o600)

    # ----- public API --------------------------------------------------------

    def get_token_silent(self) -> Optional[str]:
        """Return a valid access token from cache or via refresh. Never opens a
        browser; returns None if interactive login is required."""
        tokens = self._load_tokens()
        if not tokens:
            return None

        if tokens.get("access_token") and self._is_fresh(tokens):
            return tokens["access_token"]

        refresh_token = tokens.get("refresh_token")
        client = self._load_json(self.cfg.client_file)
        if not refresh_token or not client or not client.get("client_id"):
            return None

        try:
            meta = self._discover()
            refreshed = self._token_request(
                meta["token_endpoint"],
                {
                    "grant_type": "refresh_token",
                    "refresh_token": refresh_token,
                    "client_id": client["client_id"],
                    "resource": meta["resource"],
                    "scope": " ".join(self.cfg.scopes),
                },
                client.get("client_secret"),
            )
            refreshed.setdefault("refresh_token", refresh_token)
            self._save_tokens(refreshed)
            return refreshed.get("access_token")
        except Exception:
            return None

    def authenticate(self) -> Optional[str]:
        """Run discovery + (dynamic registration) + browser PKCE flow, persist
        the tokens, and return the access token. Returns None on failure."""
        try:
            meta = self._discover()
            client = self._ensure_client(meta)
            tokens = self._authorization_code_flow(meta, client)
        except Exception:
            return None
        self._save_tokens(tokens)
        return tokens.get("access_token")

    # ----- discovery ---------------------------------------------------------

    def _discover(self) -> dict:
        """Resolve resource + authorization-server endpoints per the MCP spec.

        The MCP server may host its own AS metadata (a proxy that wraps the
        underlying auth server with correct resource-audience handling). We try
        the server's own well-known first, then fall back to following the
        authorization_servers link from the protected-resource metadata.
        """
        prm = self._fetch_protected_resource_metadata()
        resource = prm.get("resource") or self.cfg.mcp_url

        # 1) Try the MCP server's own AS metadata (Cloudflare proxy endpoints).
        p = urlparse(self.cfg.mcp_url)
        server_origin = f"{p.scheme}://{p.netloc}"
        asm = self._get_json(f"{server_origin}/.well-known/oauth-authorization-server")
        if asm and asm.get("authorization_endpoint") and asm.get("token_endpoint"):
            return self._build_meta(resource, asm)

        # 2) Follow the authorization_servers link from protected-resource.
        auth_servers = prm.get("authorization_servers") or []
        for issuer in auth_servers:
            asm = self._fetch_as_metadata(issuer)
            if asm:
                return self._build_meta(resource, asm)

        raise RuntimeError("Could not discover authorization-server metadata")

    @staticmethod
    def _build_meta(resource: str, asm: dict) -> dict:
        return {
            "resource": resource,
            "authorization_endpoint": asm["authorization_endpoint"],
            "token_endpoint": asm["token_endpoint"],
            "registration_endpoint": asm.get("registration_endpoint"),
            "code_challenge_methods": asm.get("code_challenge_methods_supported", ["S256"]),
        }

    def _fetch_protected_resource_metadata(self) -> dict:
        p = urlparse(self.cfg.mcp_url)
        origin = f"{p.scheme}://{p.netloc}"
        path = p.path.rstrip("/")
        candidates = [
            f"{origin}/.well-known/oauth-protected-resource{path}",
            f"{origin}/.well-known/oauth-protected-resource",
        ]
        for url in candidates:
            data = self._get_json(url)
            if data and data.get("authorization_servers"):
                return data

        # Fallback: probe the MCP endpoint and read the resource_metadata hint
        # from the WWW-Authenticate challenge.
        rm_url = self._resource_metadata_from_challenge()
        if rm_url:
            data = self._get_json(rm_url)
            if data and data.get("authorization_servers"):
                return data
        raise RuntimeError("Could not fetch protected-resource metadata")

    def _resource_metadata_from_challenge(self) -> Optional[str]:
        try:
            resp = requests.post(
                self.cfg.mcp_url,
                json={"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
                headers={"Accept": "application/json, text/event-stream"},
                timeout=_HTTP_TIMEOUT,
            )
        except requests.RequestException:
            return None
        challenge = resp.headers.get("WWW-Authenticate", "")
        for part in challenge.split(","):
            part = part.strip()
            if part.startswith("resource_metadata="):
                return part.split("=", 1)[1].strip().strip('"')
        return None

    def _fetch_as_metadata(self, issuer: str) -> dict:
        p = urlparse(issuer)
        origin = f"{p.scheme}://{p.netloc}"
        path = p.path.rstrip("/")
        if path:
            # RFC 8414 inserts the well-known segment before the issuer path.
            candidates = [
                f"{origin}/.well-known/oauth-authorization-server{path}",
                f"{origin}/.well-known/openid-configuration{path}",
                f"{issuer}/.well-known/oauth-authorization-server",
                f"{issuer}/.well-known/openid-configuration",
            ]
        else:
            candidates = [
                f"{origin}/.well-known/oauth-authorization-server",
                f"{origin}/.well-known/openid-configuration",
            ]
        for url in candidates:
            data = self._get_json(url)
            if data and data.get("authorization_endpoint") and data.get("token_endpoint"):
                return data
        raise RuntimeError("Could not fetch authorization-server metadata")

    @staticmethod
    def _get_json(url: str) -> Optional[dict]:
        try:
            resp = requests.get(url, timeout=_HTTP_TIMEOUT)
            if resp.status_code == 200:
                return resp.json()
        except (requests.RequestException, ValueError):
            pass
        return None

    # ----- dynamic client registration --------------------------------------

    def _ensure_client(self, meta: dict) -> dict:
        cached = self._load_json(self.cfg.client_file)
        if cached and cached.get("client_id"):
            return cached

        reg_endpoint = meta.get("registration_endpoint")
        if not reg_endpoint:
            raise RuntimeError("Server does not support dynamic client registration")

        resp = requests.post(
            reg_endpoint,
            json={
                "client_name": self.cfg.client_name,
                "redirect_uris": [self.cfg.redirect_uri],
                "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"],
                "token_endpoint_auth_method": "none",
                "scope": " ".join(self.cfg.scopes),
            },
            headers={"Content-Type": "application/json"},
            timeout=_HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        data = resp.json()
        client = {"client_id": data["client_id"]}
        if data.get("client_secret"):
            client["client_secret"] = data["client_secret"]
        self._save_json(self.cfg.client_file, client)
        return client

    # ----- authorization-code + PKCE -----------------------------------------

    def _authorization_code_flow(self, meta: dict, client: dict) -> dict:
        verifier = _b64url(secrets.token_bytes(48))
        challenge = _b64url(hashlib.sha256(verifier.encode("ascii")).digest())
        state = secrets.token_urlsafe(24)

        params = {
            "response_type": "code",
            "client_id": client["client_id"],
            "redirect_uri": self.cfg.redirect_uri,
            "scope": " ".join(self.cfg.scopes),
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "resource": meta["resource"],  # RFC 8707: bind token to the MCP server
        }
        auth_url = f"{meta['authorization_endpoint']}?{urlencode(params)}"

        captured: dict = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                qs = parse_qs(urlparse(self.path).query)
                captured["code"] = qs.get("code", [None])[0]
                captured["state"] = qs.get("state", [None])[0]
                captured["error"] = qs.get("error", [None])[0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<h3>Authenticated! You can close this tab.</h3>")

            def log_message(self, *args):
                pass

        server = HTTPServer(("localhost", self.cfg.redirect_port), Handler)
        try:
            webbrowser.open(auth_url)
            server.handle_request()
        finally:
            server.server_close()

        if captured.get("error"):
            raise RuntimeError(f"Authorization failed: {captured['error']}")
        if captured.get("state") != state:
            raise RuntimeError("OAuth state mismatch (possible CSRF)")
        code = captured.get("code")
        if not code:
            raise RuntimeError("OAuth callback did not include an authorization code")

        return self._token_request(
            meta["token_endpoint"],
            {
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": self.cfg.redirect_uri,
                "client_id": client["client_id"],
                "code_verifier": verifier,
                "resource": meta["resource"],
            },
            client.get("client_secret"),
        )

    @staticmethod
    def _token_request(token_endpoint: str, form: dict, client_secret: Optional[str]) -> dict:
        # Public clients (token_endpoint_auth_method=none) send no secret; if the
        # server issued one during registration, use client_secret_post.
        if client_secret:
            form = {**form, "client_secret": client_secret}
        resp = requests.post(
            token_endpoint,
            data=form,  # form-encoded per OAuth 2.1
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=_HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        return resp.json()
