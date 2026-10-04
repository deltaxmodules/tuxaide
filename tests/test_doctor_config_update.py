"""P8: --version, help, doctor, config, model, cache and update."""
import json
import os
import re
import shutil
import subprocess
import sys

import pytest

from conftest import REPO, write_config


def read_config(home):
    return json.loads((home / ".config" / "tuxaide" / "config.json").read_text())


# ── version and help ─────────────────────────────────────────────────

def test_version_and_help(agent, run_agent):
    for flag in ("--version", "-V", "version"):
        assert run_agent(flag).stdout.strip() == f"TuxAide {agent.__version__}"
    for args in ((), ("help",), ("--help",)):
        out = run_agent(*args).stdout
        assert f"TuxAide {agent.__version__}" in out
        assert "tuxaide doctor" in out and "tuxaide update" in out


# ── config ───────────────────────────────────────────────────────────

def test_config_lists_settings_and_marks_changes(run_agent):
    out = run_agent("config").stdout
    assert re.search(r"^  model\s+fake  \(default: qwen2\.5-coder:7b\)$", out, re.M)
    assert re.search(r"^  typo_suggest\s+true$", out, re.M)
    assert re.search(r"^  rag_db_path\s+\S+  \(edit the file\)$", out, re.M)


def test_config_set_validates_and_keeps_other_keys(home, run_agent):
    r = run_agent("config", "set", "keep_alive", "30m", config={"custom": 1})
    assert r.returncode == 0 and "keep_alive = 30m" in r.stdout
    assert read_config(home)["keep_alive"] == "30m" and read_config(home)["custom"] == 1

    for key, bad in (("keep_alive", "soon"), ("followup_turns", "99"), ("temperature", "hot"),
                     ("ollama_url", "localhost"), ("typo_suggest", "maybe"), ("model", "a;b")):
        r = run_agent("config", "set", key, bad)
        assert r.returncode == 2 and f"Invalid value for {key}" in r.stdout, key
        assert key not in read_config(home) or read_config(home)[key] != bad


def test_config_converts_types(home, run_agent):
    run_agent("config", "set", "followup_window", "0")
    assert read_config(home)["followup_window"] == 0
    run_agent("config", "set", "ollama_url", "http://192.168.1.10:11434/")
    assert read_config(home)["ollama_url"] == "http://192.168.1.10:11434"
    run_agent("config", "set", "failure_hint", "off")
    assert read_config(home)["failure_hint"] is False


def test_config_unknown_and_fixed_keys(run_agent):
    r = run_agent("config", "set", "nonsense", "1")
    assert r.returncode == 2 and "Unknown setting" in r.stdout
    r = run_agent("config", "set", "rag_db_path", "/tmp/x")
    assert r.returncode == 2 and "edit" in r.stdout


def test_config_get_and_reset(home, run_agent):
    assert run_agent("config", "get", "model").stdout.strip() == "fake"
    assert run_agent("config", "get", "color").stdout.strip() == "false"
    run_agent("config", "reset", "model")
    assert read_config(home)["model"] == "qwen2.5-coder:7b"


def test_config_set_mode_applies_its_rag_settings(home, run_agent):
    r = run_agent("config", "set", "mode", "llm", config={"mode": "deep", "max_tokens": 600})
    assert r.returncode == 0
    c = read_config(home)
    assert (c["mode"], c["max_tokens"]) == ("llm", 300)


def test_old_set_flag_still_validates(home, run_agent):
    assert run_agent("--set", "enabled", "false").returncode == 0
    assert read_config(home)["enabled"] is False
    assert run_agent("--set", "prewarm", "sometimes").returncode == 2


# ── model ────────────────────────────────────────────────────────────

def test_model_lists_installed_with_current_marked(run_agent, ollama):
    ollama.models = [{"name": "fake", "size": 2 * 1024 ** 3}, {"name": "other:1b", "size": 700 * 1024 ** 2}]
    out = run_agent("model").stdout
    assert re.search(r"\* fake\s+2\.0 GB", out)
    assert re.search(r"^    other:1b\s+700 MB", out, re.M)


def test_model_list_warns_when_configured_model_is_missing(run_agent, ollama):
    ollama.models = [{"name": "other:1b", "size": 1}]
    assert "isn't downloaded" in run_agent("model").stdout


