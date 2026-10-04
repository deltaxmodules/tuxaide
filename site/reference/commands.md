# Commands

| Command | What it does |
| --- | --- |
| *your question* | Ask — just type it ([how it's recognised](/guide/how-it-knows)) |
| `tuxaide <question>` | Ask explicitly (also for questions that start with a real command) |
| `?` · `? <question>` | Explain the last command that failed ([details](/guide/when-a-command-fails)) |
| `tuxaide new` | Start a new conversation (forget follow-ups) |
| `tuxaide history` | Your recent questions |
| `tuxaide on` · `tuxaide off` | Enable / disable TuxAide, also in new terminals |
| `tuxaide status` | On or off, mode, model, and where answers come from |
| `tuxaide doctor` | Check everything, with fixes ([details](/guide/troubleshooting)) |
| `tuxaide setup [--yes] [--model <name>] [--rag \| --no-rag] [--shell zsh\|bash]` | Model, Smart RAG and shell — after a package install, or any time |
| `tuxaide config` | Show all settings |
| `tuxaide config get <key>` · `set <key> <value>` · `reset <key>` | Read, change (validated) or reset one setting ([settings](/reference/settings)) |
| `tuxaide model` · `tuxaide model <name>` | List models · switch (offers `ollama pull`) |
| `tuxaide mode llm\|smart\|deep` | Knowledge mode ([Smart RAG](/guide/smart-rag)) |
| `tuxaide system` | What is sent about this machine |
| `tuxaide run <command>` | Run a command and keep its output for the next question |
| `tuxaide index <command>` · `tuxaide reindex` | Add one man page · rebuild the index |
| `tuxaide cache` · `tuxaide cache clear` | Cache size · empty it |
| `tuxaide update [--check]` | Update to the latest release (only contacts GitHub when you run it) |
| `tuxaide uninstall [--yes] [--keep-data]` | Remove TuxAide's shell lines and data (asks first) |
| `tuxaide --timing` | How long recent questions took |
| `tuxaide --version` · `tuxaide help` | Version · this list |

`tux` is a short alias for `tuxaide` when nothing else is called `tux`.

## Installer options

`install.sh` (or `setup.sh | bash -s --`): `--yes`, `--no-rag`, `--model <name>`, `--help`.
