from __future__ import annotations

import json

from agentic_client import state
from helpers import TempHomeCase, git

MODEL = {"name": "m", "vendor": "cursor", "context_limit": 200000}


class StatePathTests(TempHomeCase):
    def test_feature_branch_nests(self):
        root = self.make_project("demo")
        git(root, "init", "-q", "-b", "main")
        git(root, "commit", "-q", "--allow-empty", "-m", "init")
        git(root, "checkout", "-q", "-b", "feature/foo")
        self.assertEqual(state.git_branch(root), "feature/foo")
        self.assertEqual(state.state_dir_for_root(root), self.home / "demo" / "feature" / "foo")
        agent = state.create_agent(root, name="a", mode="ask", model=MODEL)
        self.assertEqual(agent.dir.parent, self.home / "demo" / "feature" / "foo" / "default")
        meta = json.loads((agent.dir / "meta.json").read_text())
        self.assertEqual(meta["branch"], "feature/foo")
        self.assertEqual(meta["project_root"], str(root))
        self.assertEqual(meta["manager"], "default")
        self.assertEqual(meta["agent_id"], agent.id)
        for f in ("transcript.md", "log"):
            self.assertTrue((agent.dir / f).exists())

    def test_nogit(self):
        root = self.make_project("demo")
        self.assertEqual(state.git_branch(root), "nogit")
        self.assertEqual(state.state_dir_for_root(root), self.home / "demo" / "nogit")

    def test_detached(self):
        root = self.make_project("demo")
        git(root, "init", "-q", "-b", "main")
        git(root, "commit", "-q", "--allow-empty", "-m", "init")
        git(root, "checkout", "-q", "--detach")
        self.assertEqual(state.git_branch(root), "detached")
        self.assertEqual(state.state_dir_for_root(root), self.home / "demo" / "detached")

    def test_project_name_falls_back_to_basename(self):
        root = self.make_project(None)
        self.assertEqual(state.project_name(root), "proj")


class DiscoveryTests(TempHomeCase):
    def test_discovery_is_depth_independent(self):
        root = self.make_project("demo")
        shallow = state.create_agent(root, name="s", mode="ask", model=MODEL, branch="main", manager="m")
        deep = state.create_agent(
            root, name="d", mode="ask", model=MODEL, branch="feature/a/b/c", manager="team/sub/leaf"
        )
        self.assertNotEqual(len(shallow.dir.parts), len(deep.dir.parts))
        found = {a.id: a for a in state.iter_agents()}
        self.assertEqual(set(found), {shallow.id, deep.id})
        self.assertEqual(found[deep.id].meta["manager"], "team/sub/leaf")
        self.assertEqual(state.find_agent(deep.id).dir, deep.dir)
        self.assertEqual(state.agentic_home_of(deep), self.home)

    def test_mcp_auth_is_not_scanned(self):
        (self.home / "mcp-auth" / "srv").mkdir(parents=True)
        (self.home / "mcp-auth" / "srv" / "meta.json").write_text('{"agent_id": "bogus"}')
        self.assertEqual(list(state.iter_agents()), [])

    def test_move_and_rename(self):
        root = self.make_project("demo")
        agent = state.create_agent(root, name="a", mode="ask", model=MODEL, branch="main")
        moved = state.move_agent(agent, "lead/worker")
        self.assertEqual(moved.dir.parent, self.home / "demo" / "main" / "lead" / "worker")
        self.assertEqual(state.find_agent(agent.id).meta["manager"], "lead/worker")
        state.rename_agent(moved, "renamed")
        self.assertEqual(state.find_agent(agent.id).meta["name"], "renamed")

    def test_rename_project_agent_is_one_agent_of_this_project(self):
        from agentic_client.client import rename_project_agent

        root = self.make_project("demo")
        one = state.create_agent(root, name="one", mode="ask", model=MODEL, branch="main")
        two = state.create_agent(root, name="two", mode="edit", model=MODEL, branch="main")
        other = self.tmp / "other"
        other.mkdir()
        (other / ".nvim_project.json").write_text('{"name": "other"}')
        foreign = state.create_agent(other, name="foreign", mode="ask", model=MODEL, branch="main")

        renamed = rename_project_agent(root, one.id, "alpha")
        self.assertEqual(renamed, {"ok": True, "agent_id": one.id, "name": "alpha"})
        self.assertEqual(state.find_agent(one.id).meta["name"], "alpha")
        rename_project_agent(root, "two", "beta")
        self.assertEqual(state.find_agent(two.id).meta["name"], "beta")
        with self.assertRaises(ValueError):
            rename_project_agent(root, foreign.id, "nope")
        state.rename_agent(state.find_agent(two.id), "alpha")
        with self.assertRaises(ValueError):
            rename_project_agent(root, "alpha", "gamma")
        with self.assertRaises(ValueError):
            rename_project_agent(root, one.id, "bad/name")
