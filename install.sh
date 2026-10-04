#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
#  TuxAide — Complete Installer with Smart RAG
#  https://github.com/deltaxmodules/tuxaide
#
#  One-liner install:
#    curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
#    … | bash -s -- --yes            no questions
#
#  What it does:
#    1.  Detects the system and picks the model that fits its RAM
#    2.  Asks its questions (Smart RAG, a remote backend on small machines)
#    3.  Shows everything it will do and asks once
#    4.  Installs Ollama and TuxAide's files (from the tagged release,
#        checked against SHA256SUMS)
#    5.  Runs `tuxaide setup`: settings, model, Smart RAG (man pages are
#        indexed in the background), the lines in your shell rc, doctor
#
#  To uninstall:     tuxaide uninstall
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# Must match __version__ in agent.py (tests/test_version.py checks).
TUXAIDE_VERSION="2.3.0"

usage() {
    cat <<'EOF'
Usage: install.sh [--yes] [--no-rag] [--model <name>]
  -y, --yes        don't ask anything: take the recommended answers
  --no-rag         skip Smart RAG (the man-page knowledge base)
  --model <name>   use this Ollama model instead of the one picked for your RAM
EOF
}

ASSUME_YES=false
FORCE_NO_RAG=false
MODEL_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)  ASSUME_YES=true ;;
        --no-rag)  FORCE_NO_RAG=true ;;
        --model)   MODEL_OVERRIDE="${2:-}"; shift || true ;;
        --model=*) MODEL_OVERRIDE="${1#--model=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
