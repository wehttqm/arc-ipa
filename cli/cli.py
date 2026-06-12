#!/usr/bin/env python3
"""Interactive CLI for the AgentCore infrastructure agent via WebSocket."""

import asyncio
import json
import os
import re
import sys
import uuid

from prompt_toolkit import PromptSession
from prompt_toolkit.application import Application
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.history import FileHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import Layout
from prompt_toolkit.layout.containers import Window
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.styles import Style
from rich.console import Console, Group
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.text import Text
from rich.theme import Theme

from bedrock_agentcore.runtime import AgentCoreRuntimeClient
import websockets

REGION = "us-west-2"
HISTORY_DIR = os.path.join(os.path.dirname(__file__), ".chat_history")
os.makedirs(HISTORY_DIR, exist_ok=True)

_ANSI_RE = re.compile(
    r"\x1b\[[\?0-9;]*[a-zA-Z~]"
    r"|\x1b[()][A-Z0-9]"
    r"|\x1b\][\d;]*\x07"
    r"|\[[\?]?\d*[a-zA-Z~]"
    r"|\[\d*;\d*[a-zA-Z]"
)

theme = Theme({"user": "bold cyan", "agent": "bold purple", "dim": "dim"})
console = Console(theme=theme)

# A thick, bold-light green bar with a blank line of padding above it, so the user's
# input line clearly stands apart from the agent's `▸` tool lines above it.
PROMPT_STYLE = Style.from_dict({"pad": "", "bar": "bold cyan"})
PROMPT_MESSAGE = FormattedText([("class:pad", "\n"), ("class:bar", "❯❯ ")])


def strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def get_agent_arn():
    arn = os.environ.get("AGENT_RUNTIME_ARN")
    if arn:
        return arn
    console.print("[bold red]Error:[/] Set [bold]AGENT_RUNTIME_ARN[/] environment variable.")
    sys.exit(1)


def render_tool(name, args_str="", out=None):
    out = out or console
    summary = ""
    if args_str:
        try:
            args = json.loads(args_str)
            parts = []
            for k, v in list(args.items())[:3]:
                val = str(v) if not isinstance(v, str) else v
                if len(val) > 40:
                    val = val[:37] + "…"
                parts.append(f"{k}={val}")
            summary = " " + ", ".join(parts)
        except (json.JSONDecodeError, ValueError):
            pass
    out.print(f"  [blue]▸[/blue] [bold]{name}[/bold][dim]{summary}[/dim]")


# Matches an agent turn that ends by asking the user to confirm. We only look at
# the last non-empty line, and require the question form (trailing "?"), so a
# mid-sentence mention like "...get ready to proceed with step 1" won't trigger.
_CONFIRM_RE = re.compile(r"ready to provision\s*\?\s*$", re.IGNORECASE)


def needs_confirmation(text: str) -> bool:
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    if not lines:
        return False
    # Strip common trailing markdown emphasis (*, _, `) before matching.
    last = lines[-1].rstrip("*_`> ").strip()
    return bool(_CONFIRM_RE.search(last))


async def confirm_proceed() -> bool | None:
    """Inline yes/no selector navigable with arrow keys.

    Returns True for Yes, False for No, or None if the user cancels
    (Ctrl-C / Ctrl-D).
    """
    selected = 0  # 0 = Yes, 1 = No

    def get_fragments():
        yes_cls = "class:selected" if selected == 0 else "class:option"
        no_cls = "class:selected" if selected == 1 else "class:option"
        return [
            ("class:hint", "  ←/→ to choose, Enter to confirm   "),
            (yes_cls, " Yes "),
            ("", "  "),
            (no_cls, " No "),
        ]

    kb = KeyBindings()

    @kb.add("left")
    @kb.add("up")
    def _move_prev(event):
        nonlocal selected
        selected = (selected - 1) % 2

    @kb.add("right")
    @kb.add("down")
    def _move_next(event):
        nonlocal selected
        selected = (selected + 1) % 2

    @kb.add("enter")
    def _accept(event):
        event.app.exit(result=(selected == 0))

    @kb.add("y")
    def _yes(event):
        event.app.exit(result=True)

    @kb.add("n")
    def _no(event):
        event.app.exit(result=False)

    @kb.add("c-c")
    @kb.add("c-d")
    def _cancel(event):
        event.app.exit(result=None)

    style = Style.from_dict(
        {
            "hint": "dim",
            "option": "",
            "selected": "reverse bold cyan",
        }
    )
    app = Application(
        layout=Layout(Window(FormattedTextControl(get_fragments, focusable=True), height=1)),
        key_bindings=kb,
        style=style,
        full_screen=False,
        mouse_support=False,
    )
    return await app.run_async()


_CLOSED = object()  # sentinel: WebSocket closed


