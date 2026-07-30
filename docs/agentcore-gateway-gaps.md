# AgentCore Gateway + Strands Agent SDK — Integration Gaps

**Date:** 2026-07-27
**Author:** Platform Team
**Status:** Draft — for internal reference and potential feedback to AWS

---

## Summary

We're building a Teams bot → AgentCore Runtime → Gateway → GitHub MCP pipeline with per-user OAuth (3LO via Authorization Code Grant). The integration works for the happy path (user has no token → -32042 → auth card → user consents → tool succeeds), but breaks down in edge cases due to under-specified behavior in both the Gateway and the Strands Agent SDK.

---

## Gap 1: Gateway Token Lifecycle is Opaque

### Problem

The gateway only emits `-32042` (elicitation required) when **no token exists** in the vault for the user. If a token exists but is revoked, expired without a refresh token, or otherwise invalid, the gateway:

1. Fetches the token from the vault
2. Passes it to the upstream MCP server (e.g., GitHub)
3. Gets a 401/403 back
4. Returns a **generic tool error** to the agent (not -32042)

This means the agent/bot has no way to distinguish "re-auth needed" from "GitHub is down" or "bad request." The model sees the error and generates a conversational response about needing auth, but the auth card is never triggered.

### Expected Behavior

The gateway should:

- Detect 401/403 from upstream after presenting a stored token
- Attempt a token refresh (if refresh token is available)
- If refresh fails or no refresh token → emit -32042 to re-initiate the 3LO flow
- Provide distinct error codes for: no token, token invalid/revoked, upstream service error, gateway internal error

### Impact

- Cannot test the auth flow without deleting/recreating the gateway target
- Users with revoked tokens get a broken experience (model talks about needing auth but no card appears)
- No `delete-resource-token` or `revoke-token` API exists to manually clear a user's token

---

## Gap 2: No Per-User Token Management API

### Problem

The token vault has no API to delete or revoke a specific user's stored OAuth token. Available options are all nuclear:

| Action | Blast Radius |
|--------|-------------|
| `delete-workload-identity` | Blocked — "linked to a service" |
| `delete-gateway-target` + recreate | All users lose tokens for that target |
| `delete-oauth2-credential-provider` | All users, all gateways using that provider |
| Revoke on provider side (GitHub) | Works but gateway doesn't re-trigger -32042 (see Gap 1) |

### Expected Behavior

- `delete-resource-token --workload-identity <name> --credential-provider <arn>` or similar
- Per-user, per-target token revocation
- Optionally: a way to query token status (valid, expired, revoked)

### Impact

- No way to implement a `/disconnect` command that cleanly de-auths a user from a service
- Testing the auth flow during development requires destroying and recreating infrastructure
- No path to building "manage your connections" UX for end users

---

## Gap 3: Strands SDK Doesn't Support Clean Tool-Level Interrupts

### Problem

When a tool needs to abort the agent loop and surface structured data to the caller (e.g., "show an auth card"), there's no first-class mechanism. The current workaround:

1. Override `_handle_tool_execution_error` in our MCPClient subclass
2. Raise a custom `AuthRequiredError` exception
3. The Strands `ToolExecutor._stream()` catch-all catches it
4. Converts it to an error tool result: `"Error: Authorization required: <url>"`
5. Feeds that error text back to the model
6. The model generates a conversational response about needing auth (the "phantom message" in Datadog)
7. `agent(prompt)` returns normally with the model's text
8. Our code checks a side-channel `auth_state` dict and emits the auth card instead

### Consequences

- The model wastes a turn generating a response that's thrown away
- The "phantom message" shows up in Datadog/tracing as a real agent response
- The pattern relies on mutable shared state (`auth_state` dict) checked after-the-fact
- If the exception isn't raised (e.g., Gap 1 — generic error instead of -32042), the model's response leaks through as a real message

### Expected Behavior

A way to halt the agent loop from tool execution and return structured data to the caller without the model generating a response. Options:

1. **First-class abort/interrupt from tool execution** — tool returns a special result type that stops the loop immediately and surfaces data to the caller without going back to the model
2. **Exception propagation** — allow specific exception types to propagate out of `agent(prompt)` without being caught by the executor's catch-all
3. **Hook-based interruption** — an `AfterToolCallEvent` hook that can halt the loop and inject a custom response

The existing `Interrupt` mechanism is close but designed for human-in-the-loop approval flows, not "abort and redirect to external auth."

---

## Gap 4: Blank Message in Teams (Symptom of Gap 3)

### Problem

When the auth flow triggers, Teams shows two messages:
1. A blank message
2. The auth card

And Datadog logs a third message that never appears in Teams:
> "It looks like the GitHub credentials aren't currently authorized..."

### Root Cause

This is a downstream symptom of the Strands catch-all (Gap 3). The exact mechanism producing the blank message is either:

- The AgentCore Runtime emitting an empty initial SSE frame before the generator yields
- The adaptive card `ctx.reply()` with no text body rendering as a blank bubble in Teams

The Datadog-logged message is the model's response to the error tool result — generated but discarded by our `auth_state` check.

---

## Recommendations

### Short-term (workarounds we can implement)

1. ~~Hardcode service names~~ → Derive service name from OAuth URL at the bot layer ✅ Done
2. Investigate the blank message — likely fixable by either suppressing empty frames or adding text to the card reply
3. Consider suppressing the phantom model turn by returning a tool result that says "STOP — do not respond" (hacky but may prevent the wasted turn)

### Medium-term (feature requests to AWS)

1. Gateway should re-trigger -32042 when stored tokens are invalid (not just absent)
2. Per-user token deletion/revocation API
3. Token status introspection API

### Long-term (Strands SDK enhancement)

1. First-class tool abort/interrupt mechanism that doesn't feed back to the model
2. Or: configurable exception types that propagate through the executor without being caught

---

## References

- [Gateway Outbound Auth Docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-outbound-auth.html)
- [MCP Elicitation Docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-mcp-elicitation.html)
- [Strands MCPClient Source](https://github.com/strands-agents/sdk-python/blob/main/src/strands/tools/mcp/mcp_client.py)
- Gateway Terraform: `modules/agentcore/gateway/terraform/main.tf`
- Agent auth handling: `infra-agent/gateway_client.py`