if [[ -n "$MODEL_OVERRIDE" && ! "$MODEL_OVERRIDE" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    echo "Not a valid model name: $MODEL_OVERRIDE" >&2
    exit 2
fi

# ── Colours ───────────────────────────────────────────────────────────
R="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
CY="\033[36m"; GR="\033[32m"; YL="\033[33m"; RD="\033[31m"; MG="\033[35m"

# ── Helpers ───────────────────────────────────────────────────────────
banner() {
    [[ "$ASSUME_YES" == "true" ]] || clear 2>/dev/null || true
    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🐧  TuxAide ${TUXAIDE_VERSION} — Complete Installer            ║${R}"
    echo -e "${CY}${BOLD}║   Local AI assistant with Smart RAG                 ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
}
# One status row of the diagnosis box (53 columns inside): colour, mark, label, status.
box_status() {
    printf "  ${CY}│${R}  ${1}%s${R} %-24s ${1}%-24s${R}${CY}│${R}\n" "$2" "$3" "$4"
}
step()  { echo -e "\n${CY}${BOLD}[$((++STEP))/$TOTAL_STEPS] $*${R}"; }
ok()    { echo -e "  ${GR}✓${R}  $*"; }
warn()  { echo -e "  ${YL}⚠${R}  $*"; }
info()  { echo -e "  ${DIM}→  $*${R}"; }
err()   { echo -e "\n${RD}${BOLD}  ✗  ERROR: $*${R}\n"; exit 1; }
ask()   { echo -e "  ${MG}?${R}  $*"; }

# answer VAR DEFAULT — read the reply to the question just asked. With --yes
# (or with no terminal) the default is taken and shown.
answer() {
    # (a local named like the caller's variable would hide it from printf -v)
    local __tux_reply=""
    if [[ "$ASSUME_YES" == "true" ]] || ! { true </dev/tty; } 2>/dev/null; then
        __tux_reply="$2"
        echo -e "     ${DIM}${__tux_reply:-(default)}${R}"
    else
        read -r __tux_reply </dev/tty || __tux_reply=""
        __tux_reply="${__tux_reply:-$2}"
    fi
    printf -v "$1" '%s' "$__tux_reply"
}

STEP=0
TOTAL_STEPS=7
INSTALL_RAG=false
# Where answers come from: "local" (Ollama here), "ollama-remote" (Ollama on
# another computer) or "openai" (an OpenAI-compatible API). Remote is only
# ever used when the user picks it.
BACKEND="local"
OLLAMA_URL="http://localhost:11434"
API_BASE=""
API_KEY_ENV="OPENAI_API_KEY"
VENV="${HOME}/.local/share/tuxaide/venv"

# ═══════════════════════════════════════════════════════════════════════
# STEP 1 — System diagnosis
# ═══════════════════════════════════════════════════════════════════════
diagnose_system() {
    step "System diagnosis"

    # OS
    OS="linux"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS="macos"
        DISTRO="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
        ok "OS: $DISTRO"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        ok "Distro: ${PRETTY_NAME:-$DISTRO}"
    else
        DISTRO="unknown"
        warn "Could not detect distro — continuing anyway"
    fi

    # Architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)        ARCH_LABEL="amd64" ;;
        aarch64|arm64) ARCH_LABEL="arm64" ;;
        armv7l)        ARCH_LABEL="arm"   ;;
        *) err "Unsupported architecture: $ARCH" ;;
    esac
    ok "Architecture: $ARCH"

    # RAM
    if [[ "$OS" == "macos" ]]; then
        RAM_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 ))
    else
        RAM_MB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
        # In a container or a VM slice, the cgroup limit is what we really get.
        local limit
        limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
        if [[ "$limit" =~ ^[0-9]+$ ]] && (( limit / 1024 / 1024 < RAM_MB )); then
            RAM_MB=$(( limit / 1024 / 1024 ))
        fi
    fi
    RAM_GB=$(( (RAM_MB + 512) / 1024 ))
    ok "Available RAM: ${RAM_GB} GB"

    # Disk space
    DISK_FREE_KB=$(df -k "${HOME}" | awk 'NR==2{print $4}')
    DISK_FREE_GB=$((DISK_FREE_KB / 1024 / 1024))
    ok "Free disk space: ${DISK_FREE_GB} GB"

    # GPU
    HAS_GPU=false
    GPU_INFO="None detected"
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
        HAS_GPU=true
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        ok "GPU: $GPU_INFO (NVIDIA)"
    elif lspci 2>/dev/null | grep -qi "amd\|radeon"; then
        HAS_GPU=true
        GPU_INFO="AMD GPU detected"
        ok "GPU: $GPU_INFO"
    else
        ok "GPU: None — CPU-only mode"
    fi

    # Shell
    CURRENT_SHELL=$(basename "${SHELL:-bash}")
    ok "Shell: $CURRENT_SHELL"

    # systemd
    HAS_SYSTEMD=false
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null 2>&1 && \
       systemctl list-units &>/dev/null 2>&1; then
        HAS_SYSTEMD=true
        ok "systemd: available"
    elif [[ "$OS" == "macos" ]]; then
        ok "macOS: will use launchd"
    else
        warn "systemd not detected — Ollama will not start on boot automatically"
    fi

    # Man pages available
    MAN_COUNT=0
    if [[ -d /usr/share/man/man1 ]]; then
        MAN_COUNT=$(ls /usr/share/man/man1/ 2>/dev/null | wc -l)
    fi
    ok "Man pages available: ~${MAN_COUNT} in man1"

    # ── Model selection ───────────────────────────────────────────────
    # Thresholds sit a little under 8/5/3 GB: the kernel reserves some of
    # the RAM, so an "8 GB" machine reports about 7.6 GB.
    # Download sizes from registry.ollama.ai (checked 2026-10).
    LOW_RAM=false
    if [[ $RAM_MB -ge 7000 ]]; then
        MODEL="qwen2.5-coder:7b"; MODEL_SIZE="4.7 GB"; DISK_NEED_GB=6; RAG_CAPABLE=true
    elif [[ $RAM_MB -ge 4500 ]]; then
        MODEL="qwen2.5:3b";       MODEL_SIZE="1.9 GB"; DISK_NEED_GB=3; RAG_CAPABLE=true
    elif [[ $RAM_MB -ge 2800 ]]; then
        MODEL="qwen2.5:1.5b";     MODEL_SIZE="986 MB"; DISK_NEED_GB=2; RAG_CAPABLE=false
    else
        # Too little for a useful local model: offer a remote backend below.
        MODEL="qwen2.5:0.5b";     MODEL_SIZE="398 MB"; DISK_NEED_GB=1; RAG_CAPABLE=false
        LOW_RAM=true
    fi
    # A model chosen before (re-install) or on the command line wins.
    local current
    current=$(python3 -c 'import json,os,sys; print(json.load(open(os.path.expanduser("~/.config/tuxaide/config.json"))).get("model",""))' 2>/dev/null || true)
    if [[ -n "$MODEL_OVERRIDE" || -n "$current" ]]; then
        MODEL="${MODEL_OVERRIDE:-$current}"
        case "$MODEL" in
            qwen2.5-coder:7b) MODEL_SIZE="4.7 GB" ;;
            qwen2.5:3b)       MODEL_SIZE="1.9 GB" ;;
            qwen2.5:1.5b)     MODEL_SIZE="986 MB" ;;
            qwen2.5:0.5b)     MODEL_SIZE="398 MB" ;;
            *)                MODEL_SIZE="size unknown" ;;
        esac
        LOW_RAM=false
    fi

    # ── Print diagnosis summary ────────────────────────────────────────
    echo ""
    echo -e "  ${CY}${BOLD}┌─────────────────────────────────────────────────────┐${R}"
    echo -e "  ${CY}${BOLD}│  System Diagnosis Summary                           │${R}"
    echo -e "  ${CY}${BOLD}├─────────────────────────────────────────────────────┤${R}"
    printf "  ${CY}│${R}  %-22s %-28s${CY}│${R}\n" "RAM:" "${RAM_GB} GB"
    printf "  ${CY}│${R}  %-22s %-28s${CY}│${R}\n" "Free disk:" "${DISK_FREE_GB} GB available"
    printf "  ${CY}│${R}  %-22s %-28s${CY}│${R}\n" "GPU:" "$GPU_INFO"
    printf "  ${CY}│${R}  %-22s %-28s${CY}│${R}\n" "AI model:" "$MODEL ($MODEL_SIZE)"
    echo -e "  ${CY}${BOLD}├─────────────────────────────────────────────────────┤${R}"

    # LLM mode assessment
    if [[ $LOW_RAM == "true" ]]; then
        box_status "$YL" "⚠" "LLM mode" "TINY MODEL OR REMOTE"
    elif [[ $DISK_FREE_GB -ge $DISK_NEED_GB ]]; then
        box_status "$GR" "✓" "LLM mode" "READY"
    else
        box_status "$RD" "✗" "LLM mode" "INSUFFICIENT RESOURCES"
    fi

    # RAG assessment
    if [[ "$RAG_CAPABLE" == "true" && $DISK_FREE_GB -ge 8 ]]; then
        box_status "$GR" "✓" "Smart RAG" "AVAILABLE"
        RAG_AVAILABLE=true
    else
        if [[ "$RAG_CAPABLE" == "false" ]]; then
            box_status "$YL" "⚠" "Smart RAG" "RAM < 5 GB: not advised"
        else
            box_status "$YL" "⚠" "Smart RAG" "DISK SPACE LOW"
        fi
        RAG_AVAILABLE=false
    fi

    echo -e "  ${CY}${BOLD}└─────────────────────────────────────────────────────┘${R}"

    # Warnings
    echo ""
    if [[ $RAM_MB -lt 4500 && $LOW_RAM == "false" ]]; then
        warn "Less than 5 GB of RAM: using the smaller $MODEL — answers are simpler, but it works."
    fi
    if [[ $DISK_FREE_GB -lt $DISK_NEED_GB ]]; then
        warn "Less than ${DISK_NEED_GB} GB free disk space. The AI model needs $MODEL_SIZE."
        warn "Free up space before continuing."
    fi
    if [[ $HAS_GPU == "false" ]]; then
        warn "No GPU detected. Responses will be slower (~4-10s per query on CPU)."
    fi

    [[ $LOW_RAM == "true" ]] && choose_backend
    return 0
}

