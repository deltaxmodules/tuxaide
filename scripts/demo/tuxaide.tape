# The demo video of the manual — see docs/video/PLANO.md. Run: scripts/demo-video.sh
Output site/public/video/tuxaide-demo.mp4

Set Shell zsh
Set Width 1280
Set Height 800
Set FontSize 22
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set WaitTimeout 120s
Set WaitPattern /demo \$$/

# VHS starts zsh without reading rc files: load the demo's .zshrc (prompt, TuxAide's hook).
Hide
Type "source ~/.zshrc && clear" Enter
Sleep 1s
Type "scene 'TuxAide — ask your terminal in plain English' 'A local model answers right in your shell. It never runs anything on its own.'" Enter
Show
Sleep 4s

# 1. Ask; press 1; the command is on the prompt
Hide
Type "scene '1. Type a question, as if it were a command' 'Press 1: the command lands on your prompt, ready to edit. You press Enter.'" Enter
Show
Sleep 1.5s
Type "how do I find files bigger than 100MB in this folder" Sleep 500ms Enter
Wait+Screen /put on prompt/
Sleep 3s
Type "1"
Sleep 2.5s
Enter
Wait
Sleep 3s

# 2. Follow-ups, the destructive warning, any language
Hide
Type "scene '2. Follow-ups, in any language' 'Destructive commands come with a warning.'" Enter
Show
Sleep 1.5s
Type "and how do I delete them?" Sleep 500ms Enter
Wait+Screen /put on prompt|╰─/
Sleep 3.5s
Enter
Wait
Sleep 1s
Type "como vejo o espaço livre no disco" Sleep 500ms Enter
Wait+Screen /put on prompt|╰─/
Sleep 3s
Enter
Wait
Sleep 1s

# 3. A command fails: ?
Hide
Type "scene '3. A command failed? Type ?' 'To read the error it runs the command again — and asks first unless it only reads.'" Enter
Show
Sleep 1.5s
Type "tar -xzf backup.tar" Sleep 500ms Enter
Wait
Sleep 2s
Type "?" Sleep 500ms Enter
Wait+Screen /to read its error\? \[y\/N\]/
Sleep 2s
Type "y"
Wait+Screen /put on prompt|╰─/
Sleep 4s
Enter
Wait
Sleep 1s

# 4. Typos
Hide
Type "scene '4. Typos are fixed instantly, without the model'" Enter
Show
Sleep 1.5s
Type "gti status" Sleep 500ms Enter
Wait+Screen /Did you mean/
Sleep 2s
Enter
Sleep 1.5s
Enter
Wait
Sleep 2.5s

# 5. doctor
Hide
Type "scene '5. Something off? tuxaide doctor checks everything'" Enter
Show
Sleep 1.5s
Type "tuxaide doctor" Sleep 500ms Enter
Wait
Sleep 4s

Hide
Type "scene 'Local · free · open source' 'Install it in one command — manual: https://deltaxmodules.github.io/tuxaide' 'Source: https://github.com/deltaxmodules/tuxaide'" Enter
Show
Sleep 5s
