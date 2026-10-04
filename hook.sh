# ── TuxAide hook ── loaded by ~/.bashrc / ~/.zshrc ─────────────────
_LG="${HOME}/.local/bin/tuxaide"
_TUX_CFG="${HOME}/.config/tuxaide/config.json"
_TUX_SESSION_WRITER="${HOME}/.config/tuxaide/session_writer.py"
_TUX_SESSION_FILE="${HOME}/.config/tuxaide/session.json"

# Read the settings the hook needs at load time in a single python3 call.
_tux_load_cfg() {
    python3 - "$_TUX_CFG" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f: c = json.load(f)
except Exception:
    c = {}
print("true" if c.get("enabled", True) else "false",
      c.get("prewarm", "once"),
      c.get("keep_alive", "10m"),
      c.get("model", "qwen2.5-coder:7b"),
      c.get("ollama_url", "http://localhost:11434"))
PYEOF
}
read -r _LG_ON _TUX_PREWARM _TUX_KEEP_ALIVE _TUX_MODEL _TUX_OLLAMA_URL <<CFGEOF
$(_tux_load_cfg || echo "true once 10m qwen2.5-coder:7b http://localhost:11434")
CFGEOF

_tux_session_capture_enabled() {
    python3 -c "import json,os; c=json.load(open(os.path.expanduser('${_TUX_CFG}'))); print(str(bool(c.get('session_capture', False))).lower())" 2>/dev/null
}

_tux_is_interactive_cmd() {
    case "$1" in
        vim|vi|nano|top|htop|less|more|man|screen|tmux) return 0 ;;
        *) return 1 ;;
    esac
}

_tux_should_handle_question_line() {
    local line="$*"
    [[ -z "$line" ]] && return 1
    noglob "$_LG" --check "$line" >/dev/null 2>&1
}

_tux_run() {
    local cmd="$*"
    [[ -z "$cmd" ]] && { echo "Usage: tuxaide run <command>"; return 1; }

    local capture_enabled
    capture_enabled=$(_tux_session_capture_enabled)

    local stdout_file stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    bash -lc "$cmd" >"$stdout_file" 2>"$stderr_file"
    local rc=$?

    [[ -s "$stdout_file" ]] && cat "$stdout_file"
    [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2

    if [[ "$capture_enabled" == "true" && -x "$_TUX_SESSION_WRITER" ]]; then
        local first_word capturable shell_name
        first_word="${cmd%% *}"
        capturable="true"
        _tux_is_interactive_cmd "$first_word" && capturable="false"
        shell_name="${SHELL##*/}"
        if command -v flock >/dev/null 2>&1; then
            (
                flock -x 9
                python3 "$_TUX_SESSION_WRITER" "$cmd" "$stdout_file" "$stderr_file" "$rc" "$capturable" "$shell_name" >/dev/null 2>&1
            ) 9>"${HOME}/.config/tuxaide/session.lock"
        else
            local lock_dir="${HOME}/.config/tuxaide/session.lock.d"
            local tries=0
            local max_tries=3
            while (( tries < max_tries )); do
                if mkdir "$lock_dir" 2>/dev/null; then
                    python3 "$_TUX_SESSION_WRITER" "$cmd" "$stdout_file" "$stderr_file" "$rc" "$capturable" "$shell_name" >/dev/null 2>&1
                    rmdir "$lock_dir" 2>/dev/null
                    break
                fi
                tries=$((tries + 1))
                sleep 0.05
            done
            if (( tries >= max_tries )); then
                python3 "$_TUX_SESSION_WRITER" "$cmd" "$stdout_file" "$stderr_file" "$rc" "$capturable" "$shell_name" >/dev/null 2>&1
            fi
        fi
    fi

    rm -f "$stdout_file" "$stderr_file"
    return "$rc"
}

tuxaide() {
    [[ -z "${1:-}" ]] && {
        echo "🐧 TuxAide v2.1"
        echo "   tuxaide <question>            — ask a question"
        echo "   tuxaide on / off              — enable / disable hook"
        echo "   tuxaide status                — show status and mode"
        echo "   tuxaide mode [llm|smart|deep] — switch knowledge mode"
        echo "   tuxaide run <cmd>             — run and capture shell context"
        echo "   tuxaide model <name>          — change Ollama model"
        echo "   tuxaide index <cmd>           — index a man page"
        echo "   tuxaide reindex               — re-index all man pages"
        echo "   tuxaide --timing              — show recent query performance"
        return
    }
    case "$1" in
        on)
            _LG_ON=true
            "$_LG" --set enabled true
            echo "🐧 TuxAide ENABLED"
            ;;
        off)
            _LG_ON=false
            "$_LG" --set enabled false
            echo "🐧 TuxAide DISABLED (also in new terminals — 'tuxaide on' to re-enable)"
            ;;
        status)
            local mode capture
            mode=$(python3 -c "import json,os; c=json.load(open(os.path.expanduser('~/.config/tuxaide/config.json'))); print(c.get('mode','llm').upper())" 2>/dev/null || echo "LLM")
            capture=$(_tux_session_capture_enabled)
            [[ "$_LG_ON" == "true" ]] && echo "🐧 Status: ACTIVE | Mode: $mode | Session capture: ${capture:-false} | Session file: ${_TUX_SESSION_FILE}" || echo "🐧 Status: INACTIVE"
            ;;
        run)
            shift
            _tux_run "$@"
            ;;
        model|modelo)
            local m="${2:-}"
            [[ -z "$m" ]] && { echo "Usage: tuxaide model <name>"; return; }
            "$_LG" --set model "$m" && echo "🐧 Model changed to: $m"
            ;;
        mode|index|reindex|--timing) "$_LG" "$@" ;;
        *) "$_LG" --ask "$*" ;;
    esac
}
# Short alias, only if 'tux' isn't already taken by something else.
type tux >/dev/null 2>&1 || alias tux='tuxaide'

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
    if _tux_should_handle_question_line "$question"; then
        noglob "$_LG" --ask "$question"
        return 0
    fi
    echo "bash: $cmd: command not found" >&2
    return 127
}

