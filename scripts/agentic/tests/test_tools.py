from __future__ import annotations

import unittest
from pathlib import Path

from agentic_client import project as proj
from agentic_client.tools import NO_LSP_ATTACHED, ToolRunner, build_shell_command, fsearch_args, sd_args, tool_allowed
from helpers import TempHomeCase

DATA = {
    "system_tools": [
        {"name": "fsearch", "function": "echo fsearch", "description": "search", "kind": "shell", "mutates": False},
        {"name": "sd", "function": "echo sd", "description": "edit", "mutates": True},
        {"name": "lsp_hover", "function": "lua_ls", "description": "hover", "kind": "lsp", "mutates": False},
    ],
    "project_tools": [
        {"name": "touchy", "function": "echo touchy", "description": "omits mutates"},
        {"name": "where", "function": "pwd", "description": "cwd", "mutates": False},
    ],
}


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.tools = {t.name: t for t in proj.tools(DATA)}

    def test_kind_and_mutates_defaults(self):
        self.assertEqual(self.tools["touchy"].kind, "shell")
        self.assertIsNone(self.tools["touchy"].mutates)
        self.assertTrue(self.tools["touchy"].is_mutating)

    def test_agent_create_is_always_available_in_ask(self):
        tool = self.tools["agent_create"]
        self.assertFalse(tool.is_mutating)
        self.assertTrue(tool_allowed(tool, "ask"))
        again = proj.tools({"system_tools": [{"name": "agent_create", "function": "echo kept", "mutates": False}]})
        matches = [t for t in again if t.name == "agent_create"]
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].function, "echo kept")

    def test_agent_rename_is_always_available_in_ask(self):
        tool = self.tools["agent_rename"]
        self.assertFalse(tool.is_mutating)
        self.assertTrue(tool_allowed(tool, "ask"))
        self.assertIn("agent_rename.sh", tool.function)
        again = proj.tools({"system_tools": [{"name": "agent_rename", "function": "echo kept", "mutates": False}]})
        matches = [t for t in again if t.name == "agent_rename"]
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].function, "echo kept")
        from agentic_client.tools import normalize_args

        self.assertEqual(
            normalize_args(tool, {"agent": "abc", "name": "New name"}),
            ["--agent", "abc", "--name", "New name"],
        )

    def test_ask_refuses_mutating_and_omitted(self):
        runner = ToolRunner(self.tools.values(), "ask", Path("/"))
        for name in ("sd", "touchy"):
            res = runner.call(name, ["a"])
            self.assertTrue(res.refused, name)
            self.assertIn("Refused", res.text)
            self.assertIn("Ask mode", res.text)
        self.assertFalse(tool_allowed(self.tools["sd"], "ask"))
        self.assertFalse(tool_allowed(self.tools["touchy"], "ask"))
        self.assertTrue(runner.call("fsearch", ["x"]).ok)

    def test_edit_allows_both(self):
        runner = ToolRunner(self.tools.values(), "edit", Path("/"))
        res = runner.call("sd", ["f", "old text", "new"])
        self.assertTrue(res.ok)
        self.assertEqual(res.text, "sd f old text new")
        self.assertEqual(runner.call("touchy", []).text, "touchy")

    def test_lsp_without_neovim(self):
        runner = ToolRunner(self.tools.values(), "ask", Path("/"))
        self.assertEqual(runner.call("lsp_hover", ["file.lua", "3", "4"]).text, NO_LSP_ATTACHED)

    def test_lsp_callback_receives_name_and_args(self):
        seen = {}

        def lsp(tool, args):
            seen["tool"], seen["args"] = tool.function, args
            return "hover text"

        runner = ToolRunner(self.tools.values(), "ask", Path("/"), lsp=lsp)
        self.assertEqual(runner.call("lsp_hover", ["f.lua", "1"]).text, "hover text")
        self.assertEqual(seen, {"tool": "lua_ls", "args": ["f.lua", "1"]})


