from __future__ import annotations

import os
import time

import agentic_client as client
from agentic_client import state
from helpers import TempHomeCase
from test_sse_local import FakeServer


def wait_for(predicate, timeout=15.0, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        value = predicate()
        if value:
            return value
        time.sleep(step)
    raise AssertionError("timed out")


class SupervisorTests(TempHomeCase):
    def setUp(self):
        super().setUp()
        self.server = FakeServer()
        self.root = self.make_project(
            "demo",
            {"models": [{"name": "qwen", "vendor": "openai", "context_limit": 32768, "base_url": self.server.base_url}]},
        )

    def tearDown(self):
        for agent in state.iter_agents():
            state.kill_agent(agent)
        self.server.close()
        super().tearDown()

    def statuses(self, agent_id):
        return [e.get("status") for e in client.events(agent_id, follow=False) if e["type"] == "status"]

    def test_detached_turn_stop_and_reattach(self):
        agent = client.start(self.root, name="w", mode="ask", model="qwen", message="hello")
        pid = wait_for(agent.pid)
        self.assertTrue(state.pid_alive(pid))
        self.assertEqual(os.getsid(pid), pid, "supervisor must lead its own session")
        self.assertNotEqual(os.getpgid(pid), os.getpgid(0))

        wait_for(lambda: "idle" in self.statuses(agent.id)[1:])
        transcript = agent.path("transcript.md").read_text()
        self.assertIn("## User\n\nhello", transcript)
        self.assertIn("## Assistant\n\nHi there", transcript)

        again = client.attach(agent.id)
        self.assertEqual(again.dir, agent.dir)
        self.assertTrue(again.is_alive())
        self.assertGreater(again.meta["tokens"], 0)

        client.stop(agent.id)
        wait_for(lambda: not state.pid_alive(pid))
        self.assertEqual(client.attach(agent.id).meta["status"], "stopped")
        self.assertTrue(agent.path("transcript.md").exists())

    def test_restart_runs_an_existing_stopped_agent(self):
        agent = client.start(self.root, name="again", mode="ask", model="qwen", message="hello")
        pid = wait_for(agent.pid)
        wait_for(lambda: "idle" in self.statuses(agent.id)[1:])
        client.stop(agent.id)
        wait_for(lambda: not state.pid_alive(pid))
        started = client.restart(agent.id)
        new_pid = wait_for(started.pid)
        self.assertNotEqual(new_pid, pid)
        self.assertTrue(state.pid_alive(new_pid))
        same = client.restart(agent.id)
        self.assertEqual(same.pid(), new_pid)
        client.send(agent.id, "second")
        wait_for(lambda: "second" in client.attach(agent.id).path("transcript.md").read_text())

    def test_pause_resume_resends_transcript(self):
        agent = client.start(self.root, name="p", mode="ask", model="qwen", message="first")
        wait_for(lambda: "idle" in self.statuses(agent.id)[1:])
        posts_before = sum(1 for r in self.server.requests if r[0] == "POST")
        client.pause(agent.id)
        client.resume(agent.id)
        wait_for(lambda: sum(1 for r in self.server.requests if r[0] == "POST") > posts_before)
        last = self.server.requests[-1][3]["messages"]
        self.assertEqual([m["role"] for m in last[1:]], ["user", "assistant"])
        self.assertEqual(last[1]["content"], "first")

    def test_kill_keeps_transcript(self):
        agent = client.start(self.root, name="k", mode="edit", model="qwen")
        pid = wait_for(agent.pid)
        wait_for(lambda: "idle" in self.statuses(agent.id))
        self.assertTrue(client.kill(agent.id))
        wait_for(lambda: not state.pid_alive(pid))
        self.assertTrue(agent.path("transcript.md").exists())
        self.assertEqual(client.list_agents(self.root, running_only=True), [])
        self.assertEqual(len(client.list_agents(self.root)), 1)
        client.delete(agent.id)
        self.assertEqual(client.list_agents(self.root), [])
