"""P10: tuxaide setup / uninstall, the rc block, packaged layouts, installer options."""
import os
import re
import shutil
import subprocess
import sys

import pytest

from conftest import REPO

USER_RC = """# my settings
export PATH="$HOME/.local/bin:$PATH"
alias tux='echo TuxAide is great'
export EDITOR=vim
"""
LEGACY = ('\nsource "$HOME/.config/tuxaide/hook.sh"  # TuxAide\n'
          'export PATH="$HOME/.local/bin:$PATH"  # TuxAide\n')


@pytest.fixture
def installed_home(home, ollama):
    """The curl installer's layout: agent in ~/.local/bin, hook in ~/.config/tuxaide."""
    bin_dir = home / ".local" / "bin"
    bin_dir.mkdir(parents=True)
    shutil.copy(f"{REPO}/agent.py", bin_dir / "tuxaide")
    for name in ("hook.sh", "session_writer.py"):
        shutil.copy(f"{REPO}/{name}", home / ".config" / "tuxaide" / name)
    ollama.models = [{"name": "fake", "size": 1}]
    return home


def tux(home, *args, env=None, agent=None):
    full = {**os.environ, "HOME": str(home), "SHELL": "/bin/zsh", **(env or {})}
    full.pop("TUXAIDE_SHELL", None)
    return subprocess.run([sys.executable, str(agent or home / ".local" / "bin" / "tuxaide"), *args],
                          capture_output=True, text=True, env=full, stdin=subprocess.DEVNULL, timeout=60)


def write_cfg(home, ollama, **extra):
    import json
    (home / ".config" / "tuxaide" / "config.json").write_text(
        json.dumps({"ollama_url": ollama.url, "model": "fake", **extra}))


def backups(home, rc=".zshrc"):
    return [f for f in os.listdir(home) if f.startswith(rc + ".tuxaide-")]


# ── the rc block ─────────────────────────────────────────────────────

def test_setup_adds_a_block_and_keeps_user_lines(installed_home, ollama):
    write_cfg(installed_home, ollama)
    (installed_home / ".zshrc").write_text(USER_RC)
    r = tux(installed_home, "setup", "--yes", "--no-doctor")
    assert r.returncode == 0, r.stdout
    rc = (installed_home / ".zshrc").read_text()
    assert rc.startswith(USER_RC)
    assert rc.endswith('# >>> TuxAide >>>\nsource "$HOME/.config/tuxaide/hook.sh"\n# <<< TuxAide <<<\n')
    assert len(backups(installed_home)) == 1
    # Running it again changes nothing and makes no new backup.
    tux(installed_home, "setup", "--yes", "--no-doctor")
    assert (installed_home / ".zshrc").read_text() == rc and len(backups(installed_home)) == 1


def test_setup_adds_path_only_when_missing(installed_home, ollama):
    write_cfg(installed_home, ollama)
    tux(installed_home, "setup", "--yes", "--no-doctor", env={"PATH": "/usr/bin:/bin"})
    assert 'export PATH="$HOME/.local/bin:$PATH"' in (installed_home / ".zshrc").read_text()


def test_setup_migrates_old_installer_lines(installed_home, ollama):
    write_cfg(installed_home, ollama)
    (installed_home / ".bashrc").write_text(USER_RC + LEGACY)
    tux(installed_home, "setup", "--yes", "--no-doctor", "--shell", "bash")
    rc = (installed_home / ".bashrc").read_text()
    assert "  # TuxAide" not in rc and rc.count("tuxaide/hook.sh") == 1
    assert rc.startswith(USER_RC)


# ── uninstall ────────────────────────────────────────────────────────

