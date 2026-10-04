# How it compares

| | TuxAide | [tldr](https://github.com/tldr-pages/tldr) | [ShellGPT](https://github.com/TheR1D/shell_gpt) | [GitHub Copilot CLI](https://github.com/github/copilot-cli) |
| --- | --- | --- | --- | --- |
| Ask without a command word | Yes — type the question | No — `tldr tar` | No — `sgpt "…"` | No — `copilot` |
| Works offline | Yes — local model by default | Yes — clients cache the pages | With a local backend (Ollama); “not optimized for local models” | No |
| Explains errors | Yes — `?` | No | Yes — chat / REPL | Yes — agent |
| Runs commands | Never on its own: you press Enter | No | After you choose **[E]xecute** | After your approval (or in autopilot mode) |
| Needs an account or key | No | No | An OpenAI API key by default | A Copilot subscription |

Checked on 2026-10-04 against each project's page (linked above).

- **tldr** is great for quick examples of one command you already know the name of.
- **ShellGPT** and **GitHub Copilot CLI** are general assistants that can act for you, usually with a cloud model.
- **TuxAide** sits in between: it answers inside your shell, from a model on your computer, and leaves the running to you.

Something here out of date? [Open an issue](https://github.com/deltaxmodules/tuxaide/issues).
