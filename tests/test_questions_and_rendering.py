import io
import re

import pytest

ANSI = re.compile(r"\x1b\[[0-9;]*m")


@pytest.mark.parametrize("line", [
    "how do I list hidden files sorted by size",
    "como listar ficheiros ocultos",
    "comment lister les fichiers cachés",
    "cómo ver el espacio en disco",
    "wie zeige ich offene Ports",
    "is this a question?",
])
def test_questions_are_detected(agent, line):
    assert agent.is_q(line)


@pytest.mark.parametrize("line", [
    "ls -la", "git commit -m 'how to'", "which python3", "sudo apt update",
    "grep how file.txt | sort", "gti status", "xyz",
])
def test_commands_are_not_questions(agent, line):
    assert not agent.is_q(line)


@pytest.mark.parametrize("question,expected", [
    ("rsync options to exclude files", True),     # keyword "options"
    ("how to fix this error", True),              # keyword "error"
    ("where is nginx config", True),              # mentions a command
    ("how do I manage users", False),             # "man" inside "manage" must not count
    ("what is a command", False),                 # "man" inside "command" must not count
])
def test_rag_routing_uses_whole_words(agent, question, expected):
    assert agent.should_use_rag(question) is expected


def test_prompt_mirrors_the_users_language(agent):
    prompt = agent.build_prompt()
    assert "same language the user wrote" in prompt


@pytest.mark.parametrize("text", ["rm -rf /old", "sudo rm file", "dd if=/dev/zero of=/dev/sda",
                                  "mkfs.ext4 /dev/sdb1", "chmod 777 /", "DROP TABLE users",
                                  "find . -size +100M -delete", "find /tmp -type f -exec rm {} \\;",
                                  "find . -name '*.log' -execdir rm -- {} +", "ls *.tmp | xargs -0 rm"])
def test_destructive_commands(agent, text):
    assert agent.is_destructive(text)


@pytest.mark.parametrize("text", ["rm file.txt", "rmdir empty", "ls -la", "chmod 644 f",
                                  "find . -size +100M", "find . -name '*.py' -exec grep -l TODO {} +"])
def test_harmless_commands(agent, text):
    assert not agent.is_destructive(text)


def render(agent, text, cols=60, numbered=False, monkeypatch=None):
    monkeypatch.setenv("COLUMNS", str(cols))
    out = io.StringIO()
    r = agent.Renderer({"model": "m", "color": True}, "llm", out=out, numbered=numbered)
    for i in range(0, len(text), 5):          # feed in small chunks, like a stream
        r.feed(text[i:i + 5])
    r.finish()
    return out.getvalue(), r


LONG = ("To list **hidden files** sorted by size use `ls` with the right options, which are "
        "quite useful every day for anyone who uses Linux a lot.\n\n"
        "```bash\nsudo rm -rf /old-data/\n```\nDone.")


@pytest.mark.parametrize("cols", [40, 60, 100])
def test_no_line_is_wider_than_the_terminal(agent, monkeypatch, cols):
    out, _ = render(agent, LONG, cols, monkeypatch=monkeypatch)
    widths = [len(ANSI.sub("", line)) for line in out.splitlines() if "rm -rf" not in line]
    assert max(widths) <= cols


def test_destructive_warning_comes_before_its_code_block(agent, monkeypatch):
    out, _ = render(agent, LONG, monkeypatch=monkeypatch)
    plain = ANSI.sub("", out)
    assert plain.index("WARNING") < plain.index("sudo rm -rf /old-data/")


def test_shell_commands_are_numbered(agent, monkeypatch):
    text = "Use:\n\n```bash\n# comment\nls -laSh\nls -laShr\n```\n\n```text\nnot a command\n```\n"
    out, r = render(agent, text, numbered=True, monkeypatch=monkeypatch)
    plain = ANSI.sub("", out)
    assert "[1] ls -laSh" in plain and "[2] ls -laShr" in plain
    assert "not a command" in plain and "[3]" not in plain
    assert r.commands == ["ls -laSh", "ls -laShr"]


def test_extract_commands(agent):
    lines = ["# list", "$ ls -la", "", 'find . -name "*.log" \\', "  -delete", "ls -la", "echo done"]
    assert agent.extract_commands(lines) == [
        (1, "ls -la"),
        (3, 'find . -name "*.log" \\\n-delete'),
        (6, "echo done"),
    ]
