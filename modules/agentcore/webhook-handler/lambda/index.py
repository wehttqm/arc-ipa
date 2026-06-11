"""GitHub webhook handler — receives Atlantis comments and re-invokes AgentCore sessions."""

import os
import json
import hmac
import hashlib
import boto3

SESSIONS_TABLE = os.environ["SESSIONS_TABLE"]
SECRET_NAME = os.environ["SECRET_NAME"]
AGENT_RUNTIME_ARN = os.environ["AGENT_RUNTIME_ARN"]

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(SESSIONS_TABLE)
secrets = boto3.client("secretsmanager")
agentcore = boto3.client("bedrock-agentcore")

_webhook_secret = None


def _get_webhook_secret():
    global _webhook_secret
    if not _webhook_secret:
        resp = secrets.get_secret_value(SecretId=SECRET_NAME)
        secret = json.loads(resp["SecretString"])
        _webhook_secret = secret["webhook_secret"]
    return _webhook_secret


def _verify_signature(body: bytes, signature: str) -> bool:
    if not signature:
        return False
    secret = _get_webhook_secret()
    expected = "sha256=" + hmac.HMAC(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def _detect_event_type(body: str) -> str:
    if "Ran Apply" in body or "apply complete" in body.lower():
        return "apply"
    return "plan"


def handler(event, context):
    # Verify webhook signature
    body = event.get("body", "")
    body_bytes = body.encode() if isinstance(body, str) else body
    headers = {k.lower(): v for k, v in event.get("headers", {}).items()}
    signature = headers.get("x-hub-signature-256", "")

    if not _verify_signature(body_bytes, signature):
        return {"statusCode": 401, "body": "Invalid signature"}

    # Respond to GitHub ping events
    gh_event = headers.get("x-github-event", "")
    if gh_event == "ping":
        return {"statusCode": 200, "body": "pong"}

    payload = json.loads(body)

    # Only process issue_comment events (PR comments)
    action = payload.get("action")
    if action != "created":
        return {"statusCode": 200, "body": "Ignored"}

    comment = payload.get("comment", {})
    comment_user = comment.get("user", {}).get("login", "")

    # Only process Atlantis bot comments
    if "atlantis" not in comment_user.lower():
        return {"statusCode": 200, "body": "Not Atlantis"}

    pr_number = payload.get("issue", {}).get("number")
    if not pr_number:
        return {"statusCode": 200, "body": "No PR number"}

    # Look up the session waiting on this PR
    resp = table.get_item(Key={"pr_number": pr_number})
    item = resp.get("Item")
    if not item:
        return {"statusCode": 200, "body": "No session waiting for this PR"}

    session_id = item["session_id"]
    event_type = _detect_event_type(comment["body"])

    # Re-invoke the AgentCore session with the webhook payload
    agentcore.invoke_agent_runtime(
        agentRuntimeArn=AGENT_RUNTIME_ARN,
        runtimeSessionId=session_id,
        payload=json.dumps({
            "webhook": {
                "pr_number": pr_number,
                "comment_body": comment["body"],
                "event_type": event_type,
            }
        }),
    )

    # Clean up the session record
    table.delete_item(Key={"pr_number": pr_number})

    return {"statusCode": 200, "body": f"Delivered {event_type} result to session {session_id}"}
