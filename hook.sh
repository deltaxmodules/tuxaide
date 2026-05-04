# ── TuxAide hook ── loaded by ~/.bashrc / ~/.zshrc ─────────────────
_LG="${HOME}/.local/bin/tuxaide"
_LG_ON=true

tuxaide() {
    [[ -z "${1:-}" ]] && {
        echo "🐧 TuxAide v2.1"
        echo "   tuxaide <question>            — ask a question"
        echo "   tuxaide on / off              — enable / disable hook"
        echo "   tuxaide status                — show status and mode"
        echo "   tuxaide mode [llm|smart|deep] — switch knowledge mode"
        echo "   tuxaide model <name>          — change Ollama model"
        echo "   tuxaide index <cmd>           — index a man page"
        echo "   tuxaide reindex               — re-index all man pages"
        echo "   tuxaide --timing              — show recent query performance"
        return
    }
    case "$1" in
        on)      _LG_ON=true;  echo "🐧 TuxAide ENABLED" ;;
        off)     _LG_ON=false; echo "🐧 TuxAide DISABLED" ;;
        status)
            local mode
            mode=$(python3 -c "import json,os; c=json.load(open(os.path.expanduser('~/.config/tuxaide/config.json'))); print(c.get('mode','llm').upper())" 2>/dev/null || echo "LLM")
            [[ "$_LG_ON" == "true" ]] && echo "🐧 Status: ACTIVE | Mode: $mode" || echo "🐧 Status: INACTIVE"
            ;;
        model|modelo)
            local m="${2:-}"
            [[ -z "$m" ]] && { echo "Usage: tuxaide model <name>"; return; }
            python3 -c "
import json,os
f=os.path.expanduser('~/.config/tuxaide/config.json')
with open(f) as fp: c=json.load(fp)
c['model']='$m'
with open(f,'w') as fp: json.dump(c,fp,indent=4)
print('🐧 Model changed to: $m')
"       ;;
        mode|index|reindex|--timing) "$_LG" "$@" ;;
        *) "$_LG" --ask "$*" ;;
    esac
}
alias tux='tuxaide'
alias lg='tuxaide'

# ── Automatic hook via command_not_found_handle ────────────────────
command_not_found_handle() {
    local cmd="$1"
    [[ "$_LG_ON" != "true" ]] && {
        echo "bash: $cmd: command not found" >&2
        return 127
    }
    local full_cmd
    full_cmd=$(HISTTIMEFORMAT="" history 1 2>/dev/null | sed 's/^ *[0-9]* *//')
    local question="${full_cmd:-$*}"
    if "$_LG" --check "$question" 2>/dev/null; then
        "$_LG" --ask "$question"
        return 0
    fi
    echo "bash: $cmd: command not found" >&2
    return 127
}

# ── Zsh hook ───────────────────────────────────────────────────────
# In zsh, preexec runs BEFORE execution but AFTER the command is accepted.
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _lg_preexec() {
        local cmd="$1"
        [[ "$_LG_ON" != "true" ]] && return
        "$_LG" --check "$cmd" 2>/dev/null && "$_LG" --ask "$cmd"
    }
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _lg_preexec 2>/dev/null

    command_not_found_handler() {
        local cmd="$1"
        case "$cmd" in
            how|why|what|where|when|which|who|como|porque|qual|onde|\
            comment|pourquoi|quel|cómo|qué|wie|warum|was)
                return 0 ;;
        esac
        echo "zsh: command not found: $cmd" >&2
        return 127
    }
fi

# ── Pre-warm Ollama model on session start ─────────────────────────
# Keeps the model loaded in RAM so first query is faster
(sleep 4 && curl -s -X POST http://localhost:11434/api/generate \
    -d "{\"model\":\"$(python3 -c "import json,os; c=json.load(open(os.path.expanduser('~/.config/tuxaide/config.json'))); print(c.get('model','qwen2.5-coder:7b'))" 2>/dev/null || echo 'qwen2.5-coder:7b')\",\"prompt\":\"ok\",\"stream\":false}" \
    >/dev/null 2>&1 &)
# ──────────────────────────────────────────────────────────────────