# ── Zsh hook ───────────────────────────────────────────────────────
# In zsh, preexec runs BEFORE execution but AFTER the command is accepted.
if [[ -n "${ZSH_VERSION:-}" ]]; then
    # Allow natural-language questions ending with '?' without glob errors.
    setopt NO_NOMATCH 2>/dev/null
    _lg_preexec() {
        return
    }
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _lg_preexec 2>/dev/null

    command_not_found_handler() {
        local cmd="$1"
        local line="$*"
        if _tux_should_handle_question_line "$line"; then
            noglob "$_LG" --ask "$line"
            return 0
        fi
        echo "zsh: command not found: $cmd" >&2
        return 127
    }
fi

# ── Pre-warm Ollama model on session start ─────────────────────────
# Loads the model into RAM so the first question is faster.
#   prewarm=off     never
#   prewarm=once    at most once per 10 minutes, however many terminals open
#   prewarm=always  every new shell
# An empty prompt only loads the model; keep_alive sets how long it stays loaded.
_tux_prewarm() {
    [[ "$_LG_ON" == "true" ]] || return 0
    case "$_TUX_PREWARM" in
        off) return 0 ;;
        always) ;;
        *)
            local marker="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tuxaide-prewarm-$(id -u)"
            [[ -n "$(find "$marker" -mmin -10 2>/dev/null)" ]] && return 0
            touch "$marker" 2>/dev/null
            ;;
    esac
    (sleep 2 && curl -s -m 120 -X POST "${_TUX_OLLAMA_URL}/api/generate" \
        -d "{\"model\":\"${_TUX_MODEL}\",\"keep_alive\":\"${_TUX_KEEP_ALIVE}\"}" \
        >/dev/null 2>&1 &)
}
_tux_prewarm
# ──────────────────────────────────────────────────────────────────
