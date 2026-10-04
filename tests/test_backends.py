"""P9: OpenAI-compatible backend, remote indicator, API key never stored."""
import json
import os
import shutil
import subprocess

import pytest

from conftest import REPO

KEY = "sk-test-SECRET-1234567890"


def api_config(openai_api, **extra):
    return {"backend": "openai", "api_base": openai_api.base, "model": "gpt-test", **extra}


def all_files_text(home):
    out = []
    for root, _, files in os.walk(home):
        for f in files:
            try:
                out.append(open(os.path.join(root, f), errors="ignore").read())
            except OSError:
                pass
    return "\n".join(out)


# ── OpenAI-compatible backend ────────────────────────────────────────

def test_openai_backend_streams_the_answer(run_agent, openai_api, ollama):
    openai_api.answer = "Use:\n\n```bash\nss -tuln\n```\n"
    r = run_agent("--ask", "how do I check open ports", config=api_config(openai_api))
    assert "ss -tuln" in r.stdout
    assert "TuxAide (API · gpt-test)" in r.stdout              # local server: no ☁
    headers, body = openai_api.chats()[-1]
    assert body["model"] == "gpt-test" and body["stream"] is True
    assert body["messages"][0]["role"] == "system" and body["messages"][-1]["content"] == "how do I check open ports"
    assert not ollama.chat_requests()                          # Ollama isn't asked


def test_api_key_comes_from_the_environment_and_is_never_written(home, run_agent, openai_api):
    r = run_agent("--ask", "how do I list files", config=api_config(openai_api), env={"OPENAI_API_KEY": KEY})
    assert r.returncode == 0
    headers, _ = openai_api.chats()[-1]
    assert headers.get("Authorization") == f"Bearer {KEY}"
    assert KEY not in all_files_text(home)                     # config, cache, history, perf.log


def test_api_key_env_name_is_configurable(run_agent, openai_api):
    run_agent("--ask", "how do I list files", config=api_config(openai_api, api_key_env="MY_KEY"),
              env={"MY_KEY": KEY})
    assert openai_api.chats()[-1][0].get("Authorization") == f"Bearer {KEY}"


def test_no_key_no_authorization_header(run_agent, openai_api):
    run_agent("--ask", "how do I list files", config=api_config(openai_api))
    assert "Authorization" not in openai_api.chats()[-1][0]


def test_rejected_key_is_explained_and_scrubbed(home, run_agent, openai_api):
    openai_api.status = 401
    r = run_agent("--ask", "how do I list files", config=api_config(openai_api), env={"OPENAI_API_KEY": KEY})
    assert "refused the key" in r.stdout and "$OPENAI_API_KEY" in r.stdout
    assert KEY not in r.stdout and KEY not in r.stderr
    assert KEY not in all_files_text(home)


def test_api_down(run_agent):
    r = run_agent("--ask", "how do I list files",
                  config={"backend": "openai", "api_base": "http://127.0.0.1:9/v1", "model": "x"})
    assert "model API isn't answering" in r.stdout


def test_api_base_missing(run_agent):
    r = run_agent("--ask", "how do I list files", config={"backend": "openai", "model": "x"})
    assert "tuxaide config set api_base" in r.stdout


def test_cache_is_per_backend(agent):
    a = agent.answer_cache_key("q", {"model": "m", "system_context": False})
    b = agent.answer_cache_key("q", {"model": "m", "system_context": False, "backend": "openai",
                                     "api_base": "http://x/v1"})
    assert a != b


# ── settings ─────────────────────────────────────────────────────────

@pytest.mark.parametrize("key", ["api_key", "API_KEY", "token", "openai_api_key"])
def test_api_key_cannot_be_stored(home, run_agent, key):
    r = run_agent("config", "set", key, KEY)
    assert r.returncode == 2 and "never stores API keys" in r.stdout
    assert KEY not in all_files_text(home)


def test_backend_settings(home, run_agent):
    r = run_agent("config", "set", "backend", "openai")
    assert r.returncode == 0 and "tuxaide config set api_base" in r.stdout
    assert run_agent("config", "set", "backend", "cloud").returncode == 2
    assert run_agent("config", "set", "api_key_env", "not a name").returncode == 2
    r = run_agent("config", "set", "ollama_url", "http://192.168.1.10:11434")
    assert "☁ Questions will be sent to 192.168.1.10" in r.stdout


# ── the ☁ remote indicator ───────────────────────────────────────────

@pytest.mark.parametrize("cfg, remote", [
    ({"ollama_url": "http://localhost:11434"}, False),
    ({"ollama_url": "http://127.0.0.1:11434"}, False),
    ({"ollama_url": "http://[::1]:11434"}, False),
    ({"ollama_url": "http://192.168.1.10:11434"}, True),
    ({"backend": "openai", "api_base": "http://localhost:1234/v1"}, False),
    ({"backend": "openai", "api_base": "https://api.example.com/v1"}, True),
    # RAG embeddings go to Ollama even with an API backend
    ({"backend": "openai", "api_base": "http://localhost:1234/v1", "mode": "smart",
      "ollama_url": "http://192.168.1.10:11434"}, True),
    ({"backend": "openai", "api_base": "http://localhost:1234/v1", "mode": "llm",
      "ollama_url": "http://192.168.1.10:11434"}, False),
])
def test_is_remote(agent, cfg, remote):
    assert agent.is_remote(cfg) is remote
    assert ("☁" in agent.backend_label(cfg)) is remote