def test_uninstall_removes_only_what_tuxaide_wrote(installed_home, ollama):
    write_cfg(installed_home, ollama)
    (installed_home / ".zshrc").write_text(USER_RC)
    (installed_home / ".bashrc").write_text(USER_RC + LEGACY + "export LAST=1\n")
    tux(installed_home, "setup", "--yes", "--no-doctor")
    r = tux(installed_home, "uninstall", "--yes")
    assert r.returncode == 0, r.stdout
    assert (installed_home / ".zshrc").read_text() == USER_RC
    # Old installers wrote a blank line before their hook line; it stays (it may be the user's).
    assert (installed_home / ".bashrc").read_text() == USER_RC + "\nexport LAST=1\n"
    assert backups(installed_home, ".bashrc")
    assert not (installed_home / ".config" / "tuxaide").exists()
    assert not (installed_home / ".local" / "bin" / "tuxaide").exists()


def test_uninstall_keep_data(installed_home, ollama):
    write_cfg(installed_home, ollama)
    tux(installed_home, "setup", "--yes", "--no-doctor")
    tux(installed_home, "uninstall", "--yes", "--keep-data")
    assert (installed_home / ".config" / "tuxaide" / "config.json").exists()
    assert "TuxAide" not in (installed_home / ".zshrc").read_text()


def test_uninstall_needs_a_yes(installed_home, ollama):
    write_cfg(installed_home, ollama)
    tux(installed_home, "setup", "--yes", "--no-doctor")
    before = (installed_home / ".zshrc").read_text()
    r = tux(installed_home, "uninstall")
    assert r.returncode == 1 and "--yes" in r.stdout
    assert (installed_home / ".zshrc").read_text() == before


def test_uninstall_script_delegates(installed_home, ollama):
    write_cfg(installed_home, ollama)
    tux(installed_home, "setup", "--yes", "--no-doctor")
    r = subprocess.run(["bash", f"{REPO}/uninstall.sh", "--yes"], capture_output=True, text=True,
                       env={**os.environ, "HOME": str(installed_home)}, timeout=60)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "TuxAide" not in (installed_home / ".zshrc").read_text()


# ── setup: settings and model ────────────────────────────────────────

def test_setup_fills_settings_and_keeps_the_users(installed_home, ollama):
    write_cfg(installed_home, ollama, typo_suggest=False)
    tux(installed_home, "setup", "--yes", "--no-doctor")
    import json
    c = json.loads((installed_home / ".config" / "tuxaide" / "config.json").read_text())
    assert c["typo_suggest"] is False and c["model"] == "fake" and "followup_turns" in c


def test_setup_picks_a_model_for_the_ram(home, ollama, agent):
    import json
    (home / ".config" / "tuxaide" / "config.json").write_text(json.dumps({"ollama_url": ollama.url}))
    tux(home, "setup", "--yes", "--no-doctor", agent=f"{REPO}/agent.py")
    model = json.loads((home / ".config" / "tuxaide" / "config.json").read_text())["model"]
    assert model == agent.tier_for(agent.total_memory())[0]


def test_tiers(agent):
    gb = 2 ** 30
    assert agent.tier_for(16 * gb)[0] == "qwen2.5-coder:7b"
    assert agent.tier_for(int(7.6 * gb))[0] == "qwen2.5-coder:7b"      # an "8 GB" machine
    assert agent.tier_for(6 * gb)[0] == "qwen2.5:3b"
    assert agent.tier_for(int(3.8 * gb))[0] == "qwen2.5:1.5b"          # a "4 GB" machine
    assert agent.tier_for(2 * gb)[0] == "qwen2.5:0.5b"


def test_installer_and_agent_agree_on_tiers(agent):
    text = open(f"{REPO}/install.sh").read()
    for _, name, _ in agent.TIERS:
        assert f'MODEL="{name}"' in text, name


def test_setup_pulls_a_missing_model(installed_home, ollama):
    write_cfg(installed_home, ollama, model="tiny:1b")
    fake = installed_home / "fakebin"
    fake.mkdir()
    (fake / "ollama").write_text(f"#!/bin/sh\necho \"$@\" >> '{installed_home}/pulled'\n")
    (fake / "ollama").chmod(0o755)
    env = {"PATH": f"{fake}:{os.environ['PATH']}"}
    r = tux(installed_home, "setup", "--no-doctor", env=env)          # no terminal: doesn't ask, doesn't pull
    assert "Download it later" in r.stdout and not (installed_home / "pulled").exists()
    tux(installed_home, "setup", "--yes", "--no-doctor", env=env)
    assert (installed_home / "pulled").read_text().strip() == "pull tiny:1b"


