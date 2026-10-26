"""Command line used by Neovim (``jobstart``). Every command prints JSON."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from . import client


def _print(value: Any) -> None:
    sys.stdout.write(json.dumps(value) + "\n")
    sys.stdout.flush()


def _csv(value: str | None) -> list[str] | None:
    return None if value is None else [v for v in value.split(",") if v]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="agentic_client")
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("start", help="create an agent and launch its detached supervisor")
    s.add_argument("--root", required=True)
    s.add_argument("--name", required=True)
    s.add_argument("--mode", choices=["ask", "edit"], default="ask")
    s.add_argument("--model", default="auto", help="name from project models, a Cursor model, or a JSON object")
    s.add_argument("--manager", default="default")
    s.add_argument("--prompts", help="comma separated names; omit for all")
    s.add_argument("--skills", help="comma separated names; omit for all")
    s.add_argument("--message")

    e = sub.add_parser("events", help="stream events as JSON lines")
    e.add_argument("agent_id")
    e.add_argument("--offset", type=int, default=0)
    e.add_argument("--no-follow", action="store_true")

    for name in ("pause", "resume", "stop", "kill", "delete", "detach-nvim", "restart"):
        sub.add_parser(name).add_argument("agent_id")

    sd = sub.add_parser("send")
    sd.add_argument("agent_id")
    sd.add_argument("text", nargs="?", help="message; read from stdin when omitted")

    rn = sub.add_parser("rename")
    rn.add_argument("agent_id")
    rn.add_argument("name")

    mv = sub.add_parser("move")
    mv.add_argument("agent_id")
    mv.add_argument("manager")

    grant = sub.add_parser("allow-read", help="let one agent read an extra directory the user named")
    grant.add_argument("agent_id")
    grant.add_argument("directory")

    an = sub.add_parser("attach-nvim")
    an.add_argument("agent_id")
    an.add_argument("pid", type=int)

    lr = sub.add_parser("lsp-result")
    lr.add_argument("agent_id")
    lr.add_argument("request_id")
    lr.add_argument("text", nargs="?")

    ls = sub.add_parser("list")
    ls.add_argument("--root", help="project root; omit for every project")
    ls.add_argument("--running", action="store_true")

    sub.add_parser("models").add_argument("--root", required=True)
    sub.add_parser("update-cursor-models", help="ask the Cursor CLI and write system_project/cursor_models.json")
    sub.add_parser("mcp").add_argument("--root", required=True)
    sub.add_parser("supervise").add_argument("agent_dir")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cmd = args.command
    try:
        if cmd == "supervise":
            from .supervisor import main as supervise

            return supervise(args.agent_dir)
        if cmd == "start":
            model: Any = args.model
            if model.strip().startswith("{"):
                model = json.loads(model)
            agent = client.start(
                args.root,
                name=args.name,
                mode=args.mode,
                model=model,
                manager=args.manager,
                prompts=_csv(args.prompts),
                skills=_csv(args.skills),
                message=args.message,
            )
            _print({"agent_id": agent.id, "dir": str(agent.dir), "pid": agent.pid()})
        elif cmd == "events":
            for event in client.events(args.agent_id, args.offset, follow=not args.no_follow):
                _print(event)
        elif cmd == "send":
            client.send(args.agent_id, args.text if args.text is not None else sys.stdin.read())
            _print({"ok": True})
        elif cmd in ("pause", "resume", "stop", "delete"):
            getattr(client, cmd)(args.agent_id)
            _print({"ok": True})
        elif cmd == "restart":
            agent = client.restart(args.agent_id)
            _print({"ok": True, "agent_id": agent.id, "pid": agent.pid(), "alive": agent.is_alive()})
        elif cmd == "kill":
            _print({"ok": True, "killed": client.kill(args.agent_id)})
        elif cmd == "rename":
            _print(client.rename(args.agent_id, args.name).meta)
        elif cmd == "move":
            agent = client.move(args.agent_id, args.manager)
            _print({**agent.meta, "dir": str(agent.dir)})
        elif cmd == "allow-read":
            _print(client.allow_read(args.agent_id, args.directory))
        elif cmd == "attach-nvim":
            client.attach_nvim(args.agent_id, args.pid)
            _print({"ok": True})
        elif cmd == "detach-nvim":
            client.detach_nvim(args.agent_id)
            _print({"ok": True})
        elif cmd == "lsp-result":
            client.lsp_result(args.agent_id, args.request_id, args.text if args.text is not None else sys.stdin.read())
            _print({"ok": True})
        elif cmd == "list":
            _print(client.list_agents(args.root, args.running))
        elif cmd == "models":
            _print(client.list_models(args.root))
        elif cmd == "update-cursor-models":
            _print(client.update_cursor_models())
        elif cmd == "mcp":
            _print(client.mcp_status(args.root))
    except (LookupError, ValueError, OSError) as exc:
        _print({"ok": False, "error": str(exc)})
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
