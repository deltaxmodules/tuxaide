# Privacy: what is kept and where

Everything stays on your computer, unless you set up a [remote backend](/guide/remote-backends). There's no telemetry. TuxAide only goes online when you run `tuxaide update` (to GitHub) or download a model (from Ollama).

## What is sent to the model

Your question; with a follow-up, the last 3 exchanges; with `?`, the failed command line, its exit code and the error it printed when re-run; with `system_context` on, a one-line description of your system (`tuxaide system` shows it). With the default setup, “the model” is Ollama on your own computer.

## What is never sent

TuxAide only sees a line when the shell can't find its first word as a command, and only sends it if it reads like a question ([how it knows](/guide/how-it-knows)). Your normal commands never reach it.

**A password typed at the prompt by mistake** isn't a question: you get the normal “command not found”, nothing goes to a model and TuxAide writes nothing to disk. Your shell's own history keeps the line, as it would without TuxAide. If a line *is* taken as a question, it's sent and kept as in the table below — `tuxaide new` and `tuxaide cache clear` remove it.

## What is kept, and how to delete it

| What | Where | How to delete |
| --- | --- | --- |
| Settings | `~/.config/tuxaide/config.json` | `tuxaide config reset <key>` |
| Your last 20 questions and the start of each answer (for follow-ups) | `~/.config/tuxaide/history.json` — only you can read it | `tuxaide new` |
| Cached answers (30 days) | `~/.config/tuxaide/cache/` | `tuxaide cache clear` |
| Output of `tuxaide run` | `~/.config/tuxaide/session.json` — only you can read it | `rm ~/.config/tuxaide/session.json` |
| Timings and the first 80 characters of each question | `~/.config/tuxaide/logs/perf.log` | `rm ~/.config/tuxaide/logs/perf.log` |
| Man-page index (Smart RAG) | `~/.config/tuxaide/vectordb/` | `tuxaide mode llm`, then delete the folder |
| The last command line and its exit code (for `?`) | your shell's memory — never on disk | closing the terminal |

`tuxaide uninstall` removes all of it.

## What TuxAide never does

- Run a command on its own. Commands go on your prompt; you press Enter. The one exception is `?` re-running your last command to read its error — read-only commands without asking, anything else only after **y**.
- Store an API key. Keys are read from an environment variable.
- Check for updates in the background.
