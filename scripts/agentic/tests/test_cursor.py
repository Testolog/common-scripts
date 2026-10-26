from __future__ import annotations

import json
import os
import sys
import threading
import time
from pathlib import Path

from agentic_client.adapters.cursor import cursor_mcp_outcome
from agentic_client.adapters import (
    CursorAdapter,
    absorb_delta,
    choose_turn_text,
    cursor_command,
    load_cursor_catalog,
    parse_model_listing,
    update_cursor_catalog,
)
from helpers import TempHomeCase

FAKE_AGENT = """#!{python}
import json, sys, time
print(json.dumps({{"type": "system", "subtype": "init", "session_id": "chat-1", "model": "fake"}}), flush=True)
time.sleep(0.3)
print(json.dumps({{"type": "assistant", "message": {{"content": [{{"type": "text", "text": "Hel"}}]}}}}), flush=True)
print(json.dumps({{"type": "assistant", "message": {{"content": [{{"type": "text", "text": "lo"}}]}}}}), flush=True)
print(json.dumps({{"type": "result", "subtype": "success", "result": "Hello", "usage": {{"total_tokens": 7}}}}), flush=True)
open(sys.argv[0] + ".argv", "w").write(json.dumps(sys.argv[1:]))
"""

# SIGKILLs itself before any output for the first `kills` runs, then behaves like FAKE_AGENT.
KILLED_AGENT = """#!{python}
import json, os, signal, sys
marker = sys.argv[0] + ".runs"
runs = int(open(marker).read()) if os.path.exists(marker) else 0
open(marker, "w").write(str(runs + 1))
if runs < {kills}:
    os.kill(os.getpid(), signal.SIGKILL)
print(json.dumps({{"type": "result", "subtype": "success", "result": "Hello"}}), flush=True)
"""


