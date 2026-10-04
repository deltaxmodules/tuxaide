# Install and first question

TuxAide installs in one command, or from your package manager. Either way you end up with the `tuxaide` program, a small hook in your shell, and a model running locally through [Ollama](https://ollama.com).

## One command (Linux and macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

1. It looks at your system and picks the model that fits your RAM ([which one](/guide/models-and-memory)).
2. It asks its questions (Smart RAG yes or no; on very small machines, a [remote backend](/guide/remote-backends)).
3. It shows **everything it will do** — packages, `sudo`, Ollama, the model and its download size, the files it writes, the lines it adds to your shell rc — and asks once.
4. It downloads TuxAide's files from the tagged release and checks them against the release's `SHA256SUMS` **before installing anything**.
5. It installs Ollama (if needed) and runs `tuxaide setup`, which downloads the model, writes the settings, adds TuxAide to your shell and runs [`tuxaide doctor`](/guide/troubleshooting).

Options, after `bash -s --`:

| Option | What it does |
| --- | --- |
| `--yes` | No questions: the recommended answers |
| `--no-rag` | Skip [Smart RAG](/guide/smart-rag) |
| `--model <name>` | Use this Ollama model instead of the one picked for your RAM |

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash -s -- --yes --no-rag
```

## With your package manager

| | Install | Then |
| --- | --- | --- |
| Homebrew (macOS, Linux) | `brew install deltaxmodules/tap/tuxaide` | `brew services start ollama`, `tuxaide setup` |
| Arch Linux | the PKGBUILD from the release (below) | `sudo systemctl enable --now ollama`, `tuxaide setup` |
| pipx (any system with Python 3.9+) | `pipx install tuxaide` (Smart RAG: `pipx install 'tuxaide[rag]'`) | install [Ollama](https://ollama.com/download), `tuxaide setup` |

On Arch, until the AUR package is published (AUR sign-ups are paused), build it from the release's PKGBUILD:

```bash
mkdir tuxaide && cd tuxaide && curl -fL --remote-name-all https://github.com/deltaxmodules/tuxaide/releases/latest/download/{PKGBUILD,tuxaide.install} && makepkg -si
```

`tuxaide setup` does the part a package can't: it picks and downloads the model, offers Smart RAG, and adds TuxAide to your shell. Options: `--yes`, `--model <name>`, `--rag` / `--no-rag`, `--shell zsh|bash`. You can run it again any time.

## Your first question

Open a new terminal (or `source ~/.zshrc` / `source ~/.bashrc`) and type:

```bash
how do I find files bigger than 100MB in this folder
```

The answer streams in. Press `1` to put its command on your prompt, then Enter to run it.

## Uninstall

```bash
tuxaide uninstall
```

It removes the lines TuxAide added to your shell rc — the block between `# >>> TuxAide >>>` and `# <<< TuxAide <<<`, nothing else, with a backup next to the file — plus TuxAide's settings and data. With a package, remove it afterwards (`brew uninstall tuxaide`, `pipx uninstall tuxaide`, `sudo pacman -R tuxaide`). Ollama and its models stay; `ollama rm <model>` frees their space.