def test_model_switch_to_installed(home, run_agent, ollama):
    ollama.models = [{"name": "fake", "size": 1}, {"name": "llama3.2:latest", "size": 1}]
    r = run_agent("model", "llama3.2")             # "llama3.2" is "llama3.2:latest"
    assert r.returncode == 0 and "Model changed to: llama3.2" in r.stdout
    assert read_config(home)["model"] == "llama3.2"


def test_model_not_downloaded_is_not_switched_without_a_terminal(home, run_agent, ollama):
    ollama.models = [{"name": "fake", "size": 1}]
    r = run_agent("model", "missing:7b")
    assert r.returncode == 1 and "ollama pull missing:7b" in r.stdout and "not changed" in r.stdout
    assert read_config(home)["model"] == "fake"


def test_model_name_is_validated(home, run_agent):
    r = run_agent("model", 'x"; rm -rf ~; "')
    assert r.returncode == 2 and read_config(home)["model"] == "fake"


def test_model_switch_when_ollama_is_down_warns_but_saves(home, run_agent):
    r = run_agent("model", "llama3.2", config={"ollama_url": "http://127.0.0.1:9"})
    assert "couldn't check" in r.stdout and read_config(home)["model"] == "llama3.2"


# ── cache ────────────────────────────────────────────────────────────

def test_cache_show_and_clear(home, run_agent):
    for kind, n in (("answers", 3), ("embeddings", 2)):
        d = home / ".config" / "tuxaide" / "cache" / kind
        d.mkdir(parents=True)
        for i in range(n):
            (d / f"{i}.json").write_text("{}")
    out = run_agent("cache").stdout
    assert re.search(r"answers\s+3 entries", out) and re.search(r"embeddings\s+2 entries", out)
    assert "3 answers, 2 embeddings" in run_agent("cache", "clear").stdout
    assert not (home / ".config" / "tuxaide" / "cache" / "answers").exists()


# ── doctor ───────────────────────────────────────────────────────────

@pytest.fixture
def healthy(home, ollama):
    """Everything in place, as after a good install, run from the user's shell."""
    ollama.models = [{"name": "fake", "size": 1024}]
    (home / ".config" / "tuxaide" / "hook.sh").write_text("# hook\n")
    (home / ".zshrc").write_text('source "$HOME/.config/tuxaide/hook.sh"  # TuxAide\n')
    return {"TUXAIDE_SHELL_PID": "1", "TUXAIDE_SHELL": "zsh", "TUXAIDE_HANDLER": "ours",
            "PATH": f"{home}/.local/bin{os.pathsep}{os.environ['PATH']}"}


def test_doctor_all_good(run_agent, healthy):
    r = run_agent("doctor", env=healthy, config={"api_base": ""})    # as the installer writes it
    assert r.returncode == 0, r.stdout
    assert "All good." in r.stdout
    assert "Ollama 0.0.0-fake answering" in r.stdout and "Model fake downloaded" in r.stdout
    assert "answers unknown commands" in r.stdout
    assert "\x1b[" not in r.stdout                   # plain text when not on a terminal (bug reports)


def test_doctor_ollama_down_fails_with_a_fix(run_agent, healthy):
    r = run_agent("doctor", env=healthy, config={"ollama_url": "http://127.0.0.1:9"})
    assert r.returncode == 1
    assert "✗ Ollama isn't" in r.stdout and "→ " in r.stdout


def test_doctor_remote_ollama_down_suggests_the_url(run_agent, healthy):
    r = run_agent("doctor", env=healthy, config={"ollama_url": "http://192.0.2.1:9"})
    assert r.returncode == 1 and "tuxaide config set ollama_url" in r.stdout


def test_doctor_missing_model(run_agent, healthy, ollama):
    ollama.models = [{"name": "other", "size": 1}]
    r = run_agent("doctor", env=healthy)
    assert r.returncode == 1 and "→ ollama pull fake" in r.stdout


def test_doctor_shell_problems(home, run_agent, healthy):
    r = run_agent("doctor", env={**healthy, "TUXAIDE_HANDLER": "other"})
    assert r.returncode == 1 and "Another command-not-found handler" in r.stdout
    r = run_agent("doctor", env={**healthy, "TUXAIDE_HANDLER": "old-bash"})
    assert r.returncode == 1 and "too old" in r.stdout
    (home / ".zshrc").write_text("")
    r = run_agent("doctor", env=healthy)
    assert r.returncode == 1 and "hook isn't in" in r.stdout and ">> ~/.zshrc" in r.stdout


