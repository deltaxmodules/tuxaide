import json
import shutil
import subprocess
import sys
import types

import pytest

from conftest import REPO, load_module


@pytest.fixture
def indexer(home, monkeypatch):
    # chromadb is optional; the indexer only needs a collection-like object here.
    monkeypatch.setitem(sys.modules, "chromadb", types.ModuleType("chromadb"))
    return load_module("tuxaide_indexer", "indexer.py")


class FakeCollection:
    def __init__(self):
        self.ids, self.adds, self.metadatas = set(), 0, []

    def get(self, ids):
        return {"ids": [i for i in ids if i in self.ids]}

    def add(self, ids, embeddings, documents, metadatas):
        assert len(ids) == len(embeddings) == len(documents) == len(metadatas)
        self.ids.update(ids)
        self.adds += 1
        self.metadatas += metadatas


TEXT = " ".join(f"word{i}" for i in range(8000))     # ~50 chunks: more than one batch


@pytest.mark.parametrize("batch_api", [True, False])
def test_indexer_batches_and_skips_existing(indexer, ollama, monkeypatch, batch_api):
    ollama.batch_embed = batch_api
    monkeypatch.setattr(indexer, "get_man_text", lambda cmd: TEXT)
    monkeypatch.setattr(indexer, "man_section", lambda cmd: "8")
    col, cfg = FakeCollection(), {"embed_model": "e", "ollama_url": ollama.url}

    n = indexer.index_command("sudo", col, cfg, verbose=False)
    assert n == len(col.ids) > indexer.BATCH
    assert col.metadatas[0]["source"] == "man sudo(8)"
    calls = [p for p, _ in ollama.requests]
    if batch_api:
        assert calls.count("/api/embed") == col.adds < n          # far fewer requests than chunks
    else:
        assert calls.count("/api/embeddings") == n                 # 404 → one request per chunk

    before = len(ollama.requests)
    indexer.index_command("sudo", col, cfg, verbose=False)
    assert len(ollama.requests) == before                          # nothing re-embedded


def test_top_commands_have_no_duplicates(indexer):
    assert len(indexer.TOP_COMMANDS) == len(set(indexer.TOP_COMMANDS))


@pytest.mark.skipif(not shutil.which("man"), reason="no man command")
def test_man_section_defaults_to_1(indexer):
    assert indexer.man_section("definitely-not-a-command-xyz") == "1"


def test_session_writer_truncates_long_output(home, tmp_path):
    out = tmp_path / "out.txt"
    err = tmp_path / "err.txt"
    lines = [f"line {i}" for i in range(1000)]
    lines[500] = "fatal: something broke"
    out.write_text("\n".join(lines))
    err.write_text("ls: cannot access 'x': No such file or directory\n")
    subprocess.run([sys.executable, f"{REPO}/session_writer.py", "ls x", str(out), str(err), "2", "true", "bash"],
                   check=True)
    session = json.loads((home / ".config" / "tuxaide" / "session.json").read_text())
    run = session["last_shell_run"]
    kept = run["stdout"].splitlines()
    assert run["exit_code"] == 2 and run["output_truncated"]
    assert kept[:50] == lines[:50] and kept[-50:] == lines[-50:]
    assert "fatal: something broke" in kept
    assert "No such file" in run["stderr"]
    mode = (home / ".config" / "tuxaide" / "session.json").stat().st_mode & 0o777
    assert mode == 0o600                                           # may hold secrets from output
