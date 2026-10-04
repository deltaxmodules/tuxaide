# When a command fails

## `?` explains the last command

After a command fails, TuxAide shows a one-line hint. Type `?`:

```text
~/demo $ tar -xzf backup.tar
gzip: stdin: not in gzip format
tar: Child returned status 1
💡 exit 2 — type ? to ask TuxAide why
~/demo $ ?
  Re-run tar -xzf backup.tar to read its error? [y/N] y
  re-running: tar -xzf backup.tar

╞═ 🐧 TuxAide (Ollama · qwen2.5-coder:7b) ═╡
  The command failed because backup.tar is not in gzip format. Use tar
  without the -z option:

  [1] tar -xf backup.tar
```

- `? <question>` asks something specific about the last command: `? how do I fix permissions`.
- Asking in words works too, right after the failure: “why did this fail?”, “porque deu este erro?”.
- TuxAide keeps **only the last command line and its exit code**, in your shell's memory — never its output.
- To read the error it **runs the command again**: read-only commands (`ls`, `cat`, `grep`, `git status`, `systemctl status`…) straight away; anything else only after you answer **y**. Interactive programs (`vim`, `top`, …) are never re-run.
- Turn the hint off with `tuxaide config set failure_hint false`; `?` keeps working.

To give TuxAide the full output of a command up front, run it through TuxAide: `tuxaide run "make test"`, then ask.

## Typos

```text
~/demo $ gti status
zsh: command not found: gti
🐧 Did you mean: git status  [Enter/y] put on prompt · other key skips
```

Instant, without the model. TuxAide knows the commands on your `PATH`, your aliases and functions, and fixes a missing space too: `cd..` → `cd ..`, `ls-la` → `ls -la`, `git-log` → `git log`. A destructive fix is only shown, never put on the prompt.

On Debian and Ubuntu, a command that isn't installed shows which package provides it. Any command-not-found handler your system had before TuxAide (Ubuntu's, Fedora's PackageKit, oh-my-zsh's plugin) is **kept**, and still answers for commands TuxAide has nothing to say about.

Turn typo suggestions off with `tuxaide config set typo_suggest false`.