def test_remote_answer_shows_the_indicator_before_and_during(agent, openai_api, monkeypatch, capsys):
    """Every request to a remote backend is preceded by a visible ☁ (spinner) and
    the answer box says where it came from."""
    monkeypatch.setattr(agent, "is_loopback", lambda host: False)     # pretend 127.0.0.1 is far away
    c = {**agent.DEFAULTS, **api_config(openai_api), "color": False}
    seen_at_request = []
    real = agent.stream_openai

    def watch(*a, **k):
        seen_at_request.append(capsys.readouterr().err)       # what was on screen when the request left
        yield from real(*a, **k)
    monkeypatch.setattr(agent, "stream_openai", watch)
    agent.answer_streaming("how do I list files", c, None, "llm", agent.thinking(c))
    assert "☁ Asking 127.0.0.1" in seen_at_request[0]
    assert "TuxAide (☁ remote · 127.0.0.1 · gpt-test)" in capsys.readouterr().out


def test_status_warns_when_remote(run_agent):
    r = run_agent("status", config={"ollama_url": "http://192.0.2.1:11434"})
    assert "☁ remote · 192.0.2.1" in r.stdout and "sent to 192.0.2.1" in r.stdout
    r = run_agent("status")
    assert "☁" not in r.stdout and "Status: ACTIVE" in r.stdout
    assert "INACTIVE" in run_agent("status", config={"enabled": False}).stdout


def _hook_prewarm_calls(home, shell, config):
    """Source the hook with prewarm=always and a fake curl; return what curl was asked."""
    fake = home / "fakebin"
    fake.mkdir(exist_ok=True)
    (fake / "curl").write_text(f"#!/bin/sh\necho \"$@\" >> '{home}/curl.log'\n")
    (fake / "curl").chmod(0o755)
    (home / ".config" / "tuxaide" / "config.json").write_text(json.dumps({"prewarm": "always", **config}))
    env = {"HOME": str(home), "PATH": f"{fake}:/usr/bin:/bin", "TMPDIR": str(home)}
    subprocess.run([shell, "-c", f". '{REPO}/hook.sh'; sleep 3"], env=env, timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log = home / "curl.log"
    return log.read_text() if log.exists() else ""


@pytest.mark.parametrize("shell", [s for s in ("zsh", "bash") if shutil.which(s)])
def test_prewarm_never_reaches_a_remote_backend(home, shell):
    assert "localhost:11434/api/generate" in _hook_prewarm_calls(home, shell, {})
    (home / "curl.log").unlink()
    assert _hook_prewarm_calls(home, shell, {"ollama_url": "http://192.168.1.10:11434"}) == ""
    assert _hook_prewarm_calls(home, shell, {"backend": "openai", "api_base": "http://localhost:1234/v1"}) == ""


# ── model and doctor with the API backend ────────────────────────────

def test_model_lists_and_switches_api_models(home, run_agent, openai_api):
    openai_api.models = ["gpt-test", "gpt-other"]
    out = run_agent("model", config=api_config(openai_api)).stdout
    assert "* gpt-test" in out and "  gpt-other" in out
    assert run_agent("model", "gpt-other", config=api_config(openai_api)).returncode == 0
    r = run_agent("model", "nope", config=api_config(openai_api))
    assert r.returncode == 1 and "doesn't offer nope" in r.stdout


@pytest.fixture
def shell_ok(home):
    (home / ".config" / "tuxaide" / "hook.sh").write_text("# hook\n")
    (home / ".zshrc").write_text('source "$HOME/.config/tuxaide/hook.sh"  # TuxAide\n')
    return {"TUXAIDE_SHELL_PID": "1", "TUXAIDE_SHELL": "zsh", "TUXAIDE_HANDLER": "ours",
            "PATH": f"{home}/.local/bin{os.pathsep}{os.environ['PATH']}"}


def test_doctor_api_backend(run_agent, openai_api, shell_ok):
    r = run_agent("doctor", config=api_config(openai_api), env=shell_ok)
    assert r.returncode == 0, r.stdout
    assert "API answering" in r.stdout and "Model gpt-test offered" in r.stdout
    assert "No API key" in r.stdout and "☁" not in r.stdout      # local server, no key needed
    r = run_agent("doctor", config=api_config(openai_api, model="missing"), env=shell_ok)
    assert r.returncode == 1 and "doesn't offer model missing" in r.stdout


def test_doctor_remote_api_needs_a_key(run_agent, openai_api, shell_ok, agent):
    r = run_agent("doctor", config={"backend": "openai", "api_base": "http://192.0.2.1:9/v1", "model": "x"},
                  env=shell_ok)
    assert r.returncode == 1 and "No API key" in r.stdout and "export OPENAI_API_KEY" in r.stdout
    assert "☁ Questions are sent to 192.0.2.1" in r.stdout


def test_doctor_flags_a_key_in_the_config_file(run_agent, openai_api, shell_ok, home):
    r = run_agent("doctor", config=api_config(openai_api, api_key="sk-oops"), env=shell_ok)
    assert r.returncode == 1 and 'contains "api_key"' in r.stdout


def test_doctor_api_without_address(run_agent, shell_ok):
    r = run_agent("doctor", config={"backend": "openai"}, env=shell_ok)
    assert r.returncode == 1 and "no API address" in r.stdout