def test_doctor_warnings_dont_fail(run_agent, healthy, home):
    env = {k: v for k, v in healthy.items() if k not in ("TUXAIDE_SHELL_PID", "TUXAIDE_HANDLER")}
    env["PATH"] = os.environ["PATH"]
    r = run_agent("doctor", env=env, config={"enabled": False, "prewarm": "sometimes"})
    assert r.returncode == 0, r.stdout
    for text in ("turned off", "prewarm", "isn't loaded in this terminal"):
        assert text in r.stdout


def test_doctor_bad_json(home, run_agent, healthy, ollama):
    env = {**os.environ, "COLUMNS": "80", **healthy}
    write_config(home)
    (home / ".config" / "tuxaide" / "config.json").write_text("{not json")
    r = subprocess.run([sys.executable, os.path.join(REPO, "agent.py"), "doctor"],
                       capture_output=True, text=True, env=env, timeout=60)
    assert r.returncode == 1 and "isn't valid JSON" in r.stdout


def test_doctor_rag_mode_without_embed_model(run_agent, healthy):
    r = run_agent("doctor", env=healthy, config={"mode": "smart"})
    assert r.returncode == 1 and "→ ollama pull nomic-embed-text" in r.stdout


def test_doctor_low_memory(run_agent, healthy, ollama, agent, monkeypatch):
    ollama.models = [{"name": "fake", "size": 1024 ** 4}]       # 1 TB model
    assert "of memory free" in run_agent("doctor", env=healthy).stdout
    ollama.loaded = [{"name": "fake"}]
    assert "is loaded in memory" in run_agent("doctor", env=healthy).stdout


@pytest.mark.parametrize("platform, dirs, tools, expected", [
    ("darwin", {"/Applications/Ollama.app"}, {"brew"}, "open -a Ollama"),
    ("darwin", set(), {"brew"}, "brew services start ollama"),
    ("linux", {"/run/systemd/system"}, set(), "sudo systemctl start ollama"),
    ("linux", set(), set(), "ollama serve > /tmp/ollama.log 2>&1 &"),
])
def test_ollama_start_hint_fits_the_system(agent, monkeypatch, platform, dirs, tools, expected):
    monkeypatch.setattr(agent.sys, "platform", platform)
    monkeypatch.setattr(agent.os.path, "isdir", lambda p: p in dirs)
    monkeypatch.setattr(agent.shutil, "which", lambda t: f"/bin/{t}" if t in tools else None)
    assert agent.ollama_start_hint() == expected


def test_ollama_down_hint(agent, monkeypatch):
    monkeypatch.setattr(agent.shutil, "which", lambda t: None)
    monkeypatch.setattr(agent.sys, "platform", "linux")
    assert "install.sh" in agent.ollama_down_hint({"ollama_url": "http://localhost:11434"})
    assert "192.0.2.1" in agent.ollama_down_hint({"ollama_url": "http://192.0.2.1:11434"})


# ── update ───────────────────────────────────────────────────────────

@pytest.fixture
def installed(home):
    """TuxAide laid out the way install.sh does it, with RAG (venv shebang)."""
    bin_dir, cfg_dir = home / ".local" / "bin", home / ".config" / "tuxaide"
    bin_dir.mkdir(parents=True)
    agent_src = open(os.path.join(REPO, "agent.py")).read()
    (bin_dir / "tuxaide").write_text("#!/venv/bin/python\n" + agent_src.split("\n", 1)[1])
    (bin_dir / "tuxaide").chmod(0o755)
    shutil.copy(os.path.join(REPO, "uninstall.sh"), bin_dir / "tuxaide-uninstall")
    shutil.copy(os.path.join(REPO, "hook.sh"), cfg_dir / "hook.sh")
    shutil.copy(os.path.join(REPO, "session_writer.py"), cfg_dir / "session_writer.py")
    (cfg_dir / "config.json").write_text('{"model": "mine", "custom": true}')
    (cfg_dir / "history.json").write_text('[{"q": "old question"}]')
    return home


def run_installed(home, github, *args):
    return subprocess.run([sys.executable, str(home / ".local" / "bin" / "tuxaide"), "update", *args],
                          capture_output=True, text=True, timeout=60,
                          env={**os.environ, **github.env})


