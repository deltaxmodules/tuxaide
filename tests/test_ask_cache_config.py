import json
import os
import subprocess
import sys
import time

from conftest import REPO, write_config


def answers_cached(home):
    d = home / ".config" / "tuxaide" / "cache" / "answers"
    return sorted(d.iterdir()) if d.exists() else []


def test_answer_is_streamed_and_cached(run_agent, ollama, home):
    ollama.answer = "Use:\n\n```bash\nls -laSh\n```\n"
    p = run_agent("--ask", "how do I list hidden files")
    assert "ls -laSh" in p.stdout
    assert len(answers_cached(home)) == 1
    assert ollama.chat_requests()[-1]["keep_alive"] == "10m"

    ollama.answer = "something else"
    p = run_agent("--ask", "How do I list hidden files?")     # normalised: same question
    assert "ls -laSh" in p.stdout                             # served from cache
    assert len(ollama.chat_requests()) == 1


def test_errors_are_never_cached(run_agent, ollama, home):
    ollama.error = "model 'fake' not found"
    p = run_agent("--ask", "how do I list hidden files")
    assert "[Error] model 'fake' not found" in p.stdout
    assert answers_cached(home) == []

    ollama.error = None
    ollama.answer = "fine now"
    p = run_agent("--ask", "how do I list hidden files")
    assert "fine now" in p.stdout


def test_cache_key_depends_on_model(agent):
    a = agent.answer_cache_key("q", {"model": "m1", "mode": "llm"})
    assert a != agent.answer_cache_key("q", {"model": "m2", "mode": "llm"})
    assert a != agent.answer_cache_key("q", {"model": "m1", "mode": "smart"})


def test_old_cache_entries_expire(agent, home):
    agent.cache_set("answers", "k", {"answer": "old"})
    path = os.path.join(agent.CACHE_DIR, "answers", "k.json")
    past = time.time() - 31 * 86400
    os.utime(path, (past, past))
    assert agent.cache_get("answers", "k", 30) is None
    assert agent.cache_get("answers", "k") == {"answer": "old"}


def test_set_validates_and_keeps_other_keys(run_agent, home):
    cfg_path = home / ".config" / "tuxaide" / "config.json"
    assert run_agent("--set", "enabled", "false").returncode == 0
    assert run_agent("--set", "prewarm", "sometimes").returncode == 2
    assert run_agent("--set", "model", "x'; import os #").returncode == 2
    assert run_agent("--set", "not_a_key", "1").returncode == 2

    write_config(home, custom="keep-me", model="a")
    subprocess.run([sys.executable, os.path.join(REPO, "agent.py"), "--set", "model", "llama3.2:1b"], check=True)
    cfg = json.loads(cfg_path.read_text())
    assert cfg == {"custom": "keep-me", "model": "llama3.2:1b"}


def test_perf_log_records_time_to_first_token(run_agent, ollama, home):
    ollama.answer = "hello"
    run_agent("--ask", "how do I say hello")
    log = (home / ".config" / "tuxaide" / "logs" / "perf.log").read_text()
    assert "\tttft=" in log and "ttft=-" not in log


def test_no_menu_or_numbers_when_not_a_terminal(run_agent, ollama):
    ollama.answer = "```bash\nls -la\n```\n"
    p = run_agent("--ask", "how to list files in a pipe")
    assert "[1]" not in p.stdout and "put on prompt" not in p.stdout
