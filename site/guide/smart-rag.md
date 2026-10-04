# Smart RAG: answers from your man pages

A model knows commands in general. Your system has the exact documentation for the versions you have installed: its man pages. With **Smart RAG**, TuxAide answers questions about a specific command from those man pages, and cites them:

```text
$ what does the -z flag do in grep
  …
  This command will search for "pattern" in file.txt, treating null
  characters as line separators.

  Source: man grep(1)
```

## Fast when simple, precise when needed

TuxAide decides per question. “how do I create a folder” goes straight to the model; “rsync options to exclude files” mentions a command, so the matching man page is looked up first. If the lookup takes too long (`rag_timeout`, 8 s), the model answers alone.

| Mode | What it does |
| --- | --- |
| `llm` | Model only (the default) |
| `smart` | Man pages when the question needs them (recommended) |
| `deep` | Man pages for every question, longer answers |

```bash
tuxaide mode smart
```

## Turning it on

- **Installer**: answer **Y** to Smart RAG (needs 5 GB of RAM or more).
- **Any install**: `tuxaide setup --rag`.

TuxAide then installs ChromaDB in its own virtualenv (`~/.local/share/tuxaide/venv` — never your system Python, no `pip` needed), downloads the embedding model `nomic-embed-text` (274 MB), switches to `smart`, and **indexes about 150 common man pages in the background** — a few minutes. You can use TuxAide meanwhile; until indexing finishes, answers come from the model alone. `tuxaide doctor` shows the progress; the log is in `~/.config/tuxaide/logs/index.log`.

With pipx, `pipx install 'tuxaide[rag]'` puts ChromaDB in TuxAide's own pipx environment instead.

## Your own commands

```bash
tuxaide index nginx    # add one man page
tuxaide reindex        # rebuild the whole index (after big system updates)
```
