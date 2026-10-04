import pytest


@pytest.mark.parametrize("cmd,policy", [
    ("ls /nope", "safe"),
    ("git status", "safe"),
    ("FOO=1 grep x f", "safe"),
    ("find . -name x", "safe"),
    ("git push", "ask"),
    ("rm -rf x", "ask"),
    ("cat a > b", "ask"),             # redirection writes a file
    ("grep x f | sort", "ask"),
    ("find . -delete", "ask"),
    ("make install", "ask"),
    ("sudo ls", "ask"),
    ("python3 x.py", "ask"),
    ("python3", "never"),             # a REPL
    ("vim f", "never"),
    ("tail -f log", "never"),
])
def test_rerun_policy(agent, cmd, policy):
    assert agent.rerun_policy(cmd) == policy


@pytest.mark.parametrize("lang,start", [
    ("pt_PT.UTF-8", "Porque é que"),
    ("es_ES.UTF-8", "¿Por qué"),
    ("en_US.UTF-8", "Why did"),
    ("C", "Why did"),
])
def test_default_why_question_follows_locale(agent, monkeypatch, lang, start):
    monkeypatch.setenv("LANG", lang)
    assert agent.default_why_question().startswith(start)


def test_why_reruns_safe_command_and_sends_its_error(run_agent, ollama, tmp_path):
    ollama.answer = "It does not exist."
    missing = tmp_path / "definitely_missing"
    p = run_agent("--why", f"ls {missing}", "1", env={"SHELL": "/bin/sh"})
    assert "It does not exist." in p.stdout
    msg = ollama.last_user_message()
    assert f"Command: ls {missing}" in msg
    assert "No such file" in msg


def test_why_without_terminal_never_reruns_unsafe_command(run_agent, ollama, tmp_path):
    marker = tmp_path / "ran"
    run_agent("--why", f"touch {marker}", "1")
    assert not marker.exists()
    assert "output isn't available" in ollama.last_user_message()


def test_why_after_success_has_nothing_to_explain(run_agent, ollama):
    p = run_agent("--why", "true", "0")
    assert "succeeded" in p.stdout
    assert ollama.chat_requests() == []


def test_natural_followup_uses_last_failed_command(run_agent, ollama, tmp_path):
    ollama.answer = "Because."
    run_agent("--ask", "why did this fail",
              env={"TUXAIDE_LAST_CMD": f"ls {tmp_path}/nope", "TUXAIDE_LAST_RC": "2", "SHELL": "/bin/sh"})
    assert f"Command: ls {tmp_path}/nope" in ollama.last_user_message()


# ── P5: typos ─────────────────────────────────────────────────────────

@pytest.mark.parametrize("a,b,d", [("gti", "git", 1), ("sl", "ls", 1), ("grpe", "grep", 1),
                                   ("kitten", "sitting", 3), ("abc", "abc", 0)])
def test_edit_distance(agent, a, b, d):
    assert agent.edit_distance(a, b, 5) == d


@pytest.fixture
def fake_path(tmp_path, monkeypatch):
    """A PATH holding only a known set of commands, so results don't depend on the machine."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in ["git", "ls", "grep", "python3", "docker", "clear", "cd", "nl", "ln", "tar", "rm"]:
        f = bin_dir / name
        f.write_text("#!/bin/sh\n")
        f.chmod(0o755)
    monkeypatch.setenv("PATH", str(bin_dir))
    monkeypatch.chdir(tmp_path)
    return bin_dir


@pytest.mark.parametrize("typed,fixed", [
    ("gti status", "git status"),
    ("sl -la", "ls -la"),               # a swap beats "nl"/"ln"
    ("grpe -r foo .", "grep -r foo ."),
    ("pyhton3 x.py", "python3 x.py"),
    ("dokcer ps", "docker ps"),
    ("celar", "clear"),
    ("exprot FOO=1", "export FOO=1"),   # a builtin, passed in by the shell
    ("myalais", "myalias"),             # an alias, passed in by the shell
    ("cd..", "cd .."),
    ("ls-la", "ls -la"),
    ("git-log", "git log"),
    ("tar-xzf a.tgz", "tar -xzf a.tgz"),
])
def test_typo_suggestions(agent, fake_path, typed, fixed):
    assert agent.suggest_fix(typed, ["export", "myalias", "ll"]) == fixed


@pytest.mark.parametrize("typed", ["xyzzy", "hello world", "ll", "a", "FOO=1 cmd", "./missing.sh"])
def test_no_typo_suggestion(agent, fake_path, typed):
    assert agent.suggest_fix(typed, ["ll"]) is None


def test_local_script_gets_dot_slash(agent, fake_path):
    script = fake_path.parent / "deploy.sh"
    script.write_text("#!/bin/sh\n")
    script.chmod(0o755)
    assert agent.suggest_fix("deploy.sh --dry-run") == "./deploy.sh --dry-run"


def test_not_found_exit_codes(run_agent, ollama, fake_path):
    env = {"PATH": str(fake_path), "TUXAIDE_SHELL": "bash"}
    p = run_agent("--not-found", "gti", "status", env=env)
    assert p.returncode == 3 and "Did you mean: git status" in p.stderr
    p = run_agent("--not-found", "xyzzyq", env=env)
    assert p.returncode == 1 and p.stderr == ""
    ollama.answer = "Use ls."
    p = run_agent("--not-found", "how", "do", "I", "list", "files", env=env)
    assert p.returncode == 0 and "Use ls." in p.stdout
    p = run_agent("--not-found", "gti", "status", env=env, config={"typo_suggest": False})
    assert p.returncode == 1


@pytest.fixture
def fake_helper(agent, tmp_path, monkeypatch):
    """Stand-in for Debian/Ubuntu's /usr/lib/command-not-found."""
    helper = tmp_path / "command-not-found"
    helper.write_text(
        "#!/bin/sh\n"
        'case "$2" in\n'
        "  htop) echo \"Command 'htop' not found, but can be installed with:\" >&2;"
        " echo 'sudo apt install htop' >&2 ;;\n"
        '  *) echo "$2: command not found" >&2 ;;\n'
        "esac\nexit 127\n")
    helper.chmod(0o755)
    monkeypatch.setattr(agent, "CNF_HELPER", str(helper))
    return helper


def test_distro_package_hint_comes_first(agent, fake_path, fake_helper, capsys):
    (fake_path / "top").write_text("#!/bin/sh\n")
    (fake_path / "top").chmod(0o755)
    assert agent.suggest_main("htop") == 0
    err = capsys.readouterr().err
    assert err.index("sudo apt install htop") < err.index("Did you mean: top")
    assert "bash: htop: command not found" not in err      # the helper already said it


def test_bare_distro_message_is_ignored(agent, fake_path, fake_helper, capsys):
    assert agent.suggest_main("xyzzyq") == 1                # shell prints its own message
    assert capsys.readouterr().err == ""
