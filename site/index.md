---
layout: home

hero:
  name: TuxAide
  text: Ask your terminal in plain English.
  tagline: Type a Linux question as if it were a command. A model on your own computer answers right there — and it never runs anything on its own.
  image:
    src: /logo.svg
    alt: TuxAide
  actions:
    - theme: brand
      text: Install and first question
      link: /guide/get-started
    - theme: alt
      text: How does it know it's a question?
      link: /guide/how-it-knows
    - theme: alt
      text: GitHub
      link: https://github.com/deltaxmodules/tuxaide

features:
  - title: No trigger word
    details: Type the question itself. Real commands, aliases and functions run exactly as before.
    link: /guide/how-it-knows
  - title: The command, on your prompt
    details: Commands in an answer are numbered. Press 1 and it's on your prompt, ready to edit — you press Enter. Destructive ones are flagged first.
    link: /guide/answers-and-the-prompt
  - title: "? explains the last error"
    details: A command failed? Type ? and TuxAide reads the error (asking before re-running anything that isn't read-only) and tells you the fix.
    link: /guide/when-a-command-fails
  - title: Typos fixed instantly
    details: gti status → git status, cd.. → cd .., without asking the model. Your distro's own "install it with apt" hint still works.
    link: /guide/when-a-command-fails#typos
  - title: Answers from your man pages
    details: With Smart RAG, questions about a command are answered from the man pages installed on your system, with the source cited.
    link: /guide/smart-rag
  - title: Local by default
    details: A model on your machine through Ollama. No account, no API key, no telemetry. A remote backend is optional — and marked ☁ on every answer.
    link: /guide/privacy
---

## See it in 90 seconds

<video controls muted playsinline preload="none" poster="/video/tuxaide-demo.jpg" src="/video/tuxaide-demo.mp4" style="width:100%;border-radius:8px" aria-label="TuxAide in a terminal: a question and its command put on the prompt, a follow-up with a destructive-command warning, a question in Portuguese, ? explaining a failed tar command, a typo fixed, and tuxaide doctor"></video>

A real terminal and a real model (`qwen2.5-coder:7b` on Ollama): a question and its command put on the prompt, a follow-up with a warning before deleting, a question in Portuguese, `?` explaining a failed command, a typo fixed, and `tuxaide doctor`. No sound; a caption opens each scene. [How the video is made](https://github.com/deltaxmodules/tuxaide/blob/main/docs/video/PLANO.md).

## Who is it for?

People learning Linux, and anyone who doesn't remember every flag. Instead of leaving the terminal to search, you ask where you already are:

```bash
$ how do I find files bigger than 100MB in this folder
$ and how do I delete them?
$ como vejo o espaço livre no disco
$ ?            # after a command that failed
```

It answers in the language you wrote in, with commands for *your* system (`dnf` on Fedora, `brew` on macOS).

## Install in one command

```bash
curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
```

Or `brew install deltaxmodules/tap/tuxaide`, `yay -S tuxaide`, `pipx install tuxaide` — then `tuxaide setup`. [Details](/guide/get-started).
