# Answers and your prompt

Answers stream in as the model writes them, inside a box that says who answered:

```text
╭──────────────────────────────────────────────────────────────╮
╞═ 🐧 TuxAide (Ollama · qwen2.5-coder:7b) ═╡
  To find files bigger than 100MB in the current folder, use find:

  ┄ sh ┄
  [1] find . -type f -size +100M
  ┄┄┄┄┄┄

╰──────────────────────────────────────────────────────────────╯

  1 put on prompt · c copy · Enter skip
```

The header shows the model and, when they apply, **Smart RAG** (answered from your man pages), **follow-up**, or **☁ remote · host** (the answer came from another computer — see [remote backends](/guide/remote-backends)).

## Put a command on your prompt

Commands in shell code blocks are numbered (up to 9). After the answer:

| Key | What happens |
| --- | --- |
| `1`–`9` | That command goes on your prompt. **zsh**: it's there, ready to edit. **bash**: press **↑** once (bash can't pre-fill the prompt from a hook). |
| `c` | Copies the command (`pbcopy`, `wl-copy`, `xclip`, `xsel`, or OSC 52 through SSH) |
| Enter, or wait 15 s | Nothing |

TuxAide **never runs the command**: you read it and press Enter yourself.

## Destructive commands

Commands that can destroy data — `rm -rf`, `dd`, `mkfs`, `shred`, `find … -delete`, `find … -exec rm`, `xargs rm`, `DROP TABLE`… — get a red warning above their code block, and choosing one asks **y/N** before it goes on your prompt.

## Turn the menu off

```bash
tuxaide config set action_menu false
```

## Cached answers

A question asked before (with the same model, mode and system) is answered from a local cache instantly. Cached answers expire after 30 days (`cache_ttl_days`); `tuxaide cache clear` empties the cache. Errors and partial answers are never cached.
