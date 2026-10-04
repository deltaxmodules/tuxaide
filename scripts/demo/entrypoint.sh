#!/bin/bash
# Prepares a clean demo machine inside the container, then runs VHS.
# /repo is the TuxAide repository; VHS runs there and writes into site/public.
set -euo pipefail

# The host's Ollama, reached as localhost: the demo shows a local setup, and
# it is the same machine.
socat TCP-LISTEN:11434,fork,reuseaddr "TCP:${OLLAMA_HOST_ADDR:-host.docker.internal}:11434" &
for _ in $(seq 50); do curl -fs http://localhost:11434/api/tags >/dev/null && break; sleep 0.2; done

# TuxAide, laid out as install.sh does it.
mkdir -p ~/.local/bin ~/.config/tuxaide
install -m 755 /repo/agent.py ~/.local/bin/tuxaide
install -m 755 /repo/indexer.py ~/.local/bin/tuxaide-index
install -m 755 /repo/uninstall.sh ~/.local/bin/tuxaide-uninstall
install -m 644 /repo/hook.sh /repo/session_writer.py ~/.config/tuxaide/
cat > ~/.config/tuxaide/config.json <<JSON
{"model": "${DEMO_MODEL:-qwen2.5-coder:7b}", "prewarm": "off", "keep_alive": "30m", "mode": "llm"}
JSON

# A tidy prompt and the caption shown at the start of each scene.
cat > ~/.zshrc <<'ZSH'
export PATH="$HOME/.local/bin:$PATH"
PROMPT='%F{39}~/demo%f %F{245}$%f '
setopt interactive_comments
scene() {
    clear
    print -P "%B%F{214}▌ $1%f%b"
    [[ -n "${2:-}" ]] && print -P "  %F{250}$2%f"
    [[ -n "${3:-}" ]] && print -P "  %F{250}$3%f"
    print
}
cd ~/demo
ZSH
~/.local/bin/tuxaide setup --yes --no-rag --shell zsh --no-doctor >/dev/null

# Something to look at: hidden files of different sizes, and a git repository.
mkdir -p ~/demo && cd ~/demo
truncate -s 150M ubuntu-24.04.iso      # sparse: takes no space
truncate -s 4M .cache.db
truncate -s 1200K .history.bak
truncate -s 96K .config.json
printf 'remember the milk\n' > .notes.txt
truncate -s 2M report.pdf
truncate -s 640K photo.jpg
git init -q . && git -c user.name=demo -c user.email=demo@example.com commit -q --allow-empty -m "first commit"
echo "draft" > ideas.md
tar -cf backup.tar ideas.md .notes.txt          # a plain tar: `tar -xzf` on it fails

# Load the model now, so the first answer isn't slower than the others.
curl -fs http://localhost:11434/api/generate \
    -d "{\"model\": \"${DEMO_MODEL:-qwen2.5-coder:7b}\", \"keep_alive\": \"30m\"}" >/dev/null || true

cd /repo
exec vhs "$@"
