# Something not working?

## Start with `tuxaide doctor`

```text
$ tuxaide doctor
🐧 TuxAide 2.3.0 — doctor
   Ubuntu 24.04 LTS x86_64 · Python 3.12.3 · shell bash

  ✓ Settings: ~/.config/tuxaide/config.json
  ✗ Ollama isn't answering at http://localhost:11434
    → sudo systemctl start ollama
  · Mode LLM: the man-page knowledge base isn't used
  ✓ Hook in ~/.bashrc
  ✓ TuxAide answers unknown commands in this shell

1 problem(s), 0 warning(s). Run the commands after → to fix them.
```

It checks the settings, Ollama, the model, the embedding model, ChromaDB and the man-page index (in Smart/Deep mode), the hook in your rc file and in the current shell — including whether another command-not-found handler replaced it — your `PATH` and free memory. Every problem comes with the command that fixes it, for your system. It exits with 1 when something is broken, so it also works in scripts. **Please paste its output in bug reports.**

## Common problems

| Problem | Fix |
| --- | --- |
| Questions get “command not found” | Open a new terminal, or `source ~/.zshrc`. Check `tuxaide status` (maybe it's off: `tuxaide on`). |
| “Ollama not available” | Start it: `open -a Ollama` or `brew services start ollama` (macOS), `sudo systemctl start ollama` (Linux). `tuxaide doctor` gives the right one. |
| “model not found” | `ollama pull <model>`, or pick an installed one: `tuxaide model` |
| Slow answers | A smaller model (`tuxaide model qwen2.5:3b`), `prewarm` on, or close memory-hungry programs. See [models and memory](/guide/models-and-memory). |
| TuxAide answers something that was a command | The first word wasn't found as a command — check the spelling or your `PATH`. |
| A question runs as a command | It starts with a real command (`find …`): ask with `tuxaide find …`. |
| macOS bash | macOS's own bash 3.2 has no command-not-found hook: use zsh (the default) or `brew install bash`. |

## Updating

```bash
tuxaide update --check    # is there a newer release?
tuxaide update            # download it, keeping settings, history and cache
```

The new files are checked against the release's `SHA256SUMS` before anything is replaced, and the new hook is loaded into the current terminal. With Homebrew, the AUR or pipx, update with them instead (`brew upgrade tuxaide`, `pacman`, or the new release's PKGBUILD on Arch, `pipx upgrade tuxaide`) — `tuxaide update` tells you so.

## FAQ

**Does it interfere with my scripts?** No. The hook is only loaded by interactive shells, and only acts on lines whose first word isn't a command.

**Does it work over SSH?** Yes, on the machine where it's installed. `c` copies to your local clipboard through OSC 52 when your terminal supports it.

**oh-my-zsh and other frameworks?** TuxAide adds itself with `add-zsh-hook`, next to whatever else runs, and keeps the command-not-found handler that was there before. Load TuxAide last in your rc file. Prompt themes like starship and powerlevel10k haven't been tested yet.

**fish?** Not yet: bash and zsh.

**Where do I report a bug?** [GitHub issues](https://github.com/deltaxmodules/tuxaide/issues), with the output of `tuxaide doctor`.
