# 🐧 TuxAide

> **Stop searching. Just ask your terminal.**
> No trigger word. No cloud. No command execution by TuxAide. Just ask your terminal in plain English.

<div align="center">

[![CI](https://github.com/deltaxmodules/tuxaide/actions/workflows/ci.yml/badge.svg)](https://github.com/deltaxmodules/tuxaide/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.3.0-informational)](https://github.com/deltaxmodules/tuxaide/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Powered%20by-Ollama-blue)](https://ollama.com)
[![Shell: bash/zsh](https://img.shields.io/badge/Shell-bash%20%7C%20zsh-lightgrey)](#compatibility)
[![Privacy: 100% local](https://img.shields.io/badge/Privacy-100%25%20local-brightgreen)](#data-sovereignty)

</div>

---

## ⚡ Example

```bash
$ how do I list hidden files sorted by size
```

→ instantly returns:

```bash
ls -laSh
```

No browser. No copy/paste. No remembering flags.

---

## 🚀 Install

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

Then:

```bash
# Linux (bash)
source ~/.bashrc

# macOS (zsh)
source ~/.zshrc
```

Start typing questions directly in your terminal.

---

## How it works

Write your Linux question directly in the terminal, as if it were a command:

```bash
$ how do I list hidden files sorted by size
```

TuxAide intercepts it silently and answers inline:

```
╭──────────────────────────────────────────────────────────────╮
╞═ 🐧 TuxAide (Ollama · qwen2.5-coder:7b · Smart RAG) ═╡

  To list hidden files sorted by size:

  ┄ shell ┄
  ls -laSh
  ┄┄┄┄┄┄┄

  -a shows hidden files, -S sorts by size (largest first),
  -h shows human-readable sizes (KB, MB, GB).
  To reverse: ls -laShr

  Source: man ls(1)

╰──────────────────────────────────────────────────────────────╯
```

Normal commands (`ls -la`, `git commit`, `sudo apt update`) pass through untouched. **Zero interference.**

### Put the command on your prompt

Commands in the answer are numbered. Press a number and TuxAide puts that command on your prompt, ready to edit — it still never runs anything:

```
  ┄ shell ┄
  [1] ls -laSh
  [2] ls -laShr
  ┄┄┄┄┄┄┄┄┄

  1-2 put on prompt · c copy · Enter skip
```

- **zsh**: the command appears on your prompt.
- **bash**: press **↑** to bring it up (bash can't pre-fill the prompt).
- **c** copies it instead (`pbcopy`, `wl-copy`, `xclip`, `xsel`, or OSC 52 over SSH).
- Destructive commands ask for confirmation first. Turn the menu off with `"action_menu": false`.

---

## Why TuxAide

**1. Built for people learning Linux.**
No remembering flags. No searching docs. Just ask.

**2. No trigger word needed.**
You don’t type `ask`, `hey` or anything else. Just write your question — TuxAide hooks into the shell and responds.

**3. It only explains. Never executes.**
Safer by design. You stay in control of what runs on your system.

**4. 100% local by default.**
No API key. No account. No cloud. Nothing leaves your machine — ever.

**5. One command installs everything.**
Ollama, model, shell hook — all in one command.

**6. Smart RAG — fast when simple, precise when needed.**
Simple questions → fast LLM answers
Command-specific → local documentation (man pages)

---

## Response speed

| Question type      | Example                          | Speed        |
| ------------------ | -------------------------------- | ------------ |
| Repeated question  | any question asked before        | < 1s (cache) |
| Simple / general   | "how do I create a folder"       | 3–5s         |
| Command-specific   | "rsync options to exclude files" | 8–15s        |
| Deep documentation | `tuxaide mode deep`              | 15–25s       |

---

## Any language

```bash
how do I check open ports
como listar ficheiros ocultos
comment lister les fichiers cachés
cómo ver el espacio en disco
wie zeige ich offene Ports
```

TuxAide automatically replies in your language.

---

## Examples

```bash
how do I backup with rsync
why is my process consuming so much RAM
what is the difference between chmod and chown
how to configure cron to run at 3am
how to see who is connected via SSH
how to create a sudo user on Ubuntu
what does the -z flag do in grep
```

---

## Destructive command warnings

```
⚠ WARNING: This command is destructive and irreversible. Verify carefully before running.

rm -rf /old-data/
```

---

## Controls

```bash
tuxaide on
tuxaide off
tuxaide status
tuxaide run "ls /missing-path"
tuxaide new
tuxaide history
tuxaide system
tuxaide model              # list installed models
tuxaide model llama3.2     # switch (offers to download it)
tuxaide config             # show settings
tuxaide config set typo_suggest false
tuxaide doctor
tuxaide update
tuxaide cache clear
tuxaide --version

tuxaide mode smart
tuxaide mode deep
tuxaide mode llm

tuxaide --timing
tuxaide reindex
tuxaide index nginx

tuxaide-uninstall
```

`tuxaide on` / `tuxaide off` are remembered across new terminals.

### Configuration

Settings live in `~/.config/tuxaide/config.json`. Reinstalling or updating keeps your existing values.
Change them with `tuxaide config set <key> <value>` (values are checked, and the change applies
in the current terminal too) or `tuxaide config reset <key>`; `tuxaide config` lists them all.

| Key | Default | Meaning |
| --- | --- | --- |
| `prewarm` | `once` (`off` below 8 GB RAM) | Load the model when a shell opens: `off`, `once` (at most every 10 min), `always` |
| `keep_alive` | `10m` | How long Ollama keeps the model in memory after a question |
| `cache_ttl_days` | `30` | Cached answers older than this are ignored |
| `action_menu` | `true` | After an answer, offer to put a command on the prompt or copy it |
| `failure_hint` | `true` | After a failed command, show the "type ? to ask TuxAide why" hint |
| `typo_suggest` | `true` | Suggest a fix for mistyped commands (`gti` → `git`) |
| `followup_window` | `600` | Seconds a conversation stays open for follow-ups (`0` turns them off) |
| `followup_turns` | `3` | How many previous exchanges are sent with a follow-up |
| `system_context` | `true` | Tell the model your OS, package manager, shell and init system |

Smart RAG's Python dependencies (ChromaDB) are installed in TuxAide's own virtualenv at `~/.local/share/tuxaide/venv`, never in your system Python, so no `pip` command is needed. `tuxaide-uninstall` removes it.

---

## Something not working? `tuxaide doctor`

```
$ tuxaide doctor
🐧 TuxAide 2.3.0 — doctor
   Ubuntu 24.04 LTS x86_64 · Python 3.12.3 · shell bash

  ✓ Settings: ~/.config/tuxaide/config.json
  ✗ Ollama isn't answering at http://localhost:11434
    → sudo systemctl start ollama
  · Mode LLM: the man-page knowledge base isn't used
  ✓ Hook in ~/.bashrc
  ✓ TuxAide answers unknown commands in this shell

1 problem(s), 0 warning(s). Run the commands after → to fix them.
```

It checks Ollama, the model, the embedding model and ChromaDB (in Smart/Deep mode),
the man-page index, the hook in your shell (and whether another command-not-found
handler, like oh-my-zsh's, took its place), your `PATH` and free memory. Every
problem comes with the command that fixes it, for your system. It exits with 1 when
something is broken, so it works in scripts too. Please paste its output in bug reports.

## Updating

```bash
tuxaide update --check    # is there a newer release?
tuxaide update            # download it, keeping settings, history and cache
```

TuxAide only contacts GitHub when you run `tuxaide update` — it never checks for
updates on its own. The new files are downloaded and checked before anything is
replaced, and the new hook is loaded into the current terminal.

## Answers for your system

TuxAide tells the model which system it's answering for, so you get `dnf` on
Fedora, `pacman` on Arch and `brew` on macOS instead of "it depends on your
distro". Only generic facts are sent — never user names, host names or paths:

```bash
$ tuxaide system
🐧 Sent with each question: Ubuntu 24.04 LTS, package manager apt, shell bash, init systemd, x86_64
```

Turn it off with `tuxaide --set system_context false`.

## Follow-up questions

TuxAide remembers the conversation for 10 minutes, so you can keep going:

```bash
$ como listar ficheiros ocultos
$ e por tamanho?
$ e ao contrário?
```

Follow-ups are recognised by how they start ("and…", "what about…", "e…",
"y…", "et…", "und…") or by short phrases pointing back ("does that work on
mac?"). A brand-new question is sent on its own, so unrelated answers don't mix.

- `tuxaide new` — start over
- `tuxaide history` — your recent questions

## Explain the last error with `?`

When a command fails, TuxAide shows a one-line hint. Type `?` to find out why:

```
$ ls /var/log/nginx
ls: /var/log/nginx: No such file or directory
💡 exit 1 — type ? to ask TuxAide why
$ ?
```

- `? <question>` asks something specific about the last command.
- Asking in words works too, right after the failure: `porque deu este erro?`
- TuxAide remembers only the last command line and its exit code, never its output.
  To read the error it re-runs the command: read-only commands (`ls`, `cat`, `grep`,
  `git status`, `systemctl status`, …) are re-run straight away, anything else only
  after you answer **y**. Interactive programs (`vim`, `top`, …) are never re-run.
- Turn the hint off with `"failure_hint": false`; `?` keeps working.

### Typos

Mistype a command and TuxAide suggests the fix instantly, without asking the model:

```
$ gti status
zsh: command not found: gti
🐧 Did you mean: git status  [Enter/y] put on prompt · other key skips
```

It knows the commands on your `PATH` plus your own aliases and functions, and
catches a missing space too (`cd..` → `cd ..`, `ls-la` → `ls -la`,
`git-log` → `git log`). On Debian/Ubuntu, a command that isn't installed shows
which package provides it. Turn it off with `"typo_suggest": false`.

### Full output capture with `tuxaide run`

To give TuxAide the complete output of a command up front:

```bash
tuxaide run "ls /naoexiste"
tuxaide "porque deu este erro?"
```

### Capture behavior

- `session_capture` is enabled by default (`true`)
- session file: `~/.config/tuxaide/session.json`
- output is truncated predictably:
  - max 500 lines
  - head 50 + tail 50
  - keep keyword lines: `error`, `warn`, `fatal`, `failed`, `denied`

### Privacy

- all captured context is local-only
- no cloud sync
- no external telemetry

---

## 🔒 Data Sovereignty

* Fully local processing via Ollama
* No external calls
* No tracking
* Works offline after install
* Designed for data-sovereign and offline environments

---

## Compatibility

| Platform           | Support |
| ------------------ | ------- |
| Ubuntu / Debian    | ✅       |
| Fedora / RHEL      | ✅       |
| Arch Linux         | ✅       |
| macOS              | ✅       |
| ARM / Raspberry Pi | ✅       |

Shells: bash, zsh
RAM: 5GB minimum (8GB recommended)

---

## Contributing

Open source project — contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for how to run the tests (no Ollama needed) and [SECURITY.md](SECURITY.md) to
report a vulnerability.

👉 https://github.com/deltaxmodules/tuxaide

Built with the help of AI tools (Claude, Ollama).

---