def test_setup_when_ollama_is_down(installed_home, ollama):
    write_cfg(installed_home, ollama, ollama_url="http://127.0.0.1:9")
    r = tux(installed_home, "setup", "--yes", "--no-doctor")
    assert "isn't answering" in r.stdout and "setup again" in r.stdout
    assert "tuxaide/hook.sh" in (installed_home / ".zshrc").read_text()     # the shell part still happens


def test_setup_options(installed_home, ollama):
    assert tux(installed_home, "setup", "--bogus").returncode == 2
    assert tux(installed_home, "setup", "--shell", "fish").returncode == 2
    assert tux(installed_home, "setup", "--model", "a;b").returncode == 2


def test_setup_rag_starts_background_indexing(installed_home, ollama, agent, monkeypatch, capsys):
    """In-process: chromadb present, index empty → mode smart and the indexer started in the background."""
    write_cfg(installed_home, ollama)
    ollama.models = [{"name": "fake", "size": 1}, {"name": "nomic-embed-text:latest", "size": 1}]
    started = []
    monkeypatch.setattr(agent, "rag_available", lambda: True)
    monkeypatch.setattr(agent, "index_count", lambda c: 0)
    monkeypatch.setattr(agent, "start_background_index", lambda: started.append(1) or True)
    assert agent.setup_cmd(["--yes", "--rag", "--no-doctor", "--shell", "zsh"]) == 0
    assert started and agent.cfg()["mode"] == "smart"
    assert "Indexing man pages in the background" in capsys.readouterr().out


def test_setup_no_rag_turns_smart_off(installed_home, ollama):
    write_cfg(installed_home, ollama, mode="smart")
    tux(installed_home, "setup", "--yes", "--no-rag", "--no-doctor")
    import json
    assert json.loads((installed_home / ".config" / "tuxaide" / "config.json").read_text())["mode"] == "llm"


def test_indexing_pid_ignores_dead_processes(agent, home):
    (home / ".config" / "tuxaide" / "index.pid").write_text("999999")
    assert agent.indexing_pid() is None
    (home / ".config" / "tuxaide" / "index.pid").write_text(str(os.getpid()))
    assert agent.indexing_pid() == os.getpid()


# ── packaged layouts ─────────────────────────────────────────────────

def test_homebrew_like_layout(home, ollama, tmp_path):
    """bin/tuxaide → libexec/agent.py, files in share/tuxaide: the rc sources the stable
    share/tuxaide path (not libexec, not a versioned Cellar path)."""
    prefix = tmp_path / "prefix"
    for d in ("bin", "libexec", "share/tuxaide"):
        (prefix / d).mkdir(parents=True)
    shutil.copy(f"{REPO}/agent.py", prefix / "libexec" / "agent.py")
    for name in ("hook.sh", "session_writer.py"):
        shutil.copy(f"{REPO}/{name}", prefix / "share" / "tuxaide" / name)
    (prefix / "bin" / "tuxaide").symlink_to(prefix / "libexec" / "agent.py")
    write_cfg(home, ollama)
    ollama.models = [{"name": "fake", "size": 1}]
    tux(home, "setup", "--yes", "--no-doctor", agent=prefix / "bin" / "tuxaide")
    rc = (home / ".zshrc").read_text()
    assert f'source "{prefix}/share/tuxaide/hook.sh"' in rc
    assert ".local/bin" not in rc                                   # not the installer's layout


