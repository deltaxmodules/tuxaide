# 🐧 TuxAide

> **Local AI assistant for your Linux terminal.**  
> Designed for new Linux users — no remembering flags, no web searches, just ask your terminal.

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Powered%20by-Ollama-blue)](https://ollama.com)
[![Shell: bash/zsh](https://img.shields.io/badge/Shell-bash%20%7C%20zsh-lightgrey)](#compatibility)
[![Privacy: 100% local](https://img.shields.io/badge/Privacy-100%25%20local-brightgreen)](#data-sovereignty)

</div>

---

## Install

One command. That's it.

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

The installer handles everything automatically — Ollama, the AI model, the shell hook. When it finishes, run:

```bash
# Linux (bash)
source ~/.bashrc

# macOS (zsh — default on Mac)
source ~/.zshrc
```

Then just start typing questions.

---

## How it works

Write your Linux question directly in the terminal, as if it were a command:

```
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

## What makes TuxAide different

Most AI terminal tools exist. Here is why TuxAide is not just another one:

**1. No trigger word needed.**  
Every other tool requires you to type `ask`, `hey`, `lumo`, `lexido` or similar before your question. TuxAide hooks into the shell's `command_not_found` handler — you just type your question naturally and it responds.

**2. It only explains. Never executes.**  
Tools like Billy, Shell Sage or AI-Terminal-X can run commands on your behalf. TuxAide deliberately does not. It explains, shows examples, and lets *you* decide what to run. Safer for beginners.

**3. 100% local by default.**  
Not as an option — as the only mode. No API key. No account. No cloud. Nothing leaves your machine, ever. Most competitors default to cloud and offer local as an optional configuration.

**4. Built for beginners, not developers.**  
Every other tool targets experienced users or developers. TuxAide targets people who are still learning Linux — junior sysadmins, students, anyone who keeps forgetting flags and commands.

**5. One command installs everything.**  
Ollama, the AI model, the shell hook — all in one `curl | bash`. No brew taps, no cargo, no pipx, no manual steps.

**6. Smart RAG — fast when simple, precise when needed.**  
TuxAide v2.1 uses a router to decide whether a question needs local man page documentation. Simple questions get a direct LLM answer in 3–5s. Questions about specific commands or system configuration use the local knowledge base. Repeated questions are answered instantly from cache.

---

## Response speed (v2.1)

| Question type | Example | Speed |
|---|---|---|
| Repeated question | any question asked before | < 1s (cache) |
| Simple / general | "how do I create a folder" | 3–5s (LLM direct) |
| Command-specific | "rsync options to exclude files" | 8–15s (Smart RAG) |
| Deep documentation | `tuxaide mode deep` | 15–25s (full RAG) |

---

## Any language

TuxAide detects your language automatically and always replies in the same language you used:

```bash
how do I check open ports              # → English
como listar ficheiros ocultos          # → Portuguese
comment lister les fichiers cachés     # → French
cómo ver el espacio en disco           # → Spanish
wie zeige ich offene Ports             # → German
```

---

## Examples

```bash
# Just type — no special prefix needed:
how do I backup with rsync
why is my process consuming so much RAM
what is the difference between chmod and chown
how to configure cron to run at 3am
how to see who is connected via SSH
how to create a sudo user on Ubuntu
what does the -z flag do in grep
what is a symlink and how do I create one

# Explicit mode also works:
tuxaide how to check disk usage by folder
tux what is the difference between hard and soft links

# Force deep RAG for full documentation:
tuxaide mode deep
how does systemctl manage service dependencies
tuxaide mode smart
```

---

## Destructive command warnings

When TuxAide answers with a command that is potentially destructive or irreversible — such as `rm -rf`, `dd`, `mkfs`, `fdisk`, or `chmod 777` — a visible warning is shown before the code block, regardless of whether the answer came from cache or from the model.

```
  ⚠  WARNING: This command is destructive and irreversible. Verify carefully before running.

  ┄ shell ┄
  rm -rf /old-data/
```

---

## Controls

```bash
tuxaide on                   # enable automatic hook
tuxaide off                  # disable (terminal works normally)
tuxaide status               # show current status and mode
tuxaide model llama3.2       # switch Ollama model

tuxaide mode smart           # Smart RAG (default — recommended)
tuxaide mode deep            # full RAG for every question
tuxaide mode llm             # LLM only, no man pages

tuxaide --timing             # show recent query performance log
tuxaide reindex              # re-index all man pages
tuxaide index nginx          # index a specific command

tuxaide-uninstall            # remove completely
```

---

## Performance log

TuxAide silently logs the latency of every query to `~/.config/tuxaide/logs/perf.log`. To inspect it:

```bash
tuxaide --timing
```

Example output:

```
2025-05-04T18:32:11   smart    embed=2.4s   rag=0.3s   llm=6.1s   total=8.8s   cache=miss
2025-05-04T18:34:02   smart    embed=0.0s   rag=0.0s   llm=0.0s   total=0.0s   cache=hit
2025-05-04T18:41:55   llm      embed=0.0s   rag=0.0s   llm=4.2s   total=4.2s   cache=miss
```

---

## AI Model

The installer picks the **best model for Linux knowledge**, not just the smallest:

| Available RAM | Model | Size | Why |
|---|---|---|---|
| ≥ 8 GB | `qwen2.5-coder:7b` | 4.4 GB | Trained on code, man pages and system commands — best for this agent |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB | Good Linux knowledge, lower RAM footprint |
| < 5 GB | `qwen2.5:3b` | 1.9 GB | Best available lightweight option |

> **Note:** AI models can make mistakes. TuxAide is advisory only — always review a command before running it.

---

## 🔒 Data Sovereignty

TuxAide was designed from the ground up for environments where **data cannot leave the server.**

- All AI processing runs locally via Ollama — no external calls, ever
- No data is sent to any server, cloud provider or third party
- No API keys. No accounts. No usage tracking.
- Works fully **air-gapped** — no internet required after installation
- Compatible with **GDPR**, **NIS2** and **Swiss nDSG** requirements

**Independently verified** — zero external traffic:

```
$ sudo tcpdump -i any host ollama.com &
$ tuxaide how do I list open ports

tcpdump: listening on any, link-type LINUX_SLL2
[... TuxAide answers fully ...]
^C
0 packets captured
0 packets received by filter
```

Not a single packet left the server. You can reproduce this test yourself at any time.

**Ideal for:** financial services · healthcare · legal · government · education · any environment with sensitive data.

---

## Comparison with alternatives

| | TuxAide | Lexido | Billy | Shell Sage | ask.sh |
|---|---|---|---|---|---|
| 100% local by default | ✅ | ❌ cloud | ✅ | ✅ | partial |
| No API key required | ✅ | ❌ | ✅ | ✅ | ❌ |
| Auto-trigger (no keyword) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Explain only — never executes | ✅ | ✅ | ❌ executes | ❌ executes | ❌ executes |
| One-line install (curl) | ✅ | ❌ | ✅ | ❌ | ❌ |
| Multilingual | ✅ | ❌ | ❌ | ❌ | ❌ |
| Smart RAG router | ✅ | ❌ | ❌ | ❌ | ❌ |
| Answer cache | ✅ | ❌ | ❌ | ❌ | ❌ |
| Destructive command warnings | ✅ | ❌ | ❌ | partial | ❌ |
| Targets beginners | ✅ | ❌ | ❌ | ❌ | ❌ |
| GDPR / nDSG safe | ✅ | ❌ | partial | partial | ❌ |

---

## Compatibility

| Platform | Support |
|---|---|
| Ubuntu / Debian | ✅ Full |
| Fedora / RHEL / CentOS | ✅ Full |
| Arch Linux | ✅ Full |
| openSUSE | ✅ Full |
| Raspberry Pi (arm64) | ✅ Full |
| ARM servers (AWS Graviton, Oracle ARM) | ✅ Full |
| macOS (Intel + Apple Silicon) | ✅ Full |

**Shells:** bash and zsh.  
**Minimum RAM:** 5 GB. Recommended: 8 GB+.

---

## 🍎 macOS notes

macOS uses **zsh** by default (not bash). After installing, always run:

```bash
source ~/.zshrc
```

Running `source ~/.bashrc` on a Mac will cause an error — use `.zshrc` instead.

If TuxAide does not respond after sourcing, add the hook manually:

```bash
echo 'source "$HOME/.config/tuxaide/hook.sh"  # TuxAide' >> ~/.zshrc
source ~/.zshrc
```

Then verify it is working:

```bash
tuxaide status
```

Also note: on macOS, Ollama is installed as a desktop app. If the automatic installer fails, download it manually from [ollama.com](https://ollama.com), open the app once, and then re-run the TuxAide installer.

---

## Updating from v2.0

If you already have TuxAide v2.0 installed, update by running the installer again:

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

The installer detects existing components and only reinstalls the agent binary. Your indexed man pages and config are preserved. After updating, run:

```bash
source ~/.bashrc   # or source ~/.zshrc on macOS
tuxaide mode smart # activate Smart RAG if you had RAG enabled
```

---

## Uninstall

```bash
tuxaide-uninstall
```

Removes the agent, the hook, the cache and all config files. Ollama and models are kept (remove manually if needed):

```bash
# Linux
sudo systemctl stop ollama
sudo rm $(which ollama)
rm -rf ~/.ollama

# macOS
killall ollama 2>/dev/null || true
rm -rf /Applications/Ollama.app
sudo rm -f /usr/local/bin/ollama
rm -rf ~/.ollama
```

---

## Contributing

TuxAide is a community project, not a finished product. Issues, ideas and pull requests are welcome.

If you speak a language not yet supported, open an issue — multilingual support is a priority.

[github.com/deltaxmodules/tuxaide](https://github.com/deltaxmodules/tuxaide)

---

## Repository

```
tuxaide/
├── setup.sh     ← complete self-contained installer
└── README.md
```

`setup.sh` contains everything: installer, Python agent, shell hook and uninstaller. One file. Zero external dependencies beyond `python3`, `curl` and `bash`.

---

## What changed in v2.1

- **Smart router** — the agent decides when to use RAG; simple questions skip it entirely
- **Answer cache** — MD5-keyed disk cache, normalized question, instant hits on repeated queries  
- **Embedding cache** — embeddings stored to disk; never recalculated for the same text
- **RAG filtered by command** — `chmod` question searches only `chmod` chunks, not all 100 man pages
- **RAG timeout** — if ChromaDB takes more than 8s, falls back to LLM silently
- **Smaller chunks** — 200 words instead of 400, faster retrieval, less noise in context
- **top_k reduced** — 1 in smart mode, 3 in deep mode
- **max_tokens reduced** — 300 in smart/llm mode, 600 in deep mode
- **Destructive command warnings** — shown before code blocks for `rm -rf`, `dd`, `mkfs`, etc.
- **Silent perf log** — `~/.config/tuxaide/logs/perf.log` records every query's latency breakdown
- **`tuxaide --timing`** — inspect the last 10 queries in the perf log
- **Pre-warm on session start** — model loaded into RAM when terminal opens

---

<div align="center">
<sub>🐧 Named after Tux, the Linux mascot · Powered by <a href="https://ollama.com">Ollama</a> · 100% local · 100% private · Built for beginners</sub>
</div>
