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
| `pyproject.toml`, `packaging/` | pipx/PyPI package, Homebrew formula and AUR PKGBUILD templates |
| `site/` | The manual (VitePress), with the demo video and GIF in `site/public/` |
| `scripts/demo/`, `scripts/demo-video.sh` | How the demo video is recorded |
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
shellcheck -S warning hook.sh install.sh setup.sh uninstall.sh scripts/render-packaging.sh scripts/demo-video.sh scripts/demo/entrypoint.sh
python3 -m pip install ruff && ruff check .
```

CI runs both, plus the tests on Linux (Python 3.9, 3.12, 3.13) and macOS.

## The manual and the demo video

- **Manual** (`site/`, VitePress): `cd site && npm install --no-save vitepress@1.6.4 && npx vitepress dev .`
  — published to GitHub Pages with each release (`.github/workflows/pages.yml`); CI builds it on every PR.
- **Demo video and README GIF**: `scripts/demo-video.sh` (needs Docker and Ollama with
  `qwen2.5-coder:7b`). It records a real terminal with [VHS](https://github.com/charmbracelet/vhs)
  from `scripts/demo/*.tape`; the plan and the reasons behind it are in `docs/video/PLANO.md`.
  Answers come from the real model, so watch the result before committing it.

## Releasing

The version lives in `__version__` in `agent.py`.

1. Bump `__version__`, `TUXAIDE_VERSION` in `install.sh` and the version badge in
   `README.md` (`tests/test_version.py` fails if they differ). Merge to `main`.
2. Push the tag: `git tag v2.3.0 && git push origin v2.3.0`. The **Release** workflow
   checks the tag matches `__version__` and publishes the GitHub release with
   `install.sh`, `setup.sh`, `SHA256SUMS`, the wheel/sdist, and a filled-in
   `tuxaide.rb` and `PKGBUILD`.
3. Homebrew: copy `tuxaide.rb` from the release to `Formula/tuxaide.rb` in
   [deltaxmodules/homebrew-tap](https://github.com/deltaxmodules/homebrew-tap) and push.
   The manual is published to GitHub Pages by the same workflow.
4. AUR: copy `PKGBUILD` and `tuxaide.install` to the `aur.archlinux.org/tuxaide.git`
   clone, run `makepkg --printsrcinfo > .SRCINFO`, commit and push.
5. PyPI: `twine upload` the wheel and sdist from the release.

The curl installer and `tuxaide update` download the files of the release's tag and
check them against its `SHA256SUMS`; until a release exists, the installer falls back
to `main`. Templates: `packaging/homebrew/tuxaide.rb.in`, `packaging/aur/PKGBUILD.in`;
`scripts/render-packaging.sh <version>` fills them in by hand.

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
