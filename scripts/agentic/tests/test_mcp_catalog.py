from __future__ import annotations

import json
import unittest

from agentic_client.mcp_catalog import CONNECT, HTTP, INACTIVE, MISSING, SSE, UNSUPPORTED, load_catalog, parse_catalog
from agentic_client.mcp_client import connect_decision, split_mcp_call
from helpers import TempHomeCase

MCP = {
    "mcpServers": {
        "plain": {"url": "https://a.example/mcp"},
        "http": {"url": "https://b.example/mcp", "type": "http", "headers": {"X": "1"}},
        "events": {"url": "https://c.example/sse", "type": "sse"},
        "local": {"command": "npx", "args": ["thing"]},
        "off": {"url": "https://d.example/mcp"},
        "nokey": {"url": "https://e.example/mcp"},
        "absent": {"url": "https://f.example/mcp"},
    }
}
ACTIVE = {"plain": True, "http": True, "events": True, "local": True, "off": False, "ghost": True}


class CatalogTests(unittest.TestCase):
    def setUp(self):
        activation = dict(ACTIVE)
        # "nokey" has an entry without isActive: mcp_activation maps it to False.
        activation["nokey"] = False
        self.catalog = parse_catalog(json.dumps(MCP), activation)

    def server(self, name):
        return self.catalog.by_name(name)

    def test_url_and_http_connect_with_streamable_http(self):
        for name in ("plain", "http"):
            self.assertEqual(self.server(name).status, CONNECT)
            self.assertEqual(self.server(name).transport, HTTP)
        self.assertEqual(self.server("http").headers, {"X": "1"})

    def test_sse(self):
        self.assertEqual(self.server("events").status, CONNECT)
        self.assertEqual(self.server("events").transport, SSE)

    def test_command_only_unsupported(self):
        self.assertEqual(self.server("local").status, UNSUPPORTED)
        self.assertTrue(self.server("local").active)
        self.assertFalse(self.server("absent").active)
        self.assertTrue(self.server("ghost").active)
        self.assertNotIn("local", [s.name for s in self.catalog.to_connect()])

    def test_inactive_missing_or_absent_stays_off(self):
        for name in ("off", "nokey", "absent"):
            self.assertEqual(self.server(name).status, INACTIVE, name)
        self.assertEqual(self.server("ghost").status, MISSING)
        self.assertEqual({s.name for s in self.catalog.to_connect()}, {"plain", "http", "events"})

    def test_invalid_json_connects_nothing(self):
        bad = parse_catalog('{"mcpServers": {"a": {"url": "x"},}', {"a": True})
        self.assertIsNotNone(bad.error)
        self.assertEqual(bad.servers, [])
        self.assertEqual(bad.to_connect(), [])

    def test_authorization_is_generated_once_and_400_stops_after_three(self):
        auth = RuntimeError("401 Unauthorized")
        self.assertEqual(connect_decision(auth, 0, False), "authorize")
        self.assertEqual(connect_decision(auth, 0, True), "fail")
        denied = RuntimeError("HTTP 400 Bad Request")
        self.assertEqual(connect_decision(denied, 0, False), "retry")
        self.assertEqual(connect_decision(denied, 1, False), "retry")
        self.assertEqual(connect_decision(RuntimeError("status 500"), 2, False), "stop")

    def test_split_mcp_call(self):
        self.assertEqual(split_mcp_call("serena/find_symbol", {"q": 1}), ("serena", "find_symbol", {"q": 1}))
        self.assertEqual(
            split_mcp_call("serena", {"tool": "find_symbol", "arguments": {"q": 1}}), ("serena", "find_symbol", {"q": 1})
        )


class ProjectActivationTests(TempHomeCase):
    def test_reads_is_active_from_project_file(self):
        from agentic_client import project as proj

        root = self.make_project(
            "demo", {"mcp_servers": [{"name": "plain", "isActive": True}, {"name": "off"}, {"name": "http", "isActive": False}]}
        )
        (self.tmp / "mcp.json").write_text(json.dumps(MCP))
        activation = proj.mcp_activation(proj.load_project(root))
        self.assertEqual(activation, {"plain": True, "off": False, "http": False})
        catalog = load_catalog(activation)
        self.assertEqual([s.name for s in catalog.to_connect()], ["plain"])

    def test_unparseable_file_reports_error(self):
        (self.tmp / "mcp.json").write_text("{nope")
        catalog = load_catalog({"plain": True})
        self.assertIn("does not parse", catalog.error)
        self.assertEqual(catalog.to_connect(), [])
