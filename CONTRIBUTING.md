# Contributing to TuxAide

Thanks for helping. Bug reports, fixes and new ideas are all welcome.

## Project layout

| File | What it is |
| --- | --- |
| `agent.py` | The `tuxaide` command: question detection, Ollama calls, answer rendering, `?`, typo suggestions |
| `hook.sh` | Sourced from `~/.bashrc` / `~/.zshrc`: the command-not-found handler, prompt hooks, `?` alias |
| `install.sh` / `setup.sh` | Installer (`setup.sh` downloads and runs `install.sh`) |
| `indexer.py` | Builds the man-page knowledge base for Smart RAG |
| `session_writer.py` | Saves the output of `tuxaide run` for follow-up questions |
| `tests/` | The test suite |

## Running the tests

```bash
python3 -m pip install pytest
python3 -m pytest
```

No Ollama is needed: the tests start a fake one. `tests/test_shell_pty.py`
starts real interactive **zsh** and **bash** sessions in a pseudo-terminal and
types into them, so the hook is tested the way people use it. Shells that
aren't installed are skipped (macOS's `/bin/bash` 3.2 is skipped too: it has no
command-not-found hook).

## Linting

```bash
shellcheck -S warning hook.sh install.sh setup.sh uninstall.sh
python3 -m pip install ruff && ruff check .
```

CI runs both, plus the tests on Linux (Python 3.9, 3.12, 3.13) and macOS.

## Releasing

The version lives in `__version__` in `agent.py`. To release:

1. Bump `__version__`, `TUXAIDE_VERSION` in `install.sh` and the version badge in
   `README.md` (`tests/test_version.py` fails if they differ).
2. Merge to `main`, then create a GitHub release tagged `v<version>` (e.g. `v2.3.0`).

`tuxaide update` installs the files of the latest release's tag and checks that
`agent.py` there carries the same version as the tag, so the tag and
`__version__` must match.

## Ground rules

- **TuxAide never runs a command on its own.** It explains, suggests and puts
  commands on the prompt; the person presses Enter. The one exception is `?`
  re-running a command to read its error: only read-only commands run without
  asking (`SAFE_RERUN` in `agent.py`).
- **Nothing leaves the machine** unless the user configures it.
- **The hook runs on every prompt.** Keep it cheap: no Python or subshells per
  prompt unless something actually happened.
- Change bash and zsh together, and add a test in `tests/test_shell_pty.py`
  for anything you change in `hook.sh`.
