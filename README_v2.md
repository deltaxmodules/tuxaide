# 🐧 TuxAide v2 — RAG Edition

> **Local AI assistant for your Linux terminal — now with man page knowledge base.**  
> Answers grounded in your system's own documentation. No hallucinations. No cloud. No API keys.

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Powered%20by-Ollama-blue)](https://ollama.com)
[![RAG](https://img.shields.io/badge/RAG-man%20pages-orange)](#rag-mode)
[![Privacy: 100% local](https://img.shields.io/badge/Privacy-100%25%20local-brightgreen)](#data-sovereignty)

</div>

---

## What's new in v2

TuxAide v1 used a general-purpose LLM. It worked well, but could occasionally produce incorrect command flags — AI models sometimes generate plausible-sounding but wrong information.

TuxAide v2 adds **RAG (Retrieval-Augmented Generation)**: before answering, the agent searches a local vector database built from the man pages installed on your system. It injects the most relevant passages into the prompt, grounding every answer in verified documentation.

```
v1:  Question → LLM → Answer

v2:  Question → Embedding → ChromaDB (your man pages)
                                    ↓
                             Relevant passages
                                    ↓
                      Question + Context → LLM → Answer
                                                  + Source citation
```

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup_v2.sh | bash
```

The installer will:
1. Diagnose your system (RAM, disk, GPU) and show a summary
2. Ask for confirmation before proceeding
3. Ask if you want RAG mode installed
4. Handle everything else automatically

After install, run once:
```bash
source ~/.bashrc    # Linux
source ~/.zshrc     # macOS
```

---

## System diagnosis

Before installing, the installer shows a full diagnosis:

```
┌─────────────────────────────────────────────────────┐
│  System Diagnosis Summary                           │
├─────────────────────────────────────────────────────┤
│  RAM:                     16 GB                     │
│  Free disk:               45 GB available           │
│  GPU:                     NVIDIA RTX 3060           │
│  AI model:                qwen2.5-coder:7b (4.7 GB) │
├─────────────────────────────────────────────────────┤
│  ✓ TuxAide v1 (LLM mode)    READY                   │
│  ✓ TuxAide v2 (RAG mode)    AVAILABLE               │
└─────────────────────────────────────────────────────┘

? Proceed with installation? [Y/n]
? Install RAG mode? (recommended) [Y/n]
```

---

## How it works

Write your Linux question directly in the terminal:

```
$ how do I configure nginx as a reverse proxy
```

TuxAide answers based on the nginx man page installed on your system:

```
╭──────────────────────────────────────────────────────────────╮
╞═ 🐧 TuxAide (Ollama · qwen2.5-coder:7b · RAG) ═╡

  To configure nginx as a reverse proxy, add a location block
  to your server configuration:

  ┄ nginx ┄
  location /api/ {
      proxy_pass http://localhost:3000/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
  }
  ┄┄┄┄┄┄┄

  Reload the configuration with: sudo nginx -s reload

  Source: man nginx(8)

  ⚠ Always verify commands before running them.

╰──────────────────────────────────────────────────────────────╯
```

The `Source: man nginx(8)` citation tells you exactly where the information came from.

---

## RAG mode

RAG mode indexes the man pages installed on your system. This means:

- **Answers are specific to your system** — if you have nginx 1.24, answers come from the nginx 1.24 man page
- **Drastically reduced hallucinations** — answers are grounded in real documentation
- **Source citations** — every answer cites the man page it used
- **Automatic fallback** — if RAG fails for any reason, TuxAide falls back to LLM mode silently

### Knowledge base

The indexer covers the **top 100 most useful Linux commands** by default:

`ls`, `grep`, `find`, `ssh`, `curl`, `git`, `systemctl`, `journalctl`, `nginx`, `docker`, `apt`, `chmod`, `cron`, `ps`, `top`, `df`, `du`, `tar`, `sed`, `awk`, and many more.

### After system updates

When you update packages (`apt upgrade`, `dnf update`), man pages may change. Re-index to keep the knowledge base current:

```bash
tuxaide reindex          # re-index all man pages
tuxaide index nginx      # index a specific command
```

---

## Mode control

```bash
tuxaide mode rag    # use man page knowledge base (v2)
tuxaide mode llm    # use general LLM only (v1 behaviour)
tuxaide mode        # show current mode
tuxaide status      # show status and current mode
```

---

## Any language

TuxAide detects your language automatically:

```bash
how do I check open ports              # → English
como listar ficheiros ocultos          # → Portuguese
comment lister les fichiers cachés     # → French
cómo ver el espacio en disco           # → Spanish
wie zeige ich offene Ports             # → German
```

---

## All controls

```bash
tuxaide on                  # enable automatic hook
tuxaide off                 # disable temporarily
tuxaide status              # show status and mode
tuxaide mode [llm|rag]      # switch knowledge mode
tuxaide model llama3.2      # switch Ollama model
tuxaide index <cmd>         # index a specific man page
tuxaide reindex             # re-index all man pages

tuxaide-uninstall           # remove completely
```

---

## Hardware requirements

| | v1 (LLM only) | v2 (RAG + LLM) |
|---|---|---|
| Minimum RAM | 5 GB | 8 GB |
| Recommended RAM | 8 GB | 16 GB |
| Disk space | ~5 GB | ~8 GB |
| GPU | Optional | Optional (faster) |
| Install time | ~10 min | ~25 min |
| Response time (CPU) | 4–10s | 5–12s |
| Response time (GPU) | ~1–2s | ~2–3s |

### AI models

| Available RAM | LLM Model | Size |
|---|---|---|
| ≥ 8 GB | `qwen2.5-coder:7b` | 4.7 GB |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB |

**RAG embedding model:** `nomic-embed-text` (274 MB) — always local, always offline.

---

## 🔒 Data Sovereignty

Everything runs locally. Nothing ever leaves your machine.

- All AI processing via Ollama at `localhost:11434`
- Man page embeddings stored in `~/.config/tuxaide/vectordb`
- No API keys. No accounts. No telemetry. No cloud.
- Works fully **air-gapped** after installation
- Compatible with **GDPR**, **NIS2** and **Swiss nDSG**

**Verified with tcpdump: 0 packets captured** during a full session.

---

## Compatibility

| Platform | v1 | v2 (RAG) |
|---|---|---|
| Ubuntu / Debian | ✅ | ✅ |
| Fedora / RHEL / CentOS | ✅ | ✅ |
| Arch Linux | ✅ | ✅ |
| openSUSE | ✅ | ✅ |
| Raspberry Pi (arm64) | ✅ | ⚠ RAM limited |
| ARM servers (AWS Graviton) | ✅ | ✅ |
| macOS (Intel + Apple Silicon) | ✅ | ✅ |

---

## 🍎 macOS notes

macOS uses **zsh** by default. After installing, run:

```bash
source ~/.zshrc    # not ~/.bashrc
```

If TuxAide does not respond, add the hook manually:

```bash
echo 'source "$HOME/.config/tuxaide/hook.sh"  # TuxAide' >> ~/.zshrc
source ~/.zshrc
```

---

## Upgrading from v1

If you already have TuxAide v1 installed:

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup_v2.sh | bash
```

The installer detects the existing installation and only adds the RAG components. Your current configuration is preserved.

---

## Uninstall

```bash
tuxaide-uninstall
```

Removes the agent, hook, config and vector database. Ollama and models are kept.

---

## Contributing

TuxAide is a community project. Issues, ideas and pull requests are welcome.

[github.com/deltaxmodules/tuxaide](https://github.com/deltaxmodules/tuxaide)

---

## Repository

```
tuxaide/
├── setup.sh       ← v1 installer (LLM only)
├── setup_v2.sh    ← v2 installer (LLM + optional RAG)
└── README.md
```

---

<div align="center">
<sub>🐧 Named after Tux, the Linux mascot · Powered by <a href="https://ollama.com">Ollama</a> · 100% local · 100% private · Built for beginners</sub>
</div>
