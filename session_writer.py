#!/usr/bin/env python3
"""Write last shell run context for TuxAide session explanations."""
import json
import os
import re
import sys
import tempfile
import time
from typing import List


CFG_DIR = os.path.expanduser("~/.config/tuxaide")
SESSION_FILE = os.path.join(CFG_DIR, "session.json")
LOCK_FILE = os.path.join(CFG_DIR, "session.lock")
KEYWORDS = ("error", "warn", "fatal", "failed", "denied")
MAX_LINES = 500
HEAD_LINES = 50
TAIL_LINES = 50


def _read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""


def _keep_lines(raw_lines: List[str]) -> List[str]:
    if len(raw_lines) <= MAX_LINES:
        return raw_lines

    keep = set(range(min(HEAD_LINES, len(raw_lines))))
    tail_start = max(0, len(raw_lines) - TAIL_LINES)
    keep.update(range(tail_start, len(raw_lines)))

    for idx, line in enumerate(raw_lines):
        low = line.lower()
        if any(k in low for k in KEYWORDS):
            keep.add(idx)

    ordered = [raw_lines[i] for i in sorted(keep)]
    if len(ordered) <= MAX_LINES:
        return ordered
    return ordered[:MAX_LINES]


def _truncate_text(text: str):
    lines = text.splitlines()
    kept = _keep_lines(lines)
    truncated = len(lines) > len(kept)
    return "\n".join(kept), truncated, len(lines), len(kept)


def _load_json(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _atomic_write(path: str, data: dict):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="session.", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            json.dump(data, tmp, indent=2, ensure_ascii=True)
            tmp.flush()
            os.fsync(tmp.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def main():
    if len(sys.argv) < 7:
        return 1

    command = sys.argv[1]
    stdout_path = sys.argv[2]
    stderr_path = sys.argv[3]
    exit_code = int(sys.argv[4])
    capturable = sys.argv[5].lower() == "true"
    shell_name = sys.argv[6]

    stdout_raw = _read_text(stdout_path) if capturable else ""
    stderr_raw = _read_text(stderr_path) if capturable else ""

    stdout_text, out_trunc, out_total, out_kept = _truncate_text(stdout_raw)
    stderr_text, err_trunc, err_total, err_kept = _truncate_text(stderr_raw)

    now = int(time.time())
    current = _load_json(SESSION_FILE)
    run_id = int(current.get("next_id", 1))

    last_shell_run = {
        "id": run_id,
        "timestamp": now,
        "command": command,
        "exit_code": exit_code,
        "capturable": capturable,
        "shell": shell_name,
        "stdout": stdout_text,
        "stderr": stderr_text,
        "stdout_lines_total": out_total,
        "stdout_lines_kept": out_kept,
        "stderr_lines_total": err_total,
        "stderr_lines_kept": err_kept,
        "output_truncated": bool(out_trunc or err_trunc),
    }

    data = {
        "updated_at": now,
        "last_shell_run_id": run_id,
        "next_id": run_id + 1,
        "last_shell_run": last_shell_run,
    }
    _atomic_write(SESSION_FILE, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
