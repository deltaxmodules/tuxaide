# Security

## Reporting a vulnerability

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a public
issue for them.

Include what you found, how to reproduce it, and which version (`git log -1`)
you tested.

## What TuxAide does on your machine

- It hooks the shell's *command not found* handler and prompt. It never runs a
  command on its own.
- `?` re-runs your last command to read its error. Only read-only commands (a
  fixed list in `agent.py`, without redirections or pipes) run without asking;
  anything else needs you to press `y`.
- Data stays in `~/.config/tuxaide/` (config, answer cache, `session.json`, `history.json`,
  performance log) and, for Smart RAG, `~/.local/share/tuxaide/venv`.
  `session.json` can hold command output, so it is created readable by you only.
- Questions go to the Ollama server set in `ollama_url` (by default
  `http://localhost:11434`), together with a one-line description of the
  system (OS, package manager, shell, init, CPU architecture — see
  `tuxaide system`; turn off with `system_context`). No user names, host
  names or paths.
