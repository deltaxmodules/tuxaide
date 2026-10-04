# ── TuxAide hook ── loaded by ~/.bashrc / ~/.zshrc ─────────────────
# shellcheck shell=bash
_LG="${HOME}/.local/bin/tuxaide"
_TUX_CFG="${HOME}/.config/tuxaide/config.json"
_TUX_SESSION_WRITER="${HOME}/.config/tuxaide/session_writer.py"
_TUX_PENDING_DIR="${HOME}/.config/tuxaide/pending"
_TUX_HOOK="${HOME}/.config/tuxaide/hook.sh"

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
      "true" if c.get("failure_hint", True) else "false",
      c.get("backend", "ollama"))
PYEOF
}
# Also run after `tuxaide config` / `model`, so a change applies in this shell too.
_tux_reload_cfg() {
    read -r _LG_ON _TUX_PREWARM _TUX_KEEP_ALIVE _TUX_MODEL _TUX_OLLAMA_URL _TUX_FAILURE_HINT _TUX_BACKEND <<CFGEOF
$(_tux_load_cfg || echo "true once 10m qwen2.5-coder:7b http://localhost:11434 true ollama")
CFGEOF
}
_tux_reload_cfg

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
    [[ -z "${1:-}" ]] && { "$_LG" help; return; }
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
        run)
            shift
            _tux_run "$@"
            ;;
        why)
            shift
            _tux_agent --why "${_TUX_LAST_CMD:-}" "${_TUX_LAST_RC:-}" "$@"
            ;;
        model|modelo|config)
            "$_LG" "$@"
            local rc=$?
            _tux_reload_cfg
            return "$rc"
            ;;
        doctor)
            TUXAIDE_HANDLER="$(_tux_handler_state)" "$_LG" "$@"
            ;;
        update)
            # A new hook.sh is loaded into this shell straight away.
            local before rc
            before="$(cksum < "$_TUX_HOOK" 2>/dev/null)"
            "$_LG" "$@"
            rc=$?
            if [[ $rc -eq 0 && "$(cksum < "$_TUX_HOOK" 2>/dev/null)" != "$before" ]]; then
                # shellcheck disable=SC1090
                source "$_TUX_HOOK" && echo "🐧 New hook loaded in this terminal."
            fi
            return "$rc"
            ;;
        status|mode|index|reindex|--timing|new|history|system|cache|help|--help|-h|version|--version|-V) "$_LG" "$@" ;;
        *) "$_LG" --ask "$*" ;;
    esac
}
# For `tuxaide doctor`: is the command-not-found handler in this shell ours?
_tux_handler_state() {
    local body
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        body="$(typeset -f command_not_found_handler 2>/dev/null)" || { echo none; return; }
    else
        (( BASH_VERSINFO[0] >= 4 )) || { echo old-bash; return; }
        body="$(declare -f command_not_found_handle 2>/dev/null)" || { echo none; return; }
    fi
    [[ "$body" == *--not-found* ]] && echo ours || echo other
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
    # A typo that already got a "Did you mean" suggestion needs no 💡 hint too.
    if [[ -f "${_TUX_PENDING_DIR}/$$.suggested" ]]; then
        rm -f "${_TUX_PENDING_DIR}/$$.suggested"
        return
    fi
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
    # One agent call: answers a question, or suggests a fix for a typo
    # ("gti status" → "git status"), or exits 1 for a plain "not found".
    # This handler runs in a subshell, so exporting here doesn't leak.
    export TUXAIDE_LAST_CMD="$_TUX_LAST_CMD" TUXAIDE_LAST_RC="$_TUX_LAST_RC"
    local names
    names="$({ compgen -a; compgen -A function; compgen -b; } 2>/dev/null)"
    export TUXAIDE_NAMES="$names"
    _tux_agent --not-found "$question"
    case $? in
        0) return 0 ;;     # answered as a question
        3) return 127 ;;   # typo: suggestion already printed
    esac
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
        if [[ "$_LG_ON" != "true" ]]; then
            echo "zsh: command not found: $cmd" >&2
            return 127
        fi
        # Same single agent call as in bash (see command_not_found_handle).
        export TUXAIDE_LAST_CMD="$_TUX_LAST_CMD" TUXAIDE_LAST_RC="$_TUX_LAST_RC"
        # shellcheck disable=SC2296  # zsh-only expansion flags
        export TUXAIDE_NAMES="${(F)${(k)aliases}} ${(F)${(k)functions}} ${(F)${(k)builtins}}"
        noglob "$_LG" --not-found "$line"
        case $? in
            0) return 0 ;;
            3) return 127 ;;
        esac
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
    [[ "$_LG_ON" == "true" && "$_TUX_BACKEND" == "ollama" ]] || return 0
    # Only a local Ollama: nothing leaves the machine without the ☁ indicator.
    case "$_TUX_OLLAMA_URL" in
        http://localhost[:/]*|http://localhost|http://127.*|http://\[::1\]*) ;;
        *) return 0 ;;
    esac
    case "$_TUX_PREWARM" in
        off) return 0 ;;
        always) ;;
        *)
            local marker
            marker="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tuxaide-prewarm-$(id -u)"
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