class TurnRenderer:
    """Renders the frames of a single agent turn (live markdown + tool lines).

    State is per-turn; begin_turn() resets it. A turn may be user-initiated
    (started after the user sends a prompt) or server-initiated (a webhook
    resume, which opens with an `async_complete` frame).
    """

    def __init__(self, console):
        self.console = console
        self.last_output = ""  # full text of the most recently completed turn
        self._reset()

    def _reset(self):
        self.output = ""
        self.current_tool = None
        self.tool_buf = ""
        self.live = None
        self._need_gap = False  # set after a tool line; gap before next text block

    def _ensure_live(self):
        """Lazily start the live region on the first text chunk.

        Starting lazily (instead of holding an empty Live between tool calls)
        avoids the stray blank line each idle Live used to leave behind, and
        lets us insert a single blank line after a run of tool calls.
        """
        if self.live is not None:
            return
        if self._need_gap:
            self.console.print()
            self._need_gap = False
        self.live = Live(
            Text(""), console=self.console, refresh_per_second=12, vertical_overflow="visible"
        )
        self.live.start()

    def _stop_live(self):
        if self.live:
            self.live.stop()
            self.live = None

    def begin_turn(self):
        self._reset()

    def banner(self, frame):
        """Render the 'resuming…' banner for a server-initiated (webhook) turn."""
        event_type = frame.get("event_type", "")
        self._stop_live()
        self.console.print(
            f"\n[bold purple]⟳[/bold purple] [dim]Atlantis {event_type} result received, resuming…[/dim]\n"
        )
        self.output = ""
        self._need_gap = False

    def handle(self, inner):
        """Render a single `stream` frame's data payload."""
        if not isinstance(inner, dict):
            return

        if "force_stop" in inner:
            self._stop_live()
            self.console.print(f"\n[bold red]Error:[/] {inner.get('force_stop_reason', 'unknown')}")
            self.output = ""
            self._need_gap = False
            return
        if "error" in inner:
            self._stop_live()
            self.console.print(f"\n[bold red]Error:[/] {inner['error']}")
            self.output = ""
            self._need_gap = False
            return

        event_data = inner.get("event", {})

        # Tool use start
        start = event_data.get("contentBlockStart", {}).get("start", {})
        if "toolUse" in start:
            self.current_tool = start["toolUse"].get("name", "unknown")
            self.tool_buf = ""
            return

        # Tool use end
        if "contentBlockStop" in event_data and self.current_tool:
            # Commit any text that streamed before this tool (with a trailing
            # gap), then print the tool line. Don't open a new Live here — it
            # stays closed so consecutive tool calls render on adjacent lines.
            if self.output.strip() and self.live:
                self.live.update(Markdown(self.output))
                self._stop_live()
                self.console.print()
                self.output = ""
            else:
                self._stop_live()
            render_tool(self.current_tool, self.tool_buf, self.console)
            self._need_gap = True
            self.current_tool = None
            self.tool_buf = ""
            return

        # Deltas
        delta = event_data.get("contentBlockDelta", {}).get("delta", {})
        tool_chunk = delta.get("toolUse", {}).get("input", "")
        if tool_chunk and self.current_tool:
            self.tool_buf += tool_chunk
            return
        chunk = delta.get("text", "")
        if chunk:
            self._ensure_live()
            self.output += strip_ansi(chunk)
            self.live.update(Markdown(self.output))

    def finish(self):
        if self.output.strip() and self.live:
            self.live.update(Markdown(self.output))
        self._stop_live()
        self.last_output = self.output
        self._reset()


async def _reader(ws, frame_q):
    """Continuously read frames off the socket and queue them.

    Decoupling the read from the send is what lets a server-initiated resumed
    turn surface while the user is sitting idle at the prompt.
    """
    try:
        async for raw in ws:
            try:
                frame = json.loads(raw) if isinstance(raw, str) else json.loads(raw.decode())
            except (ValueError, TypeError):
                continue
            await frame_q.put(frame)
    except Exception:
        pass
    finally:
        await frame_q.put(_CLOSED)


async def _render_turn(frame_q, renderer, first=None) -> bool:
    """Render frames until `turn_complete`. Returns False if the socket closed."""
    renderer.begin_turn()
    frame = first
    try:
        while True:
            if frame is None:
                frame = await frame_q.get()
            if frame is _CLOSED:
                return False
            ev = frame.get("event")
            if ev == "turn_complete":
                return True
            if ev == "async_complete":
                renderer.banner(frame)
            elif ev == "stream":
                renderer.handle(frame.get("data", {}))
            frame = None
    finally:
        renderer.finish()


