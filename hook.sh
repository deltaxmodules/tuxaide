# ── TuxAide hook ── loaded by ~/.bashrc / ~/.zshrc ─────────────────
_LG="${HOME}/.local/bin/tuxaide"
_TUX_CFG="${HOME}/.config/tuxaide/config.json"
_TUX_SESSION_WRITER="${HOME}/.config/tuxaide/session_writer.py"
_TUX_SESSION_FILE="${HOME}/.config/tuxaide/session.json"
_TUX_PENDING_DIR="${HOME}/.config/tuxaide/pending"

# Lets TuxAide hand a chosen command back to *this* shell's prompt. The
# command-not-found handler runs in a subshell, so it can't edit the prompt
# itself: it writes the command to pending/<pid>, and the prompt hook below
# picks it up.
export TUXAIDE_SHELL_PID=$$
if [[ -n "${ZSH_VERSION:-}" ]]; then export TUXAIDE_SHELL=zsh; else export TUXAIDE_SHELL=bash; fi

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
      c.get("ollama_url", "http://localhost:11434"),
      "true" if c.get("failure_hint", True) else "false")
PYEOF
}
read -r _LG_ON _TUX_PREWARM _TUX_KEEP_ALIVE _TUX_MODEL _TUX_OLLAMA_URL _TUX_FAILURE_HINT <<CFGEOF
$(_tux_load_cfg || echo "true once 10m qwen2.5-coder:7b http://localhost:11434 true")
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

# `noglob` only exists in zsh. In bash, calling it from command_not_found_handle
# is itself "command not found", which re-enters the handler forever.
_tux_agent() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then noglob "$_LG" "$@"; else "$_LG" "$@"; fi
}

_tux_should_handle_question_line() {
    local line="$*"
    [[ -z "$line" ]] && return 1
    _tux_agent --check "$line" >/dev/null 2>&1
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
        echo "   ?  [question]                 — explain why the last command failed"
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
        why)
            shift
            _tux_agent --why "${_TUX_LAST_CMD:-}" "${_TUX_LAST_RC:-}" "$@"
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
# `?` explains the last command. An alias is expanded before globbing, so a
# one-character file in the current folder can't hijack it.
if [[ -n "${ZSH_VERSION:-}" ]]; then alias '?'='noglob tuxaide why'; else alias '?'='tuxaide why'; fi

# ── Put a command chosen in the answer menu on the prompt ──────────
# zsh: straight into the edit buffer. bash can't pre-fill the prompt from a
# hook, so the command goes into history: one ↑ brings it up, ready to edit.
_tux_take_pending() {
    local f="${_TUX_PENDING_DIR}/$$"
    [[ -f "$f" ]] || return 0
    local cmd
    cmd="$(<"$f")"
    rm -f "$f"
    [[ -n "$cmd" ]] || return 0
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        print -z -- "$cmd"
    else
        history -s -- "$cmd"
    fi
}

# ── Remember the last command, hint after a failure ────────────────
# Only the command line and its exit code are kept, in shell variables —
# never its output. `?` re-runs it (read-only commands, or after asking)
# when it needs to see the error.
_TUX_LAST_CMD=""
_TUX_LAST_RC=0
_tux_record() {
    local cmd="$1" rc="$2"
    # The not-found handler marks lines it answered as questions: those
    # aren't commands, so `?` keeps pointing at the real one before them.
    if [[ -f "${_TUX_PENDING_DIR}/$$.asked" ]]; then
        rm -f "${_TUX_PENDING_DIR}/$$.asked"
        return
    fi
    case "$cmd" in
        "?"|"? "*|"tuxaide why"*|"tux why"*) return ;;
    esac
    _TUX_LAST_CMD="$cmd"
    _TUX_LAST_RC="$rc"
    [[ "$_LG_ON" == "true" && "$_TUX_FAILURE_HINT" == "true" ]] || return
    case "$rc" in
        0|130|141|148) ;;   # success, Ctrl+C, broken pipe, Ctrl+Z
        *) printf '\033[2m💡 exit %s — type ? to ask TuxAide why\033[0m\n' "$rc" >&2 ;;
    esac
}

if [[ -n "${BASH_VERSION:-}" ]]; then
    _TUX_HISTCMD=""
    _tux_precmd() {
        local rc=$?
        # HISTCMD only moves when a new command ran (not on an empty Enter).
        if [[ -n "$_TUX_HISTCMD" && "$HISTCMD" != "$_TUX_HISTCMD" ]]; then
            # `history 1` ("  42  cmd"), not `fc -ln -1`: inside PROMPT_COMMAND
            # fc lags one entry behind after some lines (e.g. an alias).
            local last
            last="$(HISTTIMEFORMAT='' history 1 2>/dev/null)"
            last="${last#"${last%%[![:space:]]*}"}"   # leading spaces
            last="${last#"${last%%[![:digit:]]*}"}"   # history number
            last="${last#\*}"                         # "modified" marker
            last="${last#"${last%%[![:space:]]*}"}"
            _tux_record "$last" "$rc"
        fi
        _tux_take_pending
        _TUX_HISTCMD="$HISTCMD"
        return $rc
    }
    case "${PROMPT_COMMAND:-}" in
        *_tux_precmd*) ;;
        *) PROMPT_COMMAND="_tux_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
    esac
fi

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
        mkdir -p "$_TUX_PENDING_DIR" && : > "${_TUX_PENDING_DIR}/$$.asked"
        # This handler runs in a subshell, so exporting here doesn't leak.
        export TUXAIDE_LAST_CMD="$_TUX_LAST_CMD" TUXAIDE_LAST_RC="$_TUX_LAST_RC"
        _tux_agent --ask "$question"
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
    _TUX_RAN=""
    _tux_preexec() {
        _TUX_RAN="$1"
    }
    _tux_precmd() {
        local rc=$?
        if [[ -n "$_TUX_RAN" ]]; then
            _tux_record "$_TUX_RAN" "$rc"
            _TUX_RAN=""
        fi
        _tux_take_pending
        return $rc
    }
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _tux_preexec 2>/dev/null
    add-zsh-hook precmd _tux_precmd 2>/dev/null

    command_not_found_handler() {
        local cmd="$1"
        local line="$*"
        if _tux_should_handle_question_line "$line"; then
            mkdir -p "$_TUX_PENDING_DIR" && : > "${_TUX_PENDING_DIR}/$$.asked"
            # This handler runs in a subshell, so exporting here doesn't leak.
            export TUXAIDE_LAST_CMD="$_TUX_LAST_CMD" TUXAIDE_LAST_RC="$_TUX_LAST_RC"
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
