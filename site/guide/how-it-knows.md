# How does it know it's a question?

There's no trigger word. The rule is short:

1. TuxAide only looks at a line when **the shell can't find its first word** as a command. `ls -la`, `git commit -m "how"`, your aliases and functions are never touched — the shell runs them as always.
2. Such a line is a **question** if it contains a question word — *how, what, why, which, where, can I…* in English, *como, porquê, qual, onde…* in Portuguese, and the same in Spanish, French and German — or ends with `?`.
3. Right after a question, a short **follow-up** counts too: “and by size”, “e ao contrário”, “what about mac?”.

Anything else is a typo or a real “command not found”: TuxAide suggests a fix if it sees one ([typos](/guide/when-a-command-fails#typos)), and otherwise your shell (or your distro's handler) says what it always said.

## Force a question

A question that starts with a real command is run as that command: `find big files?` runs `find`. Ask through `tuxaide` instead:

```bash
tuxaide find big files
```

## Stop it

```bash
tuxaide off     # remembered in new terminals
tuxaide on
```

With TuxAide off, unknown commands get the shell's normal message and nothing is sent to the model.

## Characters the shell treats specially

zsh would normally stop a line with an unmatched `?` or `*` (`no matches found`) before TuxAide sees it. The hook turns zsh's `NOMATCH` option off in interactive shells, so `what is this?` works (an unmatched pattern is then passed on as typed, as in bash). In bash, avoid starting a question with `!` (history expansion) — or ask through `tuxaide "…"`.
