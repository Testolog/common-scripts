from __future__ import annotations

import json
import os

from agentic_client import state
from agentic_client.context import at_limit, estimate_tokens, handoff, open_tasks, update_tokens
from helpers import TempHomeCase

MODEL = {"name": "m", "vendor": "cursor", "context_limit": 100}


class HandoffTests(TempHomeCase):
    def test_tokens_prefer_usage_then_estimate(self):
        root = self.make_project()
        agent = state.create_agent(root, name="a", mode="ask", model=MODEL, branch="main")
        self.assertEqual(update_tokens(agent, {"prompt_tokens": 10, "completion_tokens": 5}, "x" * 4000), 15)
        self.assertEqual(agent.meta["tokens_source"], "usage")
        self.assertEqual(update_tokens(agent, None, "x" * 400), estimate_tokens("x" * 400))
        self.assertEqual(agent.meta["tokens_source"], "estimate")
        self.assertTrue(at_limit(agent))

    def test_open_tasks(self):
        text = "- [ ] one\n- [x] two\n* [ ] three\n- [X] one\n- [ ] four\n"
        self.assertEqual(open_tasks(text), ["three", "four"])

    def test_handoff_creates_child_and_freezes_parent(self):
        root = self.make_project()
        parent = state.create_agent(root, name="worker", mode="edit", model=MODEL, branch="feature/foo", manager="lead")
        state.append_transcript(parent, "## Assistant\n\n- [ ] write tests\n- [x] read docs\n" + "y" * 500)
        update_tokens(parent, None, parent.path("transcript.md").read_text())
        parent.save()
        self.assertTrue(at_limit(parent))

        child = handoff(parent)

        self.assertEqual(child.manager_dir, parent.manager_dir)
        self.assertEqual(child.meta["parent"], parent.id)
        self.assertEqual(child.meta["manager"], "lead")
        self.assertEqual(child.meta["branch"], "feature/foo")
        self.assertIn("- [ ] write tests", child.meta["preamble"])
        self.assertNotIn("read docs\n- [ ]", child.meta["preamble"])
        self.assertIn("Handoff summary", child.meta["preamble"])
        summary = parent.manager_dir / f"handoff-{parent.id}.md"
        self.assertTrue(summary.is_file())

        reloaded = state.find_agent(parent.id)
        self.assertTrue(reloaded.meta["read_only"])
        self.assertEqual(reloaded.meta["handoff_to"], child.id)
        self.assertIn(child.id, reloaded.meta["children"])
        self.assertFalse(os.access(parent.path("transcript.md"), os.W_OK))
        with self.assertRaises(PermissionError):
            state.append_transcript(reloaded, "more")

        events = [json.loads(l) for l in parent.path("events.jsonl").read_text().splitlines()]
        tree = [e for e in events if e["type"] == "tree"]
        self.assertEqual(len(tree), 1)
        self.assertEqual(tree[0]["action"], "handoff")
        self.assertEqual(tree[0]["child_id"], child.id)
        self.assertIs(tree[0]["switch_buffer"], False)
        self.assertFalse(any(e["type"] in ("switch", "open_buffer") for e in events))

        self.assertEqual({a.id for a in state.iter_agents()}, {parent.id, child.id})
        self.assertFalse(child.is_alive())
