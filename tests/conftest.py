"""Shared fixtures: an isolated $HOME, the agent loaded inside it, a fake Ollama."""
import importlib.util
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def home(tmp_path, monkeypatch):
    """A fresh $HOME with ~/.config/tuxaide. Paths in agent.py are resolved at
    import time, so load the agent through the `agent` fixture after this."""
    h = tmp_path / "home"
    (h / ".config" / "tuxaide").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(h))
    for var in ("TUXAIDE_SHELL_PID", "TUXAIDE_SHELL", "TUXAIDE_LAST_CMD",
                "TUXAIDE_LAST_RC", "TUXAIDE_NAMES", "LC_ALL", "LC_MESSAGES"):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("LANG", "en_US.UTF-8")
    return h


@pytest.fixture
def agent(home):
    return load_module("tuxaide_agent", "agent.py")


def write_config(home, **values):
    path = home / ".config" / "tuxaide" / "config.json"
    path.write_text(json.dumps(values))
    return path


class FakeOllama:
    """Minimal Ollama: /api/tags, streaming /api/chat, /api/embed(dings).

    `answer` is streamed back in small chunks; `error` makes /api/chat fail
    the way Ollama does (a JSON line with "error"); every request body is kept.
    """
    def __init__(self):
        self.answer = "ok"
        self.error = None
        self.batch_embed = True
        self.requests = []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, code, payload):
                self.send_response(code)
                self.end_headers()
                if payload is not None:
                    self.wfile.write(payload)

            def do_GET(self):
                self._send(200, b'{"models":[]}')

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
                fake.requests.append((self.path, body))
                if self.path == "/api/chat":
                    self.send_response(200)
                    self.end_headers()
                    if fake.error:
                        self.wfile.write(json.dumps({"error": fake.error}).encode() + b"\n")
                        return
                    for i in range(0, len(fake.answer), 7):
                        chunk = {"message": {"content": fake.answer[i:i + 7]}}
                        self.wfile.write(json.dumps(chunk).encode() + b"\n")
                    self.wfile.write(b'{"done":true}\n')
                elif self.path == "/api/embed":
                    if not fake.batch_embed:
                        return self._send(404, None)
                    self._send(200, json.dumps({"embeddings": [[0.1, 0.2]] * len(body["input"])}).encode())
                elif self.path == "/api/embeddings":
                    self._send(200, json.dumps({"embedding": [0.1, 0.2]}).encode())
                else:
                    self._send(404, None)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def chat_requests(self):
        return [body for path, body in self.requests if path == "/api/chat"]

    def last_user_message(self):
        return self.chat_requests()[-1]["messages"][-1]["content"]

    def close(self):
        self.server.shutdown()


@pytest.fixture
def ollama():
    server = FakeOllama()
    yield server
    server.close()


@pytest.fixture
def run_agent(home, ollama):
    """Run agent.py as a subprocess against the fake Ollama; returns CompletedProcess."""
    import subprocess

    def run(*args, env=None, config=None):
        cfg = {"ollama_url": ollama.url, "model": "fake", "color": False}
        cfg.update(config or {})
        write_config(home, **cfg)
        full_env = {**os.environ, "COLUMNS": "80", **(env or {})}
        return subprocess.run([sys.executable, os.path.join(REPO, "agent.py"), *args],
                              capture_output=True, text=True, env=full_env,
                              stdin=subprocess.DEVNULL, timeout=60)
    return run