class SandboxTests(TempHomeCase):
    def test_paths_stay_inside_the_project_root(self):
        root = self.make_project()
        outside = self.tmp / "other"
        outside.mkdir()
        (root / "src").mkdir()
        runner = ToolRunner(proj.tools(DATA), "edit", root)
        self.assertIn("Refused", runner.call("sd", ["../other/x", "a", "b"]).text)
        self.assertIn("Refused", runner.call("sd", [str(outside / "x"), "a", "b"]).text)
        self.assertTrue(runner.call("sd", ["src/A.java", "a", "b"]).ok)
        self.assertIn("Refused", runner.call("lsp_hover", ["/etc/passwd:1:1"]).text)

    def test_branch_logs_are_readable_and_not_writable(self):
        root = self.make_project()
        logs = self.tmp / "logs" / "feature" / "foo"
        (logs / "other-manager").mkdir(parents=True)
        runner = ToolRunner(proj.tools(DATA), "edit", root, read_roots=lambda: [root, logs])
        self.assertTrue(runner.call("fsearch", ["pattern", str(logs / "other-manager")]).ok)
        self.assertIn("Refused", runner.call("sd", [str(logs / "other-manager" / "note"), "a", "b"]).text)

    def test_a_user_granted_folder_is_readable(self):
        root = self.make_project()
        granted = self.tmp / "notes"
        granted.mkdir()
        runner = ToolRunner(proj.tools(DATA), "ask", root, read_roots=lambda: [root, granted])
        self.assertTrue(runner.call("fsearch", [str(granted)]).ok)
        self.assertIn("Refused", runner.call("fsearch", [str(self.tmp / "missing-grant")]).text)


class ToolBlockTests(unittest.TestCase):
    def test_tool_block_pattern(self):
        from agentic_client.supervisor import TOOL_BLOCK, pending_tool_calls

        text = 'Let me look.\n```tool\n{"name": "fsearch", "arguments": {"pattern": "x"}}\n```\n'
        self.assertEqual(TOOL_BLOCK.findall(text), ['{"name": "fsearch", "arguments": {"pattern": "x"}}'])
        self.assertEqual(pending_tool_calls(text), ['{"name": "fsearch", "arguments": {"pattern": "x"}}'])
        finished = text + "\nDone. The file is updated.\n"
        self.assertEqual(pending_tool_calls(finished), [])


class ShellTests(TempHomeCase):
    def test_shell_runs_in_project_root(self):
        root = self.make_project()
        runner = ToolRunner(proj.tools(DATA), "ask", root)
        self.assertEqual(Path(runner.call("where").text).resolve(), root)

    def test_args_are_quoted_and_appended(self):
        self.assertEqual(build_shell_command("$X/sd", ["a b", "it's"]), "$X/sd 'a b' 'it'\"'\"'s'")

    def test_fsearch_shapes(self):
        self.assertEqual(fsearch_args("foo", ["src", "lib"]), ["find", "foo", "src", "lib"])
        self.assertEqual(fsearch_args("foo"), ["find", "foo"])
        self.assertEqual(fsearch_args("foo", content=True), ["find", "foo", "-f"])
        runner = ToolRunner(proj.tools(DATA), "ask", self.tmp)
        self.assertEqual(runner.call("fsearch", {"pattern": "x", "content": True}).text, "fsearch find x -f")

    def test_sd_args(self):
        self.assertEqual(sd_args("a.txt", "old", "new"), ["a.txt", "old", "new"])
        with self.assertRaises(ValueError):
            sd_args("a.txt", "", "new")


class PromptResolutionTests(TempHomeCase):
    def test_order_and_path_resolution(self):
        common = self.tmp / "common"
        (common / "prompts").mkdir(parents=True)
        (common / "prompts" / "base.md").write_text("BASE")
        (common / "skills" / "base").mkdir(parents=True)
        (common / "skills" / "base" / "SKILL.md").write_text("SKILL")
        root = self.make_project(
            "demo",
            {
                "system_prompt": [{"name": "base", "path": str(common / "prompts" / "base.md")}],
                "project_prompt": [{"name": "mine", "path": "docs/mine.md"}],
                "system_skills": [{"name": "base", "path": str(common / "skills" / "base")}],
                "project_skills": [],
            },
        )
        (root / "docs").mkdir()
        (root / "docs" / "mine.md").write_text("MINE")
        data = proj.load_project(root)
        entries = proj.prompt_entries(data, root)
        self.assertEqual([e.name for e in entries], ["base", "mine"])
        self.assertEqual(entries[0].path, common / "prompts" / "base.md")
        self.assertEqual(entries[1].path, root / "docs" / "mine.md")
        text = proj.build_system_preamble(root, data, None, None)
        self.assertLess(text.index("BASE"), text.index("MINE"))
        self.assertLess(text.index("MINE"), text.index("SKILL"))
        self.assertNotIn("MINE", proj.build_system_preamble(root, data, ["base"], None))

    def test_model_rules(self):
        with self.assertRaises(proj.ProjectError):
            proj.parse_model({"name": "q", "vendor": "openai", "context_limit": 1})
        cursor = proj.parse_model({"name": "c", "vendor": "cursor", "base_url": "http://x"})
        self.assertIsNone(cursor.base_url)
        self.assertEqual(cursor.context_limit, 200000)