def test_update_replaces_files_and_keeps_user_data(installed, github):
    github.release("9.9.9", hook_extra="\n# new hook\n")
    r = run_installed(installed, github)
    assert r.returncode == 0, r.stdout
    assert "→ 9.9.9" in r.stdout
    tux = (installed / ".local" / "bin" / "tuxaide").read_text()
    assert tux.startswith("#!/venv/bin/python\n")                 # RAG venv shebang kept
    assert '__version__ = "9.9.9"' in tux
    assert os.access(installed / ".local" / "bin" / "tuxaide", os.X_OK)
    assert (installed / ".config" / "tuxaide" / "hook.sh").read_text().endswith("# new hook\n")
    assert json.loads((installed / ".config" / "tuxaide" / "config.json").read_text()) == {"model": "mine", "custom": True}
    assert "old question" in (installed / ".config" / "tuxaide" / "history.json").read_text()
    assert not (installed / ".local" / "bin" / "tuxaide-index").exists()   # no RAG indexer before → none now


def test_update_check_changes_nothing(installed, github):
    github.release("9.9.9")
    before = (installed / ".local" / "bin" / "tuxaide").read_text()
    r = run_installed(installed, github, "--check")
    assert r.returncode == 0 and "9.9.9 is available" in r.stdout
    assert (installed / ".local" / "bin" / "tuxaide").read_text() == before
    assert not any("/raw/" in p for p in github.requests)


def test_update_when_already_latest(installed, github, agent):
    github.release(agent.__version__)
    r = run_installed(installed, github)
    assert r.returncode == 0 and "latest version" in r.stdout
    assert not any("/raw/" in p for p in github.requests)


def test_update_refuses_a_broken_download(installed, github):
    github.release("9.9.9")
    github.files["agent.py"] = github.files["agent.py"].replace('"9.9.9"', '"1.0.0"')
    before = (installed / ".config" / "tuxaide" / "hook.sh").read_text()
    r = run_installed(installed, github)
    assert r.returncode == 1 and "Nothing was changed" in r.stdout
    assert (installed / ".config" / "tuxaide" / "hook.sh").read_text() == before


def test_update_refuses_a_missing_file(installed, github):
    github.release("9.9.9")
    del github.files["session_writer.py"]
    r = run_installed(installed, github)
    assert r.returncode == 1 and "Nothing was changed" in r.stdout


def test_update_refuses_a_copy_that_isnt_installed(home, github, run_agent):
    github.release("9.9.9")
    r = run_agent("update", env=github.env)
    assert r.returncode == 1 and "git pull" in r.stdout


def test_update_without_network(installed):
    r = subprocess.run([sys.executable, str(installed / ".local" / "bin" / "tuxaide"), "update"],
                       capture_output=True, text=True, timeout=60,
                       env={**os.environ, "TUXAIDE_GITHUB_API": "http://127.0.0.1:9"})
    assert r.returncode == 1 and "Couldn't reach GitHub" in r.stdout


def test_version_tuple(agent):
    assert agent.version_tuple("v2.10.0") > agent.version_tuple("2.9.9")
    assert agent.version_tuple("2.3") == agent.version_tuple("2.3")


def test_smaller_model_hint_is_really_smaller(agent):
    assert agent.smaller_model_hint(4_683_087_074).endswith("qwen2.5:3b")         # 7b → 3b
    assert agent.smaller_model_hint(1_929_911_945).endswith("qwen2.5:1.5b")       # 3b → 1.5b
    assert agent.smaller_model_hint(986_061_405).endswith("qwen2.5:0.5b")         # 1.5b → 0.5b
    assert "Remote backends" in agent.smaller_model_hint(397_820_829)            # nothing smaller


def test_update_checks_sha256sums(installed, github):
    github.release("9.9.9")
    github.sign()
    r = run_installed(installed, github)
    assert r.returncode == 0, r.stdout
    assert '__version__ = "9.9.9"' in (installed / ".local" / "bin" / "tuxaide").read_text()


def test_update_refuses_a_checksum_mismatch(installed, github):
    github.release("9.9.9")
    github.sign()
    github.files["hook.sh"] += "\n# tampered\n"
    before = (installed / ".config" / "tuxaide" / "hook.sh").read_text()
    r = run_installed(installed, github)
    assert r.returncode == 1 and "doesn't match" in r.stdout and "Nothing was changed" in r.stdout
    assert (installed / ".config" / "tuxaide" / "hook.sh").read_text() == before
