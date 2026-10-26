from __future__ import annotations

import json
import socket
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from agentic_client.adapters import LocalAdapter, LocalServerNotRunning, list_local_models
from agentic_client.sse import iter_sse, iter_sse_deltas, parse_sse_line


def data(content: str) -> str:
    return "data: " + json.dumps({"choices": [{"delta": {"content": content}}]})


class SseParserTests(unittest.TestCase):
    def test_extracts_deltas_and_stops_on_done(self):
        lines = [": keepalive", "", data("Hel"), "event: x", data("lo"), "data: [DONE]", data("AFTER")]
        self.assertEqual("".join(iter_sse_deltas(lines)), "Hello")

    def test_bytes_and_crlf(self):
        self.assertEqual(parse_sse_line((data("x") + "\r\n").encode()).text, "x")
        self.assertTrue(parse_sse_line(b"data: [DONE]\r\n").done)

    def test_usage_and_error(self):
        usage = parse_sse_line('data: {"choices": [], "usage": {"total_tokens": 42}}')
        self.assertEqual(usage.usage, {"total_tokens": 42})
        err = list(iter_sse(['data: {"error": {"message": "boom"}}']))
        self.assertEqual(err[0].error, "boom")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class FakeServer:
    def __init__(self):
        self.requests = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                outer.requests.append(("GET", self.path, dict(self.headers)))
                body = json.dumps({"data": [{"id": "qwen2.5-coder:7b"}, {"id": "llama3"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                length = int(self.headers["Content-Length"])
                outer.requests.append(("POST", self.path, dict(self.headers), json.loads(self.rfile.read(length))))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                for part in ("Hi", " there"):
                    self.wfile.write((data(part) + "\n\n").encode())
                self.wfile.write(b"data: [DONE]\n\n")

            def log_message(self, *a):
                return

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base_url = f"http://127.0.0.1:{self.httpd.server_port}/v1"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


class LocalAdapterTests(unittest.TestCase):
    def setUp(self):
        self.server = FakeServer()

    def tearDown(self):
        self.server.close()

    def test_turn_and_bearer_only_with_key(self):
        events = []
        adapter = LocalAdapter("qwen2.5-coder:7b", self.server.base_url)
        result = adapter.run_turn("sys", [{"role": "user", "content": "hello"}], events.append)
        self.assertEqual(result.text, "Hi there")
        self.assertIsNone(result.error)
        method, path, headers, body = self.server.requests[-1]
        self.assertEqual(path, "/v1/chat/completions")
        self.assertEqual(body["stream"], True)
        self.assertEqual(body["model"], "qwen2.5-coder:7b")
        self.assertEqual(body["messages"][0], {"role": "system", "content": "sys"})
        self.assertNotIn("Authorization", headers)

        LocalAdapter("m", self.server.base_url, api_key="k").run_turn("", [{"role": "user", "content": "x"}], events.append)
        self.assertEqual(self.server.requests[-1][2]["Authorization"], "Bearer k")

    def test_models(self):
        self.assertEqual(list_local_models(self.server.base_url), ["qwen2.5-coder:7b", "llama3"])
        self.assertEqual(self.server.requests[-1][1], "/v1/models")


class LocalNotRunningTests(unittest.TestCase):
    def test_clear_error(self):
        url = f"http://127.0.0.1:{free_port()}/v1"
        with self.assertRaises(LocalServerNotRunning) as ctx:
            list_local_models(url)
        self.assertIn("local server is not running", str(ctx.exception))
        result = LocalAdapter("m", url).run_turn("", [{"role": "user", "content": "x"}], lambda e: None)
        self.assertIn("local server is not running", result.error)
