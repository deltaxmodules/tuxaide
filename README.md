# 🐧 TuxAide

> **Stop searching. Just ask your terminal.**
> Type a Linux question as if it were a command and get the answer right there — from a model running on your own computer.

<div align="center">

[![CI](https://github.com/deltaxmodules/tuxaide/actions/workflows/ci.yml/badge.svg)](https://github.com/deltaxmodules/tuxaide/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.3.0-informational)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Powered%20by-Ollama-blue)](https://ollama.com)
[![Shell: bash/zsh](https://img.shields.io/badge/Shell-bash%20%7C%20zsh-lightgrey)](#requirements)
[![Privacy: local by default](https://img.shields.io/badge/Privacy-local%20by%20default-brightgreen)](#privacy-what-is-kept-and-where)

![TuxAide: a question typed in the terminal, the answer streaming in, its command put on the prompt, then a failed command explained by ?](site/public/img/tuxaide-demo.gif)

**[Manual](https://deltaxmodules.github.io/tuxaide/)** · [Demo video](https://deltaxmodules.github.io/tuxaide/#see-it-in-90-seconds) · [Changelog](CHANGELOG.md)

</div>

```bash
$ how do I list hidden files sorted by size
```

```
╭──────────────────────────────────────────────────────────────╮
╞═ 🐧 TuxAide (Ollama · qwen2.5-coder:7b · Smart RAG) ═╡
  To list hidden files sorted by size:

  ┄ shell ┄
  [1] ls -laSh
  [2] ls -laShr
  ┄┄┄┄┄┄┄┄┄

  -a shows hidden files, -S sorts by size (largest first), -h shows
  human-readable sizes. Add -r to reverse the order.

  Source: man ls(1)
╰──────────────────────────────────────────────────────────────╯
  1-2 put on prompt · c copy · Enter skip
```

- **No trigger word.** Just type the question. Real commands (`ls -la`, `git commit`) run as always.
- **It never runs anything on its own.** Press `1` and the command lands on your prompt, ready to edit; you press Enter.
- **Local by default.** A model on your machine through [Ollama](https://ollama.com). No account, no API key.
- **`?` explains the last error**, typos get fixed (`gti status` → `git status`), follow-ups work (“and by size?”), and answers fit your system (`dnf` on Fedora, `brew` on macOS).
- **Any language**: `como listar ficheiros ocultos`, `comment voir l'espace disque`, `wie zeige ich offene Ports`.

---

## Install

**One command** (Linux and macOS). It installs Ollama, picks the model that fits your RAM and sets up your shell:

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

Before changing anything it lists what it will do — packages, `sudo`, files, download size — and asks once.
Files come from the tagged release and are checked against its `SHA256SUMS`.
Options: `… | bash -s -- --yes` (no questions), `--no-rag`, `--model <name>`.

**Or with your package manager**, then run `tuxaide setup` once (model, Smart RAG, shell):

| | |
| --- | --- |
| Homebrew (macOS, Linux) | `brew install deltaxmodules/tap/tuxaide` |
| Arch Linux (AUR) | `yay -S tuxaide` |
| pipx (any system with Python 3.9+) | `pipx install tuxaide` — with Smart RAG: `pipx install 'tuxaide[rag]'` |

Then open a new terminal and type a question. Something off? Run **`tuxaide doctor`**: it checks
everything and gives the command that fixes each problem.

**Uninstall:** `tuxaide uninstall` removes only the lines TuxAide added to your shell rc
(keeping a backup) and its own files; remove the package afterwards if you used one.

---

## How does it know it's a question?

1. TuxAide only looks at a line when the shell can't find its first word as a command — so `ls`, `git`, your aliases and functions are never touched.
2. Then the line is a question if it has a question word (*how, what, why, como, porque, comment, wie, cómo…*) or ends with `?`. Anything else gets a typo suggestion or the normal “command not found”.
3. Right after a question, a short follow-up counts too (“and by size”, “e ao contrário”).

To **force** a question that starts with a real command — `find big files?` would run `find` — prefix it:
`tuxaide find big files`. To **stop** TuxAide answering: `tuxaide off` (remembered in new terminals; `tuxaide on` to resume).

---

## What it does

### Put the command on your prompt

Commands in an answer are numbered. Press the number: in **zsh** it appears on your prompt; in **bash**
press **↑** to bring it up (bash can't pre-fill the prompt). **c** copies it instead (also over SSH,
through OSC 52). Destructive commands (`rm -rf`, `dd`, `mkfs`…) carry a warning and ask before going
on the prompt.

### `?` explains the last error

```
$ ls /var/log/nginx
ls: /var/log/nginx: No such file or directory
💡 exit 1 — type ? to ask TuxAide why
$ ?
```

`? <question>` asks something specific; asking in words (“why did this fail?”) works too.
TuxAide remembers only the last command line and its exit code — never its output. To read the
error it re-runs the command: read-only commands straight away, anything else only after you answer **y**.

### Typos

```
$ gti status
zsh: command not found: gti
🐧 Did you mean: git status  [Enter/y] put on prompt · other key skips
```

Instant, without the model: it knows your `PATH`, aliases and functions, and fixes missing spaces
(`cd..`, `ls-la`). Your shell's own handler (Ubuntu's “install it with apt”, oh-my-zsh's) still answers
for commands TuxAide has nothing to say about.

### Follow-ups and history

The conversation stays open for 10 minutes: `como listar ficheiros ocultos` → `e por tamanho?` →
`e ao contrário?`. `tuxaide new` starts over; `tuxaide history` lists your recent questions.

### Smart RAG: answers from your man pages

With Smart RAG on, questions about a specific command are answered from the man pages installed on
*your* system, with the source cited (`Source: man rsync(1)`). Man pages are indexed in the background
after install; general questions skip it and stay fast. `tuxaide mode llm|smart|deep` switches.

### Answers for your system

The model is told your OS, package manager, shell and init system — never user names, host names or
paths — so you get `dnf` on Fedora and `brew` on macOS. See exactly what is sent with `tuxaide system`.

### Remote backends (optional)

Local is the default and stays that way unless you change it. On a small machine, or with a model
server you already run, point TuxAide at Ollama on another computer
(`tuxaide config set ollama_url http://192.168.1.10:11434`) or any OpenAI-compatible API — LM Studio,
llama.cpp server, vLLM, a cloud service (`tuxaide config set backend openai`,
`tuxaide config set api_base …`). Whenever a question leaves your computer, the answer is marked
**☁ remote · host**, and `status` and `doctor` say so. API keys are read from an environment variable
(`OPENAI_API_KEY`, or the name in `api_key_env`) and never written to any file.

---

## Commands

```bash
tuxaide <question>           # ask (or just type the question)
?  [question]                # explain the last command that failed
tuxaide new | history        # new conversation · recent questions
tuxaide on | off | status
tuxaide doctor               # check everything, with fixes
tuxaide setup                # model, Smart RAG and shell (after a package install)
tuxaide config [get|set|reset] <key> [value]
tuxaide model [name]         # list models · switch (offers to download it)
tuxaide mode llm|smart|deep
tuxaide system               # what is sent about this machine
tuxaide run <cmd>            # run a command and keep its output for the next question
tuxaide index <cmd> | reindex
tuxaide cache [clear]
tuxaide update [--check]     # only contacts GitHub when you run it
tuxaide uninstall
tuxaide --version | --timing
```

All settings, with what they do: [the manual](https://deltaxmodules.github.io/tuxaide/reference/settings).

---

## How it compares

| | TuxAide | [tldr](https://github.com/tldr-pages/tldr) | [ShellGPT](https://github.com/TheR1D/shell_gpt) | [GitHub Copilot CLI](https://github.com/github/copilot-cli) |
| --- | --- | --- | --- | --- |
| Ask without a command word | Yes — type the question | No — `tldr tar` | No — `sgpt "…"` | No — `copilot` |
| Works offline | Yes — local model by default | Yes — clients cache the pages | With a local backend (Ollama); “not optimized for local models” | No |
| Explains errors | Yes — `?` | No | Yes — chat / REPL | Yes — agent |
| Runs commands | Never on its own: you press Enter | No | After you choose **[E]xecute** | After your approval (or in autopilot mode) |
| Needs an account or key | No | No | An OpenAI API key by default | A Copilot subscription |

Checked on 2026-10-04 against each project's page (linked). tldr is great for examples of one command;
ShellGPT and Copilot CLI are general assistants that can act for you. TuxAide sits in between:
it answers inside your shell, from a local model, and leaves the running to you.

---

## Privacy: what is kept and where

Everything stays on your computer (unless you set up a [remote backend](#remote-backends-optional)).
No telemetry. TuxAide only goes online for `tuxaide update` and for downloading models when you ask.

| What | Where | How to delete |
| --- | --- | --- |
| Settings | `~/.config/tuxaide/config.json` | `tuxaide config reset <key>` |
| Your last 20 questions and the start of each answer (for follow-ups) | `~/.config/tuxaide/history.json` (only you can read it) | `tuxaide new` |
| Cached answers (30 days) | `~/.config/tuxaide/cache/` | `tuxaide cache clear` |
| Output of `tuxaide run` | `~/.config/tuxaide/session.json` (only you can read it) | `rm ~/.config/tuxaide/session.json` |
| Timings and the first 80 characters of each question | `~/.config/tuxaide/logs/perf.log` | `rm ~/.config/tuxaide/logs/perf.log` |
| Man-page index (Smart RAG) | `~/.config/tuxaide/vectordb/` | `tuxaide mode llm`, then delete it |
| The last command line and its exit code (for `?`) | your shell's memory only | closing the terminal |

`tuxaide uninstall` removes all of it.

---

## Requirements

Linux or macOS, **bash 4+ or zsh**, Python 3.9+. The installer picks the model that fits your RAM:

| RAM | Model | Download | Answers |
| --- | --- | --- | --- |
| 8 GB or more | `qwen2.5-coder:7b` | 4.7 GB | Best |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB | Good |
| 3–5 GB | `qwen2.5:1.5b` | 986 MB | Simpler, but usable |
| under 3 GB | `qwen2.5:0.5b`, or a [remote backend](#remote-backends-optional) | 398 MB | Basic |

Smart RAG needs 5 GB or more. Switch models any time with `tuxaide model <name>`. A GPU makes answers
faster but isn't needed. Tested on Ubuntu, Debian, Fedora, Arch, Alpine and macOS (zsh; macOS's own
bash 3.2 is too old — use zsh or `brew install bash`).

---

## FAQ

**Does it interfere with my scripts?** No. The hook is only loaded in interactive shells, and it only
acts on lines whose first word isn't a command. Scripts run exactly as before.

**Does it work over SSH?** Yes, on the machine where it's installed. `c` copies to your local clipboard
through OSC 52 when your terminal supports it.

**oh-my-zsh and other frameworks?** TuxAide adds itself with `add-zsh-hook`, next to whatever else
your setup runs, and keeps the command-not-found handler that was there before (such as the one
oh-my-zsh's plugin defines). Load TuxAide last in your rc file; `tuxaide doctor` checks that nothing
replaced it. Prompt themes like starship and powerlevel10k haven't been tested yet — reports welcome.

**fish?** Not yet: TuxAide works in bash and zsh.

**Is a question sent anywhere?** Only to the model you configured — the local Ollama by default.
`tuxaide status` says where answers come from.

**Can it run something dangerous?** It never runs a command on its own. Commands go on your prompt
for you to read; destructive ones are flagged first. The one exception is `?` re-running your last
command to read its error — only read-only commands without asking.

---

## Contributing

Bug reports, fixes and ideas are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (the tests need no
Ollama) and [SECURITY.md](SECURITY.md). When reporting a bug, please paste the output of `tuxaide doctor`.

[Changelog](CHANGELOG.md) · [MIT License](LICENSE) · Built with the help of AI tools (Claude, Ollama).
