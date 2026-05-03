# 🧞 LinuxGenie

> **Local AI agent for your Linux terminal.**  
> Type your question directly. Get an answer inline. No cloud. No API keys. No subscriptions. Forever free.

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
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/linuxgenie/main/setup.sh | bash
```

The installer handles everything automatically — Ollama, the AI model, the shell hook. When it finishes, run:

```bash
source ~/.bashrc
```

Then just start typing questions.

---

## How it works

Write your Linux question directly in the terminal, as if it were a command:

```
$ how do I list hidden files sorted by size
```

LinuxGenie intercepts it silently and answers inline:

```
╭──────────────────────────────────────────────────────────────╮
╞═ 🧞 LinuxGenie (Ollama · qwen2.5-coder:7b) ═╡

  To list hidden files sorted by size:

  ┄ shell ┄
  ls -laSh
  ┄┄┄┄┄┄┄

  -a shows hidden files, -S sorts by size (largest first),
  -h shows human-readable sizes (KB, MB, GB).
  To reverse: ls -laShr

╰──────────────────────────────────────────────────────────────╯
```

Normal commands (`ls -la`, `git commit`, `sudo apt update`) pass through untouched. **Zero interference.**

---

## Any language

LinuxGenie detects your language automatically and always replies in the same language you used:

```bash
how do I check open ports              # → English
como listar ficheiros ocultos          # → Portuguese  
comment lister les fichiers cachés     # → French
cómo ver el espacio en disco           # → Spanish
wie zeige ich offene Ports             # → German
```

---

## What the installer does

| Step | Action |
|---|---|
| 1 | Detects your distro, architecture and RAM |
| 2 | Installs dependencies (python3, curl, unzip) |
| 3 | Installs Ollama (local AI engine) |
| 4 | Registers Ollama as a systemd service (starts on boot) |
| 5 | Downloads the AI model best suited to your hardware |
| 6 | Installs the LinuxGenie agent |
| 7 | Adds the hook to your ~/.bashrc or ~/.zshrc |

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

# Explicit mode also works:
genie how to check disk usage by folder
lg what is the difference between hard and soft links
```

---

## Controls

```bash
genie on                   # enable automatic hook
genie off                  # disable (terminal works normally)
genie status               # show current status
genie model llama3.2       # switch Ollama model

linuxgenie-uninstall       # remove completely
```

---

## AI Model

The installer picks the **best model for Linux knowledge**, not just the smallest:

| Available RAM | Model | Size | Why |
|---|---|---|---|
| ≥ 8 GB | `qwen2.5-coder:7b` | 4.4 GB | Trained on code, man pages and system commands — best for this agent |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB | Good Linux knowledge, lower RAM footprint |
| < 5 GB | `qwen2.5:3b` | 1.9 GB | Best available lightweight option |

`qwen2.5-coder:7b` covers: bash/zsh scripting · systemd · networking (ip, ss, iptables, SSH) · package managers (apt, dnf, pacman) · text tools (grep, awk, sed, jq) · Docker · Git · and more.

To switch model at any time:
```bash
ollama pull mistral
genie model mistral
```

---

## 🔒 Data Sovereignty

LinuxGenie was designed from the ground up for environments where **data cannot leave the server.**

- All AI processing runs locally via Ollama — no external calls, ever
- No data is sent to any server, cloud provider or third party
- No API keys. No accounts. No usage tracking.
- Works fully **air-gapped** — no internet required after installation
- Compatible with **GDPR**, **NIS2** and **Swiss nDSG** requirements

**Independently verified** — zero external traffic:

```
$ sudo tcpdump -i any host ollama.com &
$ genie how do I list open ports

tcpdump: listening on any, link-type LINUX_SLL2
[... LinuxGenie answers fully ...]
^C
0 packets captured
0 packets received by filter
```

Not a single packet left the server. You can reproduce this test yourself at any time.

**Ideal for:** financial services · healthcare · legal · government · any environment with sensitive data.

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

## Why LinuxGenie vs alternatives

| | LinuxGenie | ShellGPT | Warp | GitHub Copilot CLI |
|---|---|---|---|---|
| 100% local | ✅ | ❌ | ❌ | ❌ |
| No API key | ✅ | ❌ | ❌ | ❌ |
| Free forever | ✅ | ❌ | ❌ | ❌ |
| Works offline | ✅ | ❌ | ❌ | ❌ |
| Transparent hook | ✅ | ❌ | ❌ | ❌ |
| One-line install | ✅ | ❌ | ❌ | ❌ |
| Multilingual | ✅ | partial | ❌ | ❌ |
| GDPR / nDSG safe | ✅ | ❌ | ❌ | ❌ |

---

## Uninstall

```bash
linuxgenie-uninstall
```

Removes the agent, the hook and all config files. Ollama and models are kept (remove manually if needed):

```bash
sudo systemctl stop ollama
sudo rm $(which ollama)
rm -rf ~/.ollama
```

---

## Repository

```
linuxgenie/
├── setup.sh     ← complete self-contained installer
└── README.md
```

`setup.sh` contains everything: installer, Python agent, shell hook and uninstaller. One file. Zero external dependencies beyond `python3`, `curl` and `bash`.

---

## Contributing

Issues, pull requests and feedback welcome at [github.com/deltaxmodules/linuxgenie](https://github.com/deltaxmodules/linuxgenie).

---

<div align="center">
<sub>Built with ❤️ · Powered by <a href="https://ollama.com">Ollama</a> · 100% local · 100% private</sub>
</div>
