# TuxAide

Type Linux questions directly in your terminal — no trigger word, no cloud, never executes commands.

```bash
$ how do I list hidden files sorted by size
```

```
╭──────────────────────────────────────────────────────────────╮
╞═ TuxAide (Ollama · qwen2.5-coder:7b · Smart RAG) ═╡

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

Normal commands (`ls -la`, `git commit`, `sudo apt update`) pass through untouched. Zero interference.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

Handles everything: Ollama, the AI model, the shell hook. One command, no manual steps.

```bash
source ~/.bashrc   # Linux
source ~/.zshrc    # macOS
```

---

## Why this is different from every other AI terminal tool

**No trigger word.** Every other tool requires `ask`, `hey`, `lumo` or similar. TuxAide hooks into the shell's `command_not_found` handler — you type your question as if it were a command and it responds. No prefix, no mode switch.

**Never executes.** Tools like Billy and Shell Sage can run commands on your behalf. TuxAide deliberately does not. It explains and shows examples. You decide what runs.

**100% local — not as an option, as the only mode.** No API key. No account. No cloud. Nothing leaves your machine. Works fully air-gapped after installation.

---

## Honest limitations

AI models hallucinate. TuxAide is no exception. It is advisory only — a starting point, not a source of truth. Always review a command before running it, especially if it involves permissions, disk operations or services.

When a response contains a potentially destructive command (`rm -rf`, `dd`, `mkfs`, `fdisk`, `chmod 777`), TuxAide shows a visible warning before the code block — even when the answer comes from cache.

---

## How the RAG works (v2.1)

TuxAide can index the man pages installed on your system and use them as a knowledge base. The key design decision in v2.1: **RAG is not used by default for every question.** A router classifies each question first.

```
question → router → cache?         → instant (< 1s)
                  → needs docs?
                      no  → LLM direct    → 3–5s
                      yes → RAG filtered  → 8–15s
```

When RAG is used, the query is filtered to the relevant command's chunks rather than searching across all indexed man pages. A `chmod` question searches only `chmod` chunks.

Response times:

| Question type | Speed |
|---|---|
| Repeated question (cache hit) | < 1s |
| Simple / general | 3–5s |
| Command-specific (Smart RAG) | 8–15s |
| Full documentation (`mode deep`) | 15–25s |

---

## Verified — zero external traffic

```bash
$ sudo tcpdump -i any host ollama.com &
$ tuxaide how do I list open ports

tcpdump: listening on any, link-type LINUX_SLL2
[... TuxAide answers fully ...]
^C
0 packets captured
0 packets received by filter
```

You can reproduce this test yourself at any time.

---

## Any language

TuxAide detects the language of the question and replies in the same language.

```bash
how do I check open ports              # → English
como listar ficheiros ocultos          # → Portuguese
comment lister les fichiers cachés     # → French
cómo ver el espacio en disco           # → Spanish
wie zeige ich offene Ports             # → German
```

---

## Controls

```bash
tuxaide on / off             # enable / disable hook
tuxaide status               # current status and mode
tuxaide model llama3.2       # switch Ollama model

tuxaide mode smart           # Smart RAG (default)
tuxaide mode deep            # full RAG for every question
tuxaide mode llm             # LLM only, no man pages

tuxaide --timing             # show recent query latency log
tuxaide reindex              # re-index all man pages
tuxaide index nginx          # index a specific command

tuxaide-uninstall            # remove completely
```

---

## Performance log

Every query is silently logged to `~/.config/tuxaide/logs/perf.log`.

```bash
tuxaide --timing
```

```
2025-05-04T18:32:11   smart   embed=2.4s  rag=0.3s  llm=6.1s  total=8.8s  cache=miss
2025-05-04T18:34:02   smart   embed=0.0s  rag=0.0s  llm=0.0s  total=0.0s  cache=hit
2025-05-04T18:41:55   llm     embed=0.0s  rag=0.0s  llm=4.2s  total=4.2s  cache=miss
```

---

## AI model selection

| Available RAM | Model | Size |
|---|---|---|
| ≥ 8 GB | `qwen2.5-coder:7b` | 4.4 GB |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB |
| < 5 GB | `qwen2.5:3b` | 1.9 GB |

`qwen2.5-coder:7b` was chosen specifically because it was trained on code, man pages and system documentation — not because it is the most popular model.

Minimum RAM: 5 GB. Recommended: 8 GB+.

---

## Requirements and compatibility

| Platform | Support |
|---|---|
| Ubuntu / Debian | Full |
| Fedora / RHEL / CentOS | Full |
| Arch Linux | Full |
| openSUSE | Full |
| Raspberry Pi (arm64) | Full |
| ARM servers (AWS Graviton, Oracle ARM) | Full |
| macOS (Intel + Apple Silicon) | Full |

Shells: bash and zsh.

---

## Comparison

| | TuxAide | Lexido | Billy | Shell Sage | ask.sh |
|---|---|---|---|---|---|
| 100% local by default | Yes | No (cloud) | Yes | Yes | Partial |
| No API key | Yes | No | Yes | Yes | No |
| No trigger word | Yes | No | No | No | No |
| Never executes | Yes | Yes | No | No | No |
| One-line install | Yes | No | Yes | No | No |
| Multilingual | Yes | No | No | No | No |
| Smart RAG router | Yes | No | No | No | No |
| Answer cache | Yes | No | No | No | No |
| Destructive warnings | Yes | No | No | Partial | No |
| GDPR / air-gap safe | Yes | No | Partial | Partial | No |

---

## What changed in v2.1

- Smart router — RAG only when the question needs local documentation
- Answer cache — MD5-keyed, normalized, instant hits on repeated queries
- Embedding cache — never recalculated for the same text
- RAG filtered by detected command — faster, less noise in context
- RAG timeout — falls back to LLM silently if ChromaDB takes more than 8s
- Smaller chunks — 200 words instead of 400
- top_k reduced — 1 in smart mode, 3 in deep mode
- max_tokens reduced — 300 in smart/llm, 600 in deep
- Destructive command warnings before code blocks
- Silent perf log with per-stage latency breakdown
- `tuxaide --timing` to inspect the last 10 queries
- Pre-warm on session start — model stays loaded in RAM

---

## macOS notes

macOS uses zsh by default. After installing:

```bash
source ~/.zshrc
```

If TuxAide does not respond, add the hook manually:

```bash
echo 'source "$HOME/.config/tuxaide/hook.sh"  # TuxAide' >> ~/.zshrc
source ~/.zshrc
```

On macOS, Ollama runs as a desktop app. If the automatic installer fails, download it from [ollama.com](https://ollama.com), open it once, then re-run the TuxAide installer.

---

## Updating from v2.0

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
source ~/.bashrc      # or ~/.zshrc on macOS
tuxaide mode smart
```

Ollama, models and the man page index are preserved. Only the agent binary and hook are updated.

---

## Uninstall

```bash
tuxaide-uninstall
```

Removes the agent, hook, cache and config. Ollama and models are kept.

---

## Repository

```
tuxaide/
├── setup.sh     ← complete self-contained installer
└── README.md
```

`setup.sh` contains everything: installer, Python agent, shell hook, indexer and uninstaller. One file. No external dependencies beyond `python3`, `curl` and `bash`.

[github.com/deltaxmodules/tuxaide](https://github.com/deltaxmodules/tuxaide)

---

<sub>Named after Tux, the Linux mascot · Powered by [Ollama](https://ollama.com) · 100% local · 100% private · Built for beginners</sub>