# Below ~3 GB of RAM a local model is barely usable. Offer a tiny local
# model or a remote backend — remote only by explicit choice.
choose_backend() {
    echo ""
    echo -e "  ${BOLD}This machine has ${RAM_GB} GB of RAM — too little for a good local model.${R}"
    echo -e "  ${BOLD}1)${R} Tiny local model ${CY}qwen2.5:0.5b${R} (398 MB download) — 100% local, basic answers"
    echo -e "  ${BOLD}2)${R} Ollama on another computer in your network"
    echo -e "  ${BOLD}3)${R} An OpenAI-compatible API (LM Studio, llama.cpp server, vLLM or a cloud service)"
    ask "Choose [1]: "
    local choice reply
    answer choice 1
    case "${choice:-1}" in
        2)
            ask "Address of that Ollama (e.g. http://192.168.1.10:11434): "
            answer reply ""
            [[ "$reply" =~ ^https?://[^[:space:]]+$ ]] || err "Not a valid address: $reply"
            OLLAMA_URL="${reply%/}"
            if ! curl -fsS -m 5 "${OLLAMA_URL}/api/tags" -o /tmp/tuxaide_tags.json 2>/dev/null; then
                err "No Ollama answering at ${OLLAMA_URL}. Start it there with OLLAMA_HOST=0.0.0.0 ollama serve"
            fi
            local models
            models=$(python3 -c 'import json; print(" ".join(m["name"] for m in json.load(open("/tmp/tuxaide_tags.json")).get("models", [])))' 2>/dev/null || true)
            info "Models there: ${models:-none}"
            ask "Model to use [${models%% *}]: "
            answer MODEL "${models%% *}"
            [[ -n "$MODEL" ]] || err "No model chosen. Download one on that computer: ollama pull qwen2.5-coder:7b"
            BACKEND="ollama-remote"
            ;;
        3)
            ask "API address [https://api.openai.com/v1]: "
            answer API_BASE "https://api.openai.com/v1"
            API_BASE="${API_BASE%/}"
            [[ "$API_BASE" =~ ^https?://[^[:space:]]+$ ]] || err "Not a valid address: $API_BASE"
            ask "Model name (as the API calls it): "
            answer MODEL ""
            [[ "$MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || err "Not a valid model name: $MODEL"
            ask "Environment variable that holds your API key [OPENAI_API_KEY]: "
            answer API_KEY_ENV "OPENAI_API_KEY"
            [[ "$API_KEY_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || err "Not a valid variable name: $API_KEY_ENV"
            BACKEND="openai"
            ;;
        *)
            return 0
            ;;
    esac
    MODEL_SIZE="remote"
    local host="${OLLAMA_URL}"
    [[ "$BACKEND" == "openai" ]] && host="$API_BASE"
    case "$host" in
        http://localhost*|http://127.*) ;;
        *) warn "☁ Your questions will be sent to ${host} — they leave this machine." ;;
    esac
    # Nothing to download or run locally; Smart RAG needs a local Ollama.
    TOTAL_STEPS=$((TOTAL_STEPS - 2))
    RAG_CAPABLE=false
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 2 — Ask about RAG
# ═══════════════════════════════════════════════════════════════════════
ask_rag() {
    step "RAG mode — man page knowledge base"

    if [[ "$BACKEND" != "local" ]]; then
        info "Smart RAG needs a local Ollama for its embeddings — skipped with a remote backend."
        INSTALL_RAG=false
        return
    fi

    echo ""
    echo -e "  ${BOLD}What is Smart RAG mode?${R}"
    echo -e "  TuxAide can index the man pages installed on this system"
    echo -e "  and use them as a knowledge base — but only when the question"
    echo -e "  actually needs local documentation. This means:"
    echo ""
    echo -e "  ${GR}✓${R}  Simple questions answered in 3–5s (LLM direct)"
    echo -e "  ${GR}✓${R}  Complex questions answered in 8–15s (Smart RAG)"
    echo -e "  ${GR}✓${R}  Repeated questions answered instantly (cache)"
    echo -e "  ${GR}✓${R}  Drastically reduced hallucinations on local docs"
    echo -e "  ${GR}✓${R}  Responses cite the source: man page + section"
    echo ""
    echo -e "  ${DIM}Extra: ~300 MB RAM, ~400 MB download; man pages are indexed in the background${R}"
    echo -e "  ${DIM}If skipped now, you can enable it later with: tuxaide setup --rag${R}"
    echo ""

    if [[ "$RAG_AVAILABLE" == "false" || "$BACKEND" != "local" ]]; then
        warn "RAG mode is not recommended for this system (insufficient RAM or disk)."
        warn "Installing in LLM-only mode."
        INSTALL_RAG=false
        return
    fi

    if [[ "$FORCE_NO_RAG" == "true" ]]; then
        INSTALL_RAG=false
        info "Skipping Smart RAG (--no-rag). Enable later with: tuxaide setup --rag"
        return
    fi
    ask "Install Smart RAG mode? (recommended) [Y/n] "
    answer RAG_CONFIRM y
    if [[ "$RAG_CONFIRM" =~ ^[yYsS]$ ]]; then
        INSTALL_RAG=true
        ok "Smart RAG mode will be installed"
    else
        INSTALL_RAG=false
        info "Skipping RAG — installing LLM mode only"
        info "Enable later with: tuxaide setup --rag"
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# Everything the installer will do, before it does any of it
# ═══════════════════════════════════════════════════════════════════════
show_plan() {
    local -a missing=() pkgs=()
    local c sudo_note=""
    for c in python3 curl; do command -v "$c" &>/dev/null || missing+=("$c"); done
    [[ $EUID -eq 0 ]] || sudo_note=" (with sudo)"
    pkgs=("${missing[@]+"${missing[@]}"}")
    if [[ "$INSTALL_RAG" == "true" ]] && command -v apt-get &>/dev/null && ! python3 -c 'import ensurepip' &>/dev/null; then
        pkgs+=("python3-venv")
    fi
    local rc="bashrc"
    [[ "$CURRENT_SHELL" == "zsh" ]] && rc="zshrc"

    echo ""
    echo -e "  ${BOLD}The installer will:${R}"
    [[ ${#pkgs[@]} -gt 0 ]] && echo -e "   • install ${pkgs[*]} with your package manager${sudo_note}"
    if [[ "$BACKEND" == "local" ]]; then
        if command -v ollama &>/dev/null; then
            echo -e "   • use the Ollama already installed"
        elif [[ "$OS" == "macos" ]]; then
            echo -e "   • install Ollama (Homebrew, or the app from ollama.com)"
        else
            echo -e "   • install Ollama with its official script from ollama.com${sudo_note}"
        fi
        echo -e "   • download the model ${CY}${MODEL}${R} (${MODEL_SIZE})"
    else
        echo -e "   • use ${CY}${MODEL}${R} on ${OLLAMA_URL}${API_BASE:+ }${API_BASE} — nothing is downloaded"
    fi
    if [[ "$INSTALL_RAG" == "true" ]]; then
        echo -e "   • install Smart RAG: chromadb in ~/.local/share/tuxaide/venv (~150 MB) and"
        echo -e "     nomic-embed-text (274 MB); index man pages in the background"
    fi
    echo -e "   • write ~/.local/bin/tuxaide* and ~/.config/tuxaide/ (from release v${TUXAIDE_VERSION})"
    echo -e "   • add a 3-line TuxAide block to ~/.${rc} (a backup is kept)"
    echo ""
    ask "Proceed? [Y/n] "
    local reply
    answer reply y
    if [[ ! "$reply" =~ ^[yYsS]$ ]]; then
        echo ""
        echo -e "  ${YL}Installation cancelled. Nothing was changed.${R}"
        echo ""
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 3 — Dependencies
# ═══════════════════════════════════════════════════════════════════════
install_dependencies() {
    step "Installing dependencies"

    if   command -v apt-get &>/dev/null; then PKG_MGR="apt-get"; INSTALL="apt-get install -y -qq"
    elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";     INSTALL="dnf install -y -q"
    elif command -v yum     &>/dev/null; then PKG_MGR="yum";     INSTALL="yum install -y -q"
    elif command -v pacman  &>/dev/null; then PKG_MGR="pacman";  INSTALL="pacman -S --noconfirm --quiet"
    elif command -v zypper  &>/dev/null; then PKG_MGR="zypper";  INSTALL="zypper install -y"
    else PKG_MGR=""; fi

    _need() {
        local cmd="$1" pkg="${2:-$1}"
        if command -v "$cmd" &>/dev/null; then ok "$cmd already available"; return; fi
        if [[ -z "$PKG_MGR" ]]; then err "$cmd required but not found."; fi
        info "Installing $pkg..."
        if [[ $EUID -eq 0 ]]; then $INSTALL "$pkg" &>/dev/null
        else sudo $INSTALL "$pkg" &>/dev/null; fi
        ok "$pkg installed"
    }

    if [[ -n "$PKG_MGR" && "$PKG_MGR" == "apt-get" ]]; then
        info "Updating repositories..."
        if [[ $EUID -eq 0 ]]; then apt-get update -qq &>/dev/null
        else sudo apt-get update -qq &>/dev/null; fi
    fi

    _need python3
    _need curl

    PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    ok "Python $PY_VER"

    [[ "$INSTALL_RAG" == "true" ]] && setup_rag_venv
    return 0
}

# RAG dependencies go into TuxAide's own virtualenv, never into the system
# Python: no `pip` command needed, no --break-system-packages, and uninstall
# removes them cleanly.
setup_rag_venv() {
    if [[ -x "$VENV/bin/python" ]] && "$VENV/bin/python" -c 'import chromadb, tiktoken' &>/dev/null; then
        ok "RAG dependencies already installed (venv: ${VENV})"
        return 0
    fi
    info "Installing RAG dependencies (chromadb, tiktoken) into ${VENV}..."

    # Debian/Ubuntu ship venv support as a separate package.
    if [[ "$PKG_MGR" == "apt-get" ]] && ! python3 -c 'import ensurepip' &>/dev/null; then
        info "Installing python3-venv..."
        if [[ $EUID -eq 0 ]]; then $INSTALL python3-venv &>/dev/null || true
        else sudo $INSTALL python3-venv &>/dev/null || true; fi
    fi

    # Try the default python3 first, then other installed versions, in case
    # chromadb has no wheels yet for the newest Python.
    local -a candidates=(python3)
    local v
    for v in 3.13 3.12 3.11 3.10; do
        command -v "python${v}" &>/dev/null && candidates+=("python${v}")
    done

    local py log="/tmp/tuxaide_venv.log"
    : > "$log"
    for py in "${candidates[@]}"; do
        rm -rf "$VENV"
        mkdir -p "$(dirname "$VENV")"
        if "$py" -m venv "$VENV" >>"$log" 2>&1 \
           && "$VENV/bin/python" -m pip install -q --upgrade pip >>"$log" 2>&1 \
           && "$VENV/bin/python" -m pip install -q chromadb tiktoken >>"$log" 2>&1 \
           && "$VENV/bin/python" -c 'import chromadb, tiktoken' >>"$log" 2>&1; then
            ok "RAG dependencies installed ($("$VENV/bin/python" --version 2>&1), venv: ${VENV})"
            return 0
        fi
        info "$py: could not set up the RAG environment, trying next Python..."
    done

    rm -rf "$VENV"
    warn "Could not install chromadb (details: $log)."
    warn "Continuing in LLM-only mode. Re-run the installer later to enable Smart RAG."
    INSTALL_RAG=false
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 4 — Ollama
# ═══════════════════════════════════════════════════════════════════════
install_ollama() {
    [[ "$BACKEND" == "local" ]] || return 0
    step "Installing Ollama"

    if command -v ollama &>/dev/null; then
        ok "Ollama already installed: $(ollama --version 2>/dev/null | head -1)"
        return
    fi

    if [[ "$OS" == "macos" ]]; then
        if command -v brew &>/dev/null; then
            info "Installing Ollama via Homebrew..."
            brew install ollama &>/tmp/lg_ollama.log && ok "Ollama installed (Homebrew)"
        else
            info "Downloading Ollama for macOS..."
            curl -fL "https://ollama.com/download/Ollama-darwin.zip" -o /tmp/ollama_mac.zip 2>/dev/null
            unzip -q /tmp/ollama_mac.zip -d /tmp/ollama_mac
            cp -r /tmp/ollama_mac/Ollama.app /Applications/ 2>/dev/null || true
            if [[ -f "/Applications/Ollama.app/Contents/Resources/ollama" ]]; then
                sudo ln -sf "/Applications/Ollama.app/Contents/Resources/ollama" /usr/local/bin/ollama 2>/dev/null || true
            fi
            ok "Ollama installed (macOS app)"
        fi
    else
        info "Downloading Ollama (official installer)..."
        if curl -fsSL https://ollama.com/install.sh | sh 2>/tmp/lg_ollama.log; then
            ok "Ollama installed"
        else
            warn "Official installer failed — trying direct binary..."
            curl -fL "https://ollama.com/download/ollama-linux-${ARCH_LABEL}" -o /tmp/ollama_bin 2>/dev/null
            chmod +x /tmp/ollama_bin
            if [[ $EUID -eq 0 ]]; then mv /tmp/ollama_bin /usr/local/bin/ollama
            else sudo mv /tmp/ollama_bin /usr/local/bin/ollama; fi
            ok "Ollama installed (direct binary)"
        fi
    fi
    export PATH="/usr/local/bin:$PATH"
}

start_ollama() {
    [[ "$BACKEND" == "local" ]] || return 0
    step "Starting Ollama service"

    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        ok "Ollama is already running"
        return
    fi

    if [[ "$OS" == "macos" ]]; then
        if command -v brew &>/dev/null && brew list ollama &>/dev/null 2>&1; then
            brew services start ollama &>/dev/null || true
            ok "Ollama started via Homebrew services"
        else
            nohup ollama serve &>/tmp/ollama.log &
            ok "Ollama started in background"
        fi
    elif [[ "$HAS_SYSTEMD" == "true" ]]; then
        info "Registering as systemd service (starts on boot)..."
        # Ollama's official installer creates its own unit and user; only
        # write ours when it didn't (e.g. the direct-binary fallback).
        if [[ ! -f /etc/systemd/system/ollama.service ]] && ! id -u ollama &>/dev/null; then
            if [[ $EUID -eq 0 ]]; then useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true
            else sudo useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true; fi
        fi
        if [[ ! -f /etc/systemd/system/ollama.service ]]; then
            local svc
            svc="[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=$(command -v ollama) serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment=\"PATH=$PATH\"

[Install]
WantedBy=multi-user.target"
            if [[ $EUID -eq 0 ]]; then echo "$svc" > /etc/systemd/system/ollama.service
            else echo "$svc" | sudo tee /etc/systemd/system/ollama.service > /dev/null; fi
        fi
        if [[ $EUID -eq 0 ]]; then systemctl daemon-reload; systemctl enable ollama --now
        else sudo systemctl daemon-reload; sudo systemctl enable ollama --now; fi
        ok "Ollama service enabled (starts on boot)"
    else
        nohup ollama serve &>/tmp/ollama.log &
        echo $! > /tmp/tuxaide_ollama.pid
        ok "Ollama started in background"
    fi

    info "Waiting for Ollama to become available..."
    local n=0
    until curl -s http://localhost:11434/api/tags &>/dev/null; do
        sleep 1; n=$((n + 1))   # not ((n++)): it returns 1 when n=0, and set -e exits
        [[ $n -ge 40 ]] && err "Ollama did not respond in 40s. Check: journalctl -u ollama -n 20"
        printf "."
    done
    printf "\n"
    ok "Ollama available at http://localhost:11434"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 5 — AI Models
# ═══════════════════════════════════════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════════
# STEP 6 — Install TuxAide files
# ═══════════════════════════════════════════════════════════════════════
resolve_source_dir() {
    local src=""
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    if [[ -f "${src}/agent.py" && -f "${src}/hook.sh" && -f "${src}/uninstall.sh" && -f "${src}/session_writer.py" ]]; then
        echo "$src"
        return
    fi
    echo ""
}

# Files come from the release tagged v$TUXAIDE_VERSION and are checked against
# its SHA256SUMS. Until that release exists, main is used (with a warning).
REPO_SLUG="${TUXAIDE_REPO:-deltaxmodules/tuxaide}"
REF="${TUXAIDE_REF:-v${TUXAIDE_VERSION}}"
RAW_BASE=""
SUMS_FILE=""

sha256_of() {
    if command -v sha256sum &>/dev/null; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

prepare_downloads() {
    RAW_BASE="${TUXAIDE_RAW_BASE:-https://raw.githubusercontent.com/${REPO_SLUG}/${REF}}"
    if [[ -z "${TUXAIDE_RAW_BASE:-}" ]] && ! curl -fsSI "${RAW_BASE}/agent.py" -o /dev/null 2>/dev/null; then
        [[ -n "${TUXAIDE_REF:-}" ]] && err "${REF} not found in ${REPO_SLUG}"
        warn "Release ${REF} isn't published yet — installing from main (no checksums)."
        REF="main"
        RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/main"
        return 0
    fi
    SUMS_FILE="$(mktemp)"
    local web="${TUXAIDE_GITHUB_WEB:-https://github.com}"
    if curl -fsSL "${web}/${REPO_SLUG}/releases/download/${REF}/SHA256SUMS" -o "$SUMS_FILE" 2>/dev/null; then
        ok "Downloading from release ${REF} (checked against SHA256SUMS)"
    else
        warn "Release ${REF} has no SHA256SUMS — files can't be verified."
        rm -f "$SUMS_FILE"; SUMS_FILE=""
    fi
}

fetch_component() {
    local name="$1" dest="$2"
    local src_dir="$3"

    if [[ -n "$src_dir" && -f "${src_dir}/${name}" ]]; then
        cp "${src_dir}/${name}" "$dest"
        return 0
    fi

    [[ -n "$RAW_BASE" ]] || prepare_downloads
    curl -fsSL "${RAW_BASE}/${name}" -o "$dest" || return 1
    if [[ -n "$SUMS_FILE" ]]; then
        local want got
        want="$(awk -v f="$name" '$2 == f || $2 == "*" f {print $1}' "$SUMS_FILE")"
        got="$(sha256_of "$dest")"
        if [[ -z "$want" || "$want" != "$got" ]]; then
            rm -f "$dest"
            err "${name} doesn't match the release's SHA256SUMS — download aborted."
        fi
    fi
}

# Download every file and check it against SHA256SUMS before anything else is
# installed: a bad download stops the installer with nothing changed.
STAGE=""
stage_components() {
    STAGE="$(mktemp -d)"
    local src_dir name
    src_dir="$(resolve_source_dir)"
    for name in agent.py hook.sh session_writer.py uninstall.sh indexer.py; do
        fetch_component "$name" "${STAGE}/${name}" "$src_dir" || err "Failed to fetch ${name}"
    done
}

# When the RAG venv exists, run the script with its Python so chromadb is importable.
use_venv_python() {
    local file="$1"
    [[ -x "$VENV/bin/python" ]] || return 0
    { echo "#!${VENV}/bin/python"; tail -n +2 "$file"; } > "${file}.tmp" && mv "${file}.tmp" "$file"
}

install_agent() {
    step "Installing TuxAide components"

    local BIN="${HOME}/.local/bin"
    local CFG="${HOME}/.config/tuxaide"
    local SRC_DIR="$STAGE"

    mkdir -p "$BIN" "$CFG"

    fetch_component "agent.py" "${BIN}/tuxaide" "$SRC_DIR" || err "Failed to fetch agent.py"
    use_venv_python "${BIN}/tuxaide"
    chmod +x "${BIN}/tuxaide"
    ok "Binary installed → ${BIN}/tuxaide"

    fetch_component "hook.sh" "${CFG}/hook.sh" "$SRC_DIR" || err "Failed to fetch hook.sh"
    ok "Hook installed → ${CFG}/hook.sh"

    fetch_component "session_writer.py" "${CFG}/session_writer.py" "$SRC_DIR" || err "Failed to fetch session_writer.py"
    chmod +x "${CFG}/session_writer.py"
    ok "Session writer installed → ${CFG}/session_writer.py"

    fetch_component "uninstall.sh" "${BIN}/tuxaide-uninstall" "$SRC_DIR" || err "Failed to fetch uninstall.sh"
    chmod +x "${BIN}/tuxaide-uninstall"
    ok "Uninstaller → ${BIN}/tuxaide-uninstall"

    fetch_component "indexer.py" "${BIN}/tuxaide-index" "$SRC_DIR" || err "Failed to fetch indexer.py"
    use_venv_python "${BIN}/tuxaide-index"
    chmod +x "${BIN}/tuxaide-index"
    ok "Indexer installed → ${BIN}/tuxaide-index"
}
# ═══════════════════════════════════════════════════════════════════════
# STEP 7 — tuxaide setup: settings, model, Smart RAG, shell rc, doctor
# ═══════════════════════════════════════════════════════════════════════
run_setup() {
    step "Setting up the model and your shell"

    local tux="${HOME}/.local/bin/tuxaide"
    if [[ "$BACKEND" == "ollama-remote" ]]; then
        "$tux" --set ollama_url "$OLLAMA_URL"
    elif [[ "$BACKEND" == "openai" ]]; then
        "$tux" --set backend openai
        "$tux" --set api_base "$API_BASE"
        "$tux" --set api_key_env "$API_KEY_ENV"
    fi
    [[ "$BACKEND" == "local" ]] || "$tux" --set prewarm off

    local -a args=(--yes)
    # A model picked here (command line, remote choice) is set; otherwise
    # setup keeps the current one or picks the one for this RAM.
    [[ -n "$MODEL_OVERRIDE" || "$BACKEND" != "local" ]] && args+=(--model "$MODEL")
    if [[ "$INSTALL_RAG" == "true" ]]; then args+=(--rag); else args+=(--no-rag); fi
    local sh="$CURRENT_SHELL"
    [[ "$sh" == "zsh" || "$sh" == "bash" ]] || sh="bash"
    args+=(--shell "$sh")
    "$tux" setup "${args[@]}" || warn "tuxaide setup reported a problem — see above"
}

print_summary() {
    local mode_label="LLM only"
    [[ "$INSTALL_RAG" == "true" ]] && mode_label="Smart RAG (man pages being indexed in the background)"

    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🐧  TuxAide ${TUXAIDE_VERSION} installed and ready!            ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    local rc="bashrc"
    [[ "$CURRENT_SHELL" == "zsh" ]] && rc="zshrc"
    echo -e "  ${YL}${BOLD}⚡ Open a new terminal, or run this now to activate:${R}"
    echo ""
    echo -e "  ${BOLD}    source ~/.${rc}${R}"
    echo ""
    echo -e "  ${DIM}(Future sessions activate automatically.)${R}"
    echo ""
    echo -e "  ${BOLD}Active mode:${R}  ${CY}${mode_label}${R}"
    echo -e "  ${BOLD}AI model:${R}     ${CY}${MODEL}${R}"
    if [[ "$BACKEND" == "openai" ]]; then
        echo -e "  ${BOLD}API:${R}          ${CY}${API_BASE}${R}"
        echo ""
        echo -e "  ${YL}${BOLD}Put your API key in your shell rc (TuxAide never stores it):${R}"
        echo -e "  ${BOLD}    echo 'export ${API_KEY_ENV}=…' >> ~/.${CURRENT_SHELL}rc${R}"
    elif [[ "$BACKEND" == "ollama-remote" ]]; then
        echo -e "  ${BOLD}Ollama:${R}       ${CY}${OLLAMA_URL}${R}"
    fi
    echo ""
    echo -e "  ${BOLD}How to use:${R}"
    echo -e "  ${CY}how do I list hidden files${R}        ← type directly"
    echo -e "  ${CY}como listar ficheiros ocultos${R}     ← any language"
    echo -e "  ${CY}tuxaide how to check open ports${R}   ← explicit mode"
    echo ""
    echo -e "  ${BOLD}Mode control:${R}"
    echo -e "  ${CY}tuxaide mode smart${R} — Smart RAG (recommended)"
    echo -e "  ${CY}tuxaide mode deep${R}  — full RAG for every question"
    echo -e "  ${CY}tuxaide mode llm${R}   — LLM only, no man pages"
    echo -e "  ${CY}tuxaide status${R}     — show current mode"
    echo -e "  ${CY}tuxaide --timing${R}   — show recent query performance"
    echo -e "  ${CY}tuxaide doctor${R}     — check that everything works"
    echo -e "  ${CY}tuxaide update${R}     — update to the latest release"
    if [[ "$INSTALL_RAG" == "true" ]]; then
        echo ""
        echo -e "  ${BOLD}Re-index after system updates:${R}"
        echo -e "  ${CY}tuxaide reindex${R}      — re-index all man pages"
        echo -e "  ${CY}tuxaide index nginx${R}  — index a specific command"
    fi
    echo ""
    echo -e "  ${BOLD}Uninstall:${R}  ${CY}tuxaide uninstall${R}"
    echo ""
    echo -e "  ${DIM}Config: ~/.config/tuxaide/config.json${R}"
    echo -e "  ${DIM}Perf log: ~/.config/tuxaide/logs/perf.log${R}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════
main() {
    banner
    diagnose_system
    ask_rag
    show_plan
    install_dependencies
    stage_components
    install_ollama
    start_ollama
    install_agent
    run_setup
    print_summary || true
}

main