class CursorTests(TempHomeCase):
    def fake_binary(self) -> Path:
        path = self.tmp / "agent"
        path.write_text(FAKE_AGENT.format(python=sys.executable))
        path.chmod(0o755)
        return path

    def test_repeated_snapshot_is_not_appended(self):
        stored, delta = absorb_delta("Hello", " world")
        self.assertEqual((stored, delta), ("Hello world", " world"))
        again, skipped = absorb_delta(stored, "The root pom is updated. " * 5)
        self.assertEqual(again, stored + "The root pom is updated. " * 5)
        dup, skipped = absorb_delta(again, "The root pom is updated. " * 5)
        self.assertEqual(dup, again)
        self.assertEqual(skipped, "")
        self.assertEqual(choose_turn_text("done", "done done done"), "done")

    def test_command_flags(self):
        ask = cursor_command("hi", model="sonnet-4", workspace=Path("/p"), mode="ask", binary="agent")
        self.assertEqual(
            ask,
            ["agent", "-p", "--output-format", "stream-json", "--stream-partial-output", "--trust", "--approve-mcps",
             "--workspace", "/p", "--sandbox", "enabled", "--model", "sonnet-4", "--mode", "ask", "hi"],
        )
        edit = cursor_command("hi", model="auto", workspace=Path("/p"), mode="edit", session_id="c1", binary="agent")
        self.assertIn("--force", edit)
        self.assertNotIn("--model", edit)
        self.assertEqual(edit[-3:], ["--resume", "c1", "hi"])
        auto = cursor_command(
            "hi", model="auto-smart[optimize_for=cost]", workspace=Path("/p"), mode="ask", binary="agent"
        )
        self.assertIn("auto-smart[optimize_for=cost]", auto)

    def test_model_listing_parser(self):
        out = (
            "Available models\n\n"
            "auto-smart - Auto (current, default)\n"
            "composer-2.5 - Composer 2.5\n"
            "gpt-5.5 - GPT-5.5\n"
            "\x1b[32mclaude-opus-4-8\x1b[0m - Opus 4.8\n"
            "Tip: use --model <id>\n"
        )
        listed = parse_model_listing(out)
        self.assertEqual(
            [m["label"] for m in listed[:3]],
            ["Auto Balance", "Auto Intelligence", "Auto Cost"],
        )
        self.assertEqual(
            [m["id"] for m in listed[:3]],
            [
                "auto-smart[optimize_for=balanced]",
                "auto-smart[optimize_for=intelligence]",
                "auto-smart[optimize_for=cost]",
            ],
        )
        self.assertEqual(
            [(m["id"], m["label"]) for m in listed[3:]],
            [("composer-2.5", "Composer 2.5"), ("gpt-5.5", "GPT-5.5"), ("claude-opus-4-8", "Opus 4.8")],
        )

    def test_stream_pause_resume(self):
        binary = self.fake_binary()
        adapter = CursorAdapter("fake", self.tmp, "ask", binary=str(binary))
        events, result = [], {}
        adapter.pause()
        worker = threading.Thread(target=lambda: result.update(r=adapter.run_turn("sys", [{"role": "user", "content": "q"}], events.append)))
        worker.start()
        time.sleep(0.6)
        self.assertEqual(events, [])
        self.assertTrue(worker.is_alive())
        adapter.resume()
        worker.join(10)
        r = result["r"]
        self.assertEqual(r.text, "Hello")
        self.assertIsNone(r.error)
        self.assertEqual(r.usage, {"total_tokens": 7})
        self.assertEqual("".join(e["text"] for e in events if e["type"] == "delta"), "Hello")
        self.assertEqual(adapter.session_id, "chat-1")
        argv = (binary.parent / "agent.argv").read_text()
        self.assertIn('"--mode", "ask"', argv)

        adapter.run_turn("sys", [{"role": "user", "content": "q"}, {"role": "user", "content": "next"}], events.append)
        argv = (binary.parent / "agent.argv").read_text()
        self.assertIn('"--resume", "chat-1", "next"', argv)

    def test_stop_ends_process(self):
        binary = self.fake_binary()
        adapter = CursorAdapter("fake", self.tmp, "edit", binary=str(binary))
        result = {}
        worker = threading.Thread(target=lambda: result.update(r=adapter.run_turn("", [{"role": "user", "content": "q"}], lambda e: None)))
        worker.start()
        time.sleep(0.1)
        adapter.stop()
        worker.join(10)
        self.assertTrue(result["r"].aborted)
        self.assertIsNone(adapter._proc)

    def killed_binary(self, kills: int) -> Path:
        path = self.tmp / "agent"
        path.write_text(KILLED_AGENT.format(python=sys.executable, kills=kills))
        path.chmod(0o755)
        return path

    def test_early_sigkill_retries_once(self):
        binary = self.killed_binary(1)
        adapter = CursorAdapter("fake", self.tmp, "ask", binary=str(binary))
        events = []
        r = adapter.run_turn("", [{"role": "user", "content": "q"}], events.append)
        self.assertIsNone(r.error)
        self.assertEqual(r.text, "Hello")
        self.assertEqual((binary.parent / "agent.runs").read_text(), "2")
        self.assertTrue(any(e["type"] == "log" and "retrying" in e["text"] for e in events))

    def test_repeated_early_sigkill_reports_error(self):
        binary = self.killed_binary(5)
        adapter = CursorAdapter("fake", self.tmp, "ask", binary=str(binary))
        r = adapter.run_turn("", [{"role": "user", "content": "q"}], lambda e: None)
        self.assertIn("SIGKILL", r.error)
        self.assertEqual((binary.parent / "agent.runs").read_text(), "2")

    def test_catalog_load_does_not_run_the_cli(self):
        common = self.tmp / "common"
        (common / "system_project").mkdir(parents=True)
        previous = os.environ.get("COMMON_SCRIPT")
        os.environ["COMMON_SCRIPT"] = str(common)
        os.environ["AGENTIC_CURSOR_BIN"] = str(self.tmp / "missing-agent")
        try:
            stored = [{"id": "gpt-test", "label": "GPT Test"}]
            (common / "system_project" / "cursor_models.json").write_text(json.dumps({"models": stored}))
            self.assertEqual(load_cursor_catalog(), stored)
        finally:
            os.environ.pop("AGENTIC_CURSOR_BIN", None)
            if previous is None:
                os.environ.pop("COMMON_SCRIPT", None)
            else:
                os.environ["COMMON_SCRIPT"] = previous

    def test_update_writes_the_system_project_catalog(self):
        binary = self.tmp / "agent"
        binary.write_text(
            "#!" + sys.executable + "\nimport sys\n"
            "print('auto - Auto')\nprint('composer-2.5 - Composer 2.5')\n"
        )
        binary.chmod(0o755)
        common = self.tmp / "common"
        previous = os.environ.get("COMMON_SCRIPT")
        os.environ["COMMON_SCRIPT"] = str(common)
        try:
            written = update_cursor_catalog(binary=str(binary))
            saved = json.loads((common / "system_project" / "cursor_models.json").read_text())
            self.assertEqual(written["models"], saved["models"])
            self.assertEqual(saved["models"][3]["id"], "composer-2.5")
            self.assertEqual(load_cursor_catalog()[3]["label"], "Composer 2.5")
        finally:
            if previous is None:
                os.environ.pop("COMMON_SCRIPT", None)
            else:
                os.environ["COMMON_SCRIPT"] = previous

    def test_mcp_auth_and_http_outcomes(self):
        auth = {
            "getMcpToolsToolCall": {
                "args": {"server": "playtika-sandbox-flink-prod"},
                "result": {"success": {"content": '{"namespaceStatus": "needsAuth"}'}},
            }
        }
        self.assertEqual(cursor_mcp_outcome(auth), ("playtika-sandbox-flink-prod", "auth"))
        http = {
            "getMcpToolsToolCall": {
                "args": {"server": "plain"},
                "result": {"error": {"error": "HTTP status 500"}},
            }
        }
        self.assertEqual(cursor_mcp_outcome(http), ("plain", "http"))
        stopped = []
        adapter = CursorAdapter("fake", self.tmp, "ask", binary="agent")
        adapter.stop = lambda: stopped.append(True)
        state = {"text": ""}
        adapter._mcp_guard(auth, state)
        self.assertTrue(stopped)
        self.assertEqual(state.get("continue_after_auth"), "playtika-sandbox-flink-prod")
        self.assertIn("Continue the task and use its tools now", state["text"])
