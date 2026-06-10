#!/usr/bin/env python3
"""Interactive CLI for the AgentCore infrastructure agent."""

import boto3
import json
import os
import subprocess
import sys
import uuid

from prompt_toolkit import PromptSession
from prompt_toolkit.history import FileHistory
from rich.console import Console
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.theme import Theme

REGION = "us-west-2"
RUNTIME_TF_DIR = os.path.join(os.path.dirname(__file__), "..", "tf", "modules", "agentcore", "runtime")
HISTORY_DIR = os.path.join(os.path.dirname(__file__), ".chat_history")
os.makedirs(HISTORY_DIR, exist_ok=True)

theme = Theme({"user": "bold cyan", "agent": "bold green", "dim": "dim"})
console = Console(theme=theme)


def get_agent_arn():
    arn = os.environ.get("AGENT_RUNTIME_ARN")
    if arn:
        return arn
    else:
        sys.exit("Error: set AGENT_RUNTIME_ARN environment variable to your agent runtime ARN.")


def stream_response(client, arn, session_id, prompt):
    response = client.invoke_agent_runtime(
        agentRuntimeArn=arn,
        qualifier="DEFAULT",
        runtimeSessionId=session_id,
        payload=json.dumps({"prompt": prompt}).encode(),
    )

    output = ""
    with Live(Markdown(""), console=console, refresh_per_second=12, vertical_overflow="visible") as live:
        for line in response["response"].iter_lines():
            if not line:
                continue
            text = line.decode("utf-8")
            if not text.startswith("data: "):
                continue
            try:
                event = json.loads(text[6:])
            except (json.JSONDecodeError, ValueError):
                continue
            if not isinstance(event, dict):
                continue
            if "force_stop" in event:
                live.stop()
                console.print(f"\n[bold red]Error:[/] {event.get('force_stop_reason', 'unknown')}")
                return None
            if "error" in event:
                live.stop()
                console.print(f"\n[bold red]Error:[/] {event['error']}")
                return None
            delta = event.get("event", {}).get("contentBlockDelta", {}).get("delta", {})
            chunk = delta.get("text", "")
            if chunk:
                output += chunk
                live.update(Markdown(output))
    return output


def main():
    arn = get_agent_arn()
    client = boto3.client("bedrock-agentcore", region_name=REGION)
    session_id = uuid.uuid4().hex + "0"  # 33 chars required

    console.print(Panel(
        "[agent]Infra Agent[/] — interactive session\n"
        "[dim]Type your message and press Enter. Ctrl+D or 'exit' to quit.[/dim]",
        border_style="green",
    ))
    console.print(f"[dim]session: {session_id[:8]}...[/dim]\n")

    prompt_session = PromptSession(
        history=FileHistory(os.path.join(HISTORY_DIR, "prompts")),
    )

    while True:
        try:
            user_input = prompt_session.prompt("❯ ").strip()
        except (EOFError, KeyboardInterrupt):
            console.print("\n[dim]Goodbye.[/dim]")
            break

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit", "/quit", "/exit"):
            console.print("[dim]Goodbye.[/dim]")
            break

        console.print()
        stream_response(client, arn, session_id, user_input)
        console.print()


if __name__ == "__main__":
    main()
