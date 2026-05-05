# 🐧 TuxAide

> **Stop searching. Just ask your terminal.**
> No trigger word. No cloud. No command execution by TuxAide. Just ask your terminal in plain English.

<div align="center">

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

## Response speed (v2.1)

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
tuxaide model llama3.2

tuxaide mode smart
tuxaide mode deep
tuxaide mode llm

tuxaide --timing
tuxaide reindex
tuxaide index nginx

tuxaide-uninstall
```

---

## Shell Error Context (v2.2)

TuxAide can explain the last command output/error when you ask follow-up questions such as:

```bash
tuxaide run "ls /naoexiste"
tuxaide "porque deu este erro?"
```

This uses local session context from your latest captured shell execution.

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

Open source project — contributions welcome.

👉 https://github.com/deltaxmodules/tuxaide

Built with the help of AI tools (Claude, Ollama).

---
