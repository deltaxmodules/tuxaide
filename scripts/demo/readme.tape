# The README's GIF — see docs/video/PLANO.md. Run: scripts/demo-video.sh
Output site/public/img/tuxaide-demo.gif

Set Shell zsh
Set Width 1000
Set Height 600
Set FontSize 16
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 35ms
Set WaitTimeout 120s
Set WaitPattern /demo \$$/
Set Framerate 20

# VHS starts zsh without reading rc files: load the demo's .zshrc (prompt, TuxAide's hook).
Hide
Type "source ~/.zshrc && clear" Enter
Sleep 1s
Show
Type "how do I find files bigger than 100MB in this folder" Sleep 300ms Enter
Wait+Screen /put on prompt/
Sleep 1.5s
Type "1"
Sleep 1.2s
Enter
Wait
Sleep 1.5s
Hide
Type "clear" Enter
Show
Type "ls /var/log/nginx" Sleep 300ms Enter
Wait
Sleep 1s
Type "?" Sleep 300ms Enter
Wait+Screen /put on prompt|╰─/
Sleep 3s
