# Follow-ups and your system

## Follow-up questions

TuxAide remembers the conversation for 10 minutes, so you can keep going:

```bash
$ como listar ficheiros ocultos
$ e por tamanho?
$ e ao contrário?
```

A follow-up is recognised by how it starts (“and…”, “what about…”, “e…”, “y…”, “et…”, “und…”) or by short phrases pointing back (“does that work on mac?”). It's sent with the last 3 exchanges and marked **follow-up** in the answer header. A brand-new question is sent on its own, so unrelated answers don't mix.

| Command | What it does |
| --- | --- |
| `tuxaide new` | Start over (forget the conversation) |
| `tuxaide history` | Your recent questions |

Settings: `followup_window` (seconds a conversation stays open; `0` turns follow-ups off) and `followup_turns` (exchanges sent with a follow-up).

## Answers for your system

TuxAide tells the model which system it's answering for, so you get `dnf` on Fedora, `pacman` on Arch and `brew` on macOS instead of “it depends on your distro”. See exactly what is sent:

```bash
$ tuxaide system
🐧 Sent with each question: Ubuntu 24.04 LTS, package manager apt, shell bash, init systemd, x86_64
```

Only generic facts are sent — never user names, host names or paths. Turn it off with `tuxaide config set system_context false`.

## Any language

TuxAide replies in the language of your question:

```bash
how do I check open ports
como listar ficheiros ocultos
comment lister les fichiers cachés
cómo ver el espacio en disco
wie zeige ich offene Ports
```