def test_hook_finds_its_agent_in_a_packaged_layout(tmp_path, home):
    prefix = tmp_path / "usr"
    (prefix / "bin").mkdir(parents=True)
    (prefix / "share" / "tuxaide").mkdir(parents=True)
    shutil.copy(f"{REPO}/agent.py", prefix / "bin" / "tuxaide")
    (prefix / "bin" / "tuxaide").chmod(0o755)
    shutil.copy(f"{REPO}/hook.sh", prefix / "share" / "tuxaide" / "hook.sh")
    for shell in [s for s in ("zsh", "bash") if shutil.which(s)]:
        out = subprocess.run([shell, "-c", f'. "{prefix}/share/tuxaide/hook.sh"; echo "LG=$_LG W=$_TUX_SESSION_WRITER"'],
                             capture_output=True, text=True, env={"HOME": str(home), "PATH": "/usr/bin:/bin"},
                             timeout=30).stdout
        assert f"LG={prefix}/bin/tuxaide" in out, (shell, out)
        assert f"W={prefix}/share/tuxaide/session_writer.py" in out, (shell, out)


def test_update_points_package_installs_to_their_manager(home, github, run_agent):
    github.release("9.9.9")
    r = run_agent("update", env=github.env)
    assert r.returncode == 1 and "git pull" in r.stdout


# ── installer options and packaging ──────────────────────────────────

def test_installer_options():
    run = lambda *a: subprocess.run(["bash", f"{REPO}/install.sh", *a], capture_output=True, text=True, timeout=30)  # noqa: E731
    assert run("--help").returncode == 0 and "--yes" in run("--help").stdout
    assert run("--bogus").returncode == 2
    assert run("--model", "a;b").returncode == 2


@pytest.mark.skipif(not shutil.which("curl"), reason="render-packaging.sh downloads with curl")
def test_render_packaging(tmp_path, agent):
    tarball = tmp_path / "t.tar.gz"
    tarball.write_bytes(b"fake tarball")
    out = tmp_path / "out"
    r = subprocess.run(["bash", f"{REPO}/scripts/render-packaging.sh", agent.__version__,
                        f"file://{tarball}", str(out)], capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    import hashlib
    sha = hashlib.sha256(b"fake tarball").hexdigest()
    formula, pkgbuild = (out / "tuxaide.rb").read_text(), (out / "PKGBUILD").read_text()
    assert sha in formula and sha in pkgbuild and "@" not in re.sub(r"[\w.-]+@[\w.]+|\"@|python@", "", formula)
    assert f"pkgver={agent.__version__}" in pkgbuild


def test_path_warning_for_the_installer_layout(installed_home, ollama):
    write_cfg(installed_home, ollama)
    env = {"PATH": "/usr/bin:/bin"}
    assert "isn't on your PATH" in tux(installed_home, "doctor", env=env).stdout
    r = tux(installed_home, "setup", "--yes", env=env)               # adds the PATH line to the rc
    assert 'export PATH="$HOME/.local/bin:$PATH"' in (installed_home / ".zshrc").read_text()
    assert "isn't on your PATH" not in r.stdout and "isn't loaded in this terminal" not in r.stdout


def test_indexer_of_the_same_installation(installed_home, tmp_path, monkeypatch):
    """An older tuxaide-index earlier on PATH must not be used."""
    bin_dir = installed_home / ".local" / "bin"
    (bin_dir / "tuxaide-index").write_text("#!/bin/sh\n")
    (bin_dir / "tuxaide-index").chmod(0o755)
    other = tmp_path / "other"
    other.mkdir()
    (other / "tuxaide-index").write_text("#!/bin/sh\n")
    (other / "tuxaide-index").chmod(0o755)
    code = "import sys; sys.argv[0] = sys.argv[1]; exec(open(sys.argv[1]).read().replace('if __name__ == \"__main__\": main()', '')); print(indexer_command())"
    out = subprocess.run([sys.executable, "-c", code, str(bin_dir / "tuxaide")], capture_output=True, text=True,
                         env={**os.environ, "HOME": str(installed_home), "PATH": f"{other}:/usr/bin:/bin"}).stdout
    assert str(bin_dir / "tuxaide-index") in out and str(other) not in out
