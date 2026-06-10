#!/usr/bin/env python3
"""Interactive CLI for the AgentCore infrastructure agent."""

import boto3
import json
import os
import re
import sys
import termios
import tty
import uuid

from prompt_toolkit import PromptSession
from prompt_toolkit.history import FileHistory
from rich.console import Console, Group
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.text import Text
from rich.theme import Theme

REGION = "us-west-2"
HISTORY_DIR = os.path.join(os.path.dirname(__file__), ".chat_history")
os.makedirs(HISTORY_DIR, exist_ok=True)

# Regex to strip ANSI escapes, focus reports ([I/[O), bracketed paste, and CSI fragments
_ANSI_RE = re.compile(
    r"\x1b\[[\?0-9;]*[a-zA-Z~]"   # full CSI sequences (includes ?1004h, ?2004h, etc.)
    r"|\x1b[()][A-Z0-9]"           # charset sequences
    r"|\x1b\][\d;]*\x07"           # OSC sequences
    r"|\[[\?]?\d*[a-zA-Z~]"        # broken/partial CSI without ESC (e.g. [I, [O, [0m, [?1004l)
    r"|\[\d*;\d*[a-zA-Z]"          # e.g. [0;1m
)

theme = Theme({"user": "bold cyan", "agent": "bold green", "dim": "dim"})
console = Console(theme=theme)


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes and residual bracket sequences from text."""
    return _ANSI_RE.sub("", text)


def get_agent_arn():
    arn = os.environ.get("AGENT_RUNTIME_ARN")
    if arn:
        return arn
    console.print("[bold red]Error:[/] Set [bold]AGENT_RUNTIME_ARN[/] environment variable.")
    sys.exit(1)


def stream_response(client, arn, session_id, prompt):
    """Stream agent response, rendering text as markdown and tool calls as styled panels."""
    response = client.invoke_agent_runtime(
        agentRuntimeArn=arn,
        qualifier="DEFAULT",
        runtimeSessionId=session_id,
        payload=json.dumps({"prompt": prompt}).encode(),
    )

    output = ""
    tool_calls = []
    current_tool = None
    tool_input_buf = ""

    def flush_text(live):
        """Flush accumulated text to console and reset."""
        nonlocal output
        if output.strip():
            live.update(Markdown(output))
        return output

    def render_tool(name, args_str=""):
        """Print a compact one-line tool call indicator with args summary."""
        summary = ""
        if args_str:
            try:
                args = json.loads(args_str)
                # Show first few meaningful key=value pairs
                parts = []
                for k, v in list(args.items())[:3]:
                    val = str(v) if not isinstance(v, str) else v
                    if len(val) > 40:
                        val = val[:37] + "…"
                    parts.append(f"{k}={val}")
                summary = " " + ", ".join(parts)
            except (json.JSONDecodeError, ValueError):
                pass
        console.print(f"  [blue]▸[/blue] [bold]{name}[/bold][dim]{summary}[/dim]")

    live = Live(Text(""), console=console, refresh_per_second=12, vertical_overflow="visible")
    # Disable focus/mouse reporting and flush any queued terminal responses
    sys.stdout.write("\x1b[?1004l\x1b[?1003l\x1b[?1006l")
    sys.stdout.flush()
    # Suppress stdin echo during streaming so focus events don't print
    try:
        _old_attrs = termios.tcgetattr(sys.stdin)
        _new_attrs = termios.tcgetattr(sys.stdin)
        _new_attrs[3] &= ~termios.ECHO  # disable echo
        termios.tcsetattr(sys.stdin, termios.TCSANOW, _new_attrs)
        _restore_term = True
    except (termios.error, ValueError):
        _restore_term = False
    live.start()

    try:
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

            # Error handling
            if "force_stop" in event:
                live.stop()
                console.print(f"\n[bold red]Error:[/] {event.get('force_stop_reason', 'unknown')}")
                return None
            if "error" in event:
                live.stop()
                console.print(f"\n[bold red]Error:[/] {event['error']}")
                return None

            inner = event.get("event", {})

            # Tool use start — just record the name, wait for input
            start = inner.get("contentBlockStart", {}).get("start", {})
            if "toolUse" in start:
                current_tool = start["toolUse"].get("name", "unknown")
                tool_input_buf = ""
                continue

            # Content block stop — if we were in a tool, render it now
            if "contentBlockStop" in inner and current_tool:
                tool_calls.append(current_tool)
                if output.strip():
                    live.update(Markdown(output))
                    live.stop()
                    console.print()
                    output = ""
                else:
                    live.stop()
                render_tool(current_tool, tool_input_buf)
                current_tool = None
                tool_input_buf = ""
                live = Live(Text(""), console=console, refresh_per_second=12, vertical_overflow="visible")
                live.start()
                continue

            # Text/tool input delta
            delta = inner.get("contentBlockDelta", {}).get("delta", {})
            # Tool input accumulation
            tool_chunk = delta.get("toolUse", {}).get("input", "")
            if tool_chunk and current_tool:
                tool_input_buf += tool_chunk
                continue
            # Text delta
            chunk = delta.get("text", "")
            if chunk:
                clean = strip_ansi(chunk)
                output += clean
                live.update(Markdown(output))
    finally:
        live.stop()
        # Restore terminal echo
        if _restore_term:
            termios.tcsetattr(sys.stdin, termios.TCSANOW, _old_attrs)

    # Print final output if anything remains that Live didn't render cleanly
    # (Live already showed it, so we just return the value)
    return output if output.strip() else None


def check_aws_credentials():
    """Verify AWS credentials are available before starting."""
    try:
        boto3.client("sts", region_name=REGION).get_caller_identity()
    except Exception:
        console.print("[bold red]Error:[/] Not logged in to AWS. Run [bold]aws login[/] or configure credentials.")
        sys.exit(1)


LOGO_FILE = os.path.join(os.path.dirname(__file__), "static/deadbird-ascii.txt")


def get_logo():
    if os.path.isfile(LOGO_FILE):
        with open(LOGO_FILE, "r") as f:
            return Text.from_ansi(f.read().rstrip())
    return Text("")


def main():
    arn = get_agent_arn()
    check_aws_credentials()
    client = boto3.client("bedrock-agentcore", region_name=REGION)
    session_id = uuid.uuid4().hex + "0"

    # Disable terminal focus reporting globally to prevent [I/[O leaks
    sys.stdout.write("\x1b[?1004l\x1b[?1003l")
    sys.stdout.flush()

    console.clear()
    logo = get_logo()
    label = Text.from_markup(
        "\n[bold green]Arc'teryx Platform Agent[/] — interactive session\n"
        "[dim]Type your message and press Enter. Ctrl+D or 'exit' to quit.[/dim]"
    )
    console.print(Panel(Group(logo, label), border_style="green"))
    console.print(f"[dim]session: {session_id[:8]}…[/dim]\n")

    prompt_session = PromptSession(
        history=FileHistory(os.path.join(HISTORY_DIR, "prompts")),
        enable_suspend=False,
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
