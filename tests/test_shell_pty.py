"""End-to-end tests in real interactive shells, driven through a pseudo-terminal.

Each test starts zsh or bash with the hook loaded, types like a person would,
and reads the screen. The model is the FakeOllama from conftest.
"""
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import time

import pytest

from conftest import REPO

# CSI and OSC sequences, keypad mode (ESC = / ESC >, sent by zsh on Linux
# terminfo), charset selection (ESC ( B), and carriage returns.
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\a]*\a|\x1b[=>]|\x1b[()][0-9A-Za-z]|\r")


def _bash_ok():
    bash = shutil.which("bash")
    if not bash:
        return False
    v = subprocess.run([bash, "-c", "echo ${BASH_VERSINFO[0]}"], capture_output=True, text=True).stdout
    return v.strip().isdigit() and int(v) >= 4      # command_not_found_handle needs bash 4


SHELLS = [s for s, ok in (("zsh", bool(shutil.which("zsh"))), ("bash", _bash_ok())) if ok]
if not SHELLS:
    pytest.skip("neither zsh nor bash >= 4 available", allow_module_level=True)


class Shell:
    def __init__(self, name, home):
        self.name, self.home = name, home
        argv = ([shutil.which("zsh"), "-i"] if name == "zsh" else
                [shutil.which("bash"), "--noprofile", "--rcfile", f"{home}/.bashrc", "-i"])
        env = {"HOME": str(home), "ZDOTDIR": str(home), "TERM": "xterm", "LANG": "C.UTF-8",
               "PYTHONIOENCODING": "utf-8", "PATH": "/usr/local/bin:/usr/bin:/bin",
               "COLUMNS": "80", "LINES": "40"}
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(argv[0], argv, env)
        self.buf = b""
        self.read_until(r"PROMPT> $")

    def read_until(self, pattern, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            text = ANSI.sub("", self.buf.decode(errors="ignore"))
            if re.search(pattern, text):
                self.buf = b""
                return text
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    self.buf += os.read(self.fd, 4096)
                except OSError:
                    break
        raise AssertionError(f"timed out waiting for {pattern!r}; screen:\n"
                             + ANSI.sub("", self.buf.decode(errors="ignore")))

    def send(self, keys):
        os.write(self.fd, keys.encode())

    def run(self, line):
        """Type a line, return everything up to the next prompt."""
        self.send(line + "\r")
        return self.read_until(r"PROMPT> $")

    def ask(self, line):
        """Type a question, skip the answer menu, return the screen."""
        self.send(line + "\r")
        out = self.read_until(r"put on prompt")
        self.send("\r")
        return out + self.read_until(r"PROMPT> $")

    def close(self):
        """Exit the shell; kill it if it doesn't go within 3 s (e.g. a test failed mid-menu)."""
        try:
            self.send("\x15exit\r")
        except OSError:
            pass
        # Keep reading while waiting: on macOS a shell (and close() on the pty)
        # can block while there is output nobody has read.
        end, exited = time.time() + 3, False
        while time.time() < end and not exited:
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    os.read(self.fd, 4096)
                except OSError:
                    pass
            try:
                exited = bool(os.waitpid(self.pid, os.WNOHANG)[0])
            except ChildProcessError:
                exited = True
        if not exited:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        while select.select([self.fd], [], [], 0)[0]:
            try:
                if not os.read(self.fd, 4096):
                    break
            except OSError:
                break
        os.close(self.fd)


@pytest.fixture(params=SHELLS)
def sh(request, home, ollama):
    bin_dir, fake = home / ".local" / "bin", home / "fakebin"
    bin_dir.mkdir(parents=True)
    fake.mkdir()
    shutil.copy(f"{REPO}/agent.py", bin_dir / "tuxaide")
    (bin_dir / "tuxaide").chmod(0o755)
    shutil.copy(f"{REPO}/hook.sh", home / ".config" / "tuxaide" / "hook.sh")
    (home / ".config" / "tuxaide" / "config.json").write_text(json.dumps(
        {"ollama_url": ollama.url, "model": "fake", "prewarm": "off", "color": False}))
    # A fake clipboard, so the tests never touch the real one.
    (fake / "pbcopy").write_text(f"#!/bin/sh\ncat > '{home}/clipboard'\n")
    (fake / "pbcopy").chmod(0o755)
    path = f"{fake}:{bin_dir}:{os.path.dirname(sys.executable)}:/usr/local/bin:/usr/bin:/bin"
    rc = (f'export PATH="{path}"\nalias myalias="echo hi"\nPS1="PROMPT> "\n'
          'source ~/.config/tuxaide/hook.sh\n')
    (home / ".zshrc").write_text(rc + "PROMPT='PROMPT> '\nunsetopt PROMPT_SP\n")
    # Debian/Ubuntu's global zshrc runs compinit, which can stop at an
    # "insecure directories" question on CI runners.
    (home / ".zshenv").write_text("skip_global_compinit=1\n")
    (home / ".bashrc").write_text(rc)
    ollama.answer = "Use:\n\n```bash\nls -laSh\nls -laShr\n```\n"
    shell = Shell(request.param, home)
    yield shell
    shell.close()


def pending_commands(home):
    d = home / ".config" / "tuxaide" / "pending"
    return [f for f in os.listdir(d) if f.isdigit()] if d.exists() else []


def expect_on_prompt(sh, cmd):
    """zsh puts the command in the edit buffer; bash puts it in history (↑)."""
    if sh.name == "zsh":
        sh.read_until(rf"PROMPT> {re.escape(cmd)}$")
    else:
        sh.read_until(r"to get it on your prompt[\s\S]*PROMPT> $")
        sh.send("\x1b[A")
        sh.read_until(rf"{re.escape(cmd)}$")
    sh.send("\x15")                                   # clear the line, never run it


# ── P3: answer menu ──────────────────────────────────────────────────

def test_menu_puts_chosen_command_on_prompt(sh):
    sh.send("how do I list hidden files sorted by size\r")
    out = sh.read_until(r"put on prompt")
    assert "[1] ls -laSh" in out and "[2] ls -laShr" in out and "1-2 put on prompt" in out
    sh.send("2")
    expect_on_prompt(sh, "ls -laShr")
    assert pending_commands(sh.home) == []


def test_menu_copies(sh):
    sh.send("how do I list hidden files by size please\r")
    sh.read_until(r"put on prompt")
    sh.send("c")
    sh.read_until(r"copy which\?")
    sh.send("1")
    sh.read_until(r"Copied")
    assert (sh.home / "clipboard").read_text() == "ls -laSh"


def test_menu_destructive_command_needs_y(sh, ollama):
    ollama.answer = "Careful:\n\n```bash\nsudo rm -rf /old-data/\n```\n"
    sh.send("how do I delete the old data folder\r")
    sh.read_until(r"put on prompt")
    sh.send("1")
    sh.read_until(r"anyway\? \[y/N\]")
    sh.send("n")
    sh.read_until(r"Skipped")
    assert pending_commands(sh.home) == []


# ── P4: hint + `?` ───────────────────────────────────────────────────

def test_failure_hint_and_question_mark(sh, ollama):
    out = sh.run("ls /nonexistent_tux")
    assert re.search(r"exit [12] — type \? to ask TuxAide why", out)
    assert "type ?" not in sh.run("")                 # an empty Enter doesn't repeat it

    out = sh.ask("?")
    assert "re-running: ls /nonexistent_tux" in out
    msg = ollama.last_user_message()
    assert "Command: ls /nonexistent_tux" in msg and "No such file" in msg

    sh.ask("how do I list hidden files")              # a question isn't "the last command"
    sh.ask("?")
    assert "Command: ls /nonexistent_tux" in ollama.last_user_message()

    sh.run("ls /nonexistent_tux")
    sh.ask("why did this fail")                       # a natural follow-up works too
    assert "Command: ls /nonexistent_tux" in ollama.last_user_message()


def test_unsafe_command_is_rerun_only_after_y(sh, ollama):
    out = sh.run("sh -c 'echo boom >&2; exit 3'")
    assert "exit 3 — type ?" in out
    sh.send("?\r")
    sh.read_until(r"to read its error\? \[y/N\]")
    sh.send("n")
    sh.read_until(r"put on prompt"); sh.send("\r"); sh.read_until(r"PROMPT> $")
    assert "STDERR:\nboom" not in ollama.last_user_message()

    sh.run("sh -c 'echo boom >&2; exit 3'")
    sh.send("? what does boom mean\r")
    sh.read_until(r"\[y/N\]")
    sh.send("y")
    sh.read_until(r"put on prompt"); sh.send("\r"); sh.read_until(r"PROMPT> $")
    msg = ollama.last_user_message()
    assert msg.startswith("what does boom mean") and "STDERR:\nboom" in msg


def test_staged_command_is_not_the_last_command(sh, ollama):
    sh.run("ls /nonexistent_tux")
    sh.send("how do I list files\r")
    sh.read_until(r"put on prompt")
    sh.send("1")
    expect_on_prompt(sh, "ls -laSh")
    sh.ask("?")
    assert "Command: ls /nonexistent_tux" in ollama.last_user_message()


def test_no_hint_after_success_or_ctrl_c(sh):
    assert "type ?" not in sh.run("true")
    assert "succeeded" in sh.run("?")
    sh.send("sleep 5\r")
    time.sleep(0.5)
    sh.send("\x03")
    assert "type ?" not in sh.read_until(r"PROMPT> $")


# ── P5: typos ────────────────────────────────────────────────────────

def test_typo_fix_goes_to_prompt_without_hint(sh):
    sh.send("pyhton3 --version\r")
    out = sh.read_until(r"other key skips")
    assert "Did you mean: python3 --version" in out
    sh.send("\r")
    expect_on_prompt(sh, "python3 --version")
    assert "type ?" not in out


@pytest.mark.parametrize("typed,expected", [("myalais", "myalias"), ("cd..", "cd .."),
                                            ("grpe --version", "grep --version")])
def test_typo_suggestions_in_shell(sh, typed, expected):
    sh.send(typed + "\r")
    out = sh.read_until(r"other key skips")
    assert f"Did you mean: {expected}" in out
    sh.send("n")
    sh.read_until(r"PROMPT> $")
    assert pending_commands(sh.home) == []


def test_destructive_typo_fix_is_only_shown(sh):
    out = sh.run("rm-rf /tmp/nothing_here_tux")
    assert "Did you mean: rm -rf /tmp/nothing_here_tux" in out and "other key skips" not in out


def test_unknown_word_gets_normal_not_found_and_hint(sh):
    out = sh.run("xyzzyq")
    assert "command not found" in out and "Did you mean" not in out and "type ?" in out


# ── on / off ─────────────────────────────────────────────────────────

def test_off_disables_everything_and_persists(sh):
    sh.run("tuxaide off")
    for check in (sh, Shell(sh.name, sh.home)):       # this shell and a new one
        out = check.run("pyhton3 --version")
        assert "command not found" in out and "Did you mean" not in out
        out = check.run("how do I list files")
        assert "TuxAide" not in out
        if check is not sh:
            check.close()
    sh.run("tuxaide on")


# ── P6: follow-ups ───────────────────────────────────────────────────

def test_followups_in_shell(sh, ollama):
    sh.ask("how do I list hidden files")
    out = sh.ask("e por tamanho?")
    assert "follow-up" in out
    assert ollama.chat_requests()[-1]["messages"][1]["content"] == "how do I list hidden files"
    out = sh.ask("and by size")                        # no "?" — still a follow-up here
    assert "follow-up" in out
    sh.run("tuxaide new")
    out = sh.run("and by size")                        # conversation closed: just a typo
    assert "TuxAide (" not in out