async def _drive_turn(frame_q, renderer, send, first=None) -> bool:
    """Render a turn and, if it ends by asking the user to confirm, present an
    arrow-key yes/no selector and continue the conversation with the answer.

    Loops so the agent can ask to confirm again after each reply. Returns False
    if the socket closed.
    """
    while True:
        if not await _render_turn(frame_q, renderer, first):
            return False
        first = None

        if not needs_confirmation(renderer.last_output):
            return True

        answer = await confirm_proceed()
        if answer is None:
            console.print("[dim]Cancelled — type a message to continue.[/dim]")
            return True

        reply = "yes" if answer else "no"
        console.print(f"  [cyan]❯[/cyan] [bold]{reply}[/bold]\n")
        await send(json.dumps({"prompt": reply}))


async def _settle(task):
    """Cancel-and-drain a task, swallowing the resulting CancelledError."""
    if task.cancelled():
        return
    if not task.done():
        task.cancel()
    try:
        await task
    except BaseException:
        pass


_EXIT_WORDS = ("exit", "quit", "/quit", "/exit")


async def _interaction_loop(send, make_prompt, frame_q, renderer):
    """Coordinate user input and server pushes over one connection.

    Each iteration races the interactive prompt against the next incoming frame:
      - If a frame arrives first, the server started a turn (a webhook resume).
        Cancel the idle prompt and render the turn.
      - If the user submits first, send the prompt and render the response turn.

    A frame that races in just as the user submits is held over (`pending_frame`)
    so it is never dropped.
    """
    pending_frame = None
    while True:
        # A server turn is already queued — render it before prompting again.
        if pending_frame is not None:
            first, pending_frame = pending_frame, None
            if first is _CLOSED or not await _drive_turn(frame_q, renderer, send, first):
                return
            continue

        prompt_task = asyncio.ensure_future(make_prompt())
        frame_task = asyncio.ensure_future(frame_q.get())
        done, _ = await asyncio.wait(
            {prompt_task, frame_task}, return_when=asyncio.FIRST_COMPLETED
        )

        # Server-initiated turn wins: preempt the prompt and render.
        if frame_task in done:
            await _settle(prompt_task)
            first = frame_task.result()
            if first is _CLOSED or not await _drive_turn(frame_q, renderer, send, first):
                return
            continue

        # User submitted. A frame may have raced in — hold it over, don't drop it.
        if frame_task.done() and not frame_task.cancelled():
            pending_frame = frame_task.result()
        else:
            await _settle(frame_task)

        try:
            user_input = (prompt_task.result() or "").strip()
        except (EOFError, KeyboardInterrupt):
            console.print("\n[dim]Goodbye.[/dim]")
            return

        if not user_input:
            continue
        if user_input.lower() in _EXIT_WORDS:
            console.print("[dim]Goodbye.[/dim]")
            return

        console.print()
        await send(json.dumps({"prompt": user_input}))
        if not await _drive_turn(frame_q, renderer, send, None):
            return
        console.print()


async def run():
    arn = get_agent_arn()
    session_id = uuid.uuid4().hex + "0"

    client = AgentCoreRuntimeClient(region=REGION)
    ws_url, headers = client.generate_ws_connection(
        runtime_arn=arn,
        session_id=session_id,
    )

    console.clear()
    LOGO_FILE = os.path.join(os.path.dirname(__file__), "static/deadbird-ascii.txt")
    logo = Text("")
    if os.path.isfile(LOGO_FILE):
        with open(LOGO_FILE, "r") as f:
            logo = Text.from_ansi(f.read().rstrip())
    label = Text.from_markup(
        "\n[bold purple]Arc'teryx Platform Agent[/] — interactive session\n"
        "[dim]Type your message and press Enter. Ctrl+D or 'exit' to quit.[/dim]"
    )
    console.print(Panel(Group(logo, label), border_style="purple"))
    console.print(f"[dim]session: {session_id[:8]}…[/dim]\n")

    prompt_session = PromptSession(
        history=FileHistory(os.path.join(HISTORY_DIR, "prompts")),
        enable_suspend=False,
    )

    async with websockets.connect(ws_url, additional_headers=headers) as ws:
        frame_q = asyncio.Queue()
        reader_task = asyncio.ensure_future(_reader(ws, frame_q))
        renderer = TurnRenderer(console)

        async def send(text):
            await ws.send(text)

        async def make_prompt():
            # prompt_async (not a worker thread) so a server-initiated turn can
            # cancel the idle prompt to take over the terminal.
            return await prompt_session.prompt_async(PROMPT_MESSAGE, style=PROMPT_STYLE)

        try:
            await _interaction_loop(send, make_prompt, frame_q, renderer)
        finally:
            await _settle(reader_task)

    console.print("[dim]Goodbye.[/dim]")


def main():
    asyncio.run(run())


if __name__ == "__main__":
    main()
