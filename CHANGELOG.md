# Changelog

All notable changes to TuxAide. Versions follow [semantic versioning](https://semver.org/).

## 2.3.0 — 2026-10-04

The biggest release so far: answers stream in, commands go straight to your
prompt, `?` explains the last error, and TuxAide installs from Homebrew, the
AUR or pipx.

### Asking
- **Answers stream in** as the model writes them; the model is pre-loaded when
  a terminal opens (`prewarm`), and man pages are indexed in batches.
- **Put a command on your prompt**: commands in an answer are numbered — press
  the number (zsh: on the prompt; bash: one ↑ away), or `c` to copy.
  Destructive commands ask first.
- **Follow-up questions** ("and by size?") within 10 minutes; `tuxaide new`,
  `tuxaide history`.
- **Answers fit your system**: the model is told your OS, package manager,
  shell and init system (`tuxaide system`; `system_context` to turn it off).
- Replies in the language of the question, also for German, Italian and others.

### When things go wrong
- **`?` explains the last command that failed**, re-running it to read the
  error only when that's safe (read-only commands) or you say yes.
- **Typo suggestions** without the model: `gti status` → `git status`,
  `cd..` → `cd ..`; on Debian/Ubuntu, which package provides a missing command.
- The shell's previous command-not-found handler (Ubuntu's, PackageKit,
  oh-my-zsh's) is kept and still answers when TuxAide has nothing to say.

### Tools
- `tuxaide doctor` checks Ollama, the model, Smart RAG, the hook and memory,
  with the fix for your OS for every problem.
- `tuxaide update [--check]`, `tuxaide config [get|set|reset]`,
  `tuxaide model [name]` (offers `ollama pull`), `tuxaide cache [clear]`,
  `tuxaide --version`, `tuxaide status`.
- `tuxaide setup` (model, Smart RAG, shell) and `tuxaide uninstall`, which
  removes only the lines TuxAide added to your rc file, with a backup.

### Models and backends
- The installer picks the model that fits your RAM, down to `qwen2.5:1.5b`
  for 3–5 GB and `qwen2.5:0.5b` below.
- Optional remote backends: Ollama on another computer, or any
  OpenAI-compatible API (LM Studio, llama.cpp, vLLM, cloud). Every answer that
  leaves your machine is marked **☁ remote**; API keys are read from an
  environment variable and never stored.

### Installing
- Homebrew (`brew install deltaxmodules/tap/tuxaide`), AUR (`yay -S tuxaide`)
  and pipx (`pipx install tuxaide`, extra `[rag]`).
- The curl installer shows everything it will do and asks once; `--yes`,
  `--no-rag`, `--model`; files come from the release tag and are checked
  against `SHA256SUMS`; Smart RAG's dependencies live in their own virtualenv
  and man pages are indexed in the background.

### Fixes
- bash hung on every unknown command; `tuxaide off` was ignored in zsh.
- Answers were cut at the wrong width, cached errors were replayed, and "how do
  I manage users" triggered the man-page search because of the word "man".
- The installer could stop silently while waiting for Ollama, skip the model
  download when another model shared its name prefix, and its uninstaller
  deleted any rc line containing the word "TuxAide".
- `tuxaide model <name>` could run code hidden in the name.

### For contributors
- A test suite (`pytest`, with real zsh and bash sessions in a pseudo-terminal)
  and CI on Linux and macOS; `ruff` and `shellcheck` clean.
- One version, in `agent.py`; a Release workflow publishes everything from a tag.

## 2.2.1 — 2026-05-05
- zsh: no more duplicate replies; questions with `?` no longer break on globbing.
- Contextual routing ("why did this fail?") moved into the agent.

## 2.2.0 — 2026-05-05
- Shell error context: `tuxaide run "<command>"` captures a command's output so
  follow-up questions like "why did this fail?" can explain it.

## 2.1.1 — 2026-05-04
- Internal: the installer split into `install.sh`, `agent.py`, `hook.sh`,
  `indexer.py` and `uninstall.sh`. No change for users.

## 2.1.0 — 2026-05-04
- Smart RAG: man pages are searched only when a question needs them, with
  answer and embedding caches — from about 50 s down to a few seconds.

## 2.0.0 — 2026-05-04
- RAG mode: answers grounded in the man pages installed on your system.

## 0.1.0 — 2026-05-03
- First release: type Linux questions straight into your terminal, answered
  by a local model through Ollama.
