#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
#  TuxAide v2.1 — Complete Installer with Smart RAG
#  https://github.com/deltaxmodules/tuxaide
#
#  One-liner install:
#    curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup.sh | bash
#
#  What it does:
#    1.  Detects distro, architecture, RAM and GPU
#    2.  Shows system diagnosis and asks for confirmation
#    3.  Installs all v1 components (Ollama, model, shell hook)
#    4.  Asks if user wants RAG mode (man page knowledge base)
#    5.  If yes: installs ChromaDB, embedding model, indexes man pages
#    6.  Activates immediately — no terminal restart needed
#
#  v2.1 changes (smart RAG):
#    - Smart router: RAG only when the question needs local docs
#    - Cache: embeddings and answers cached to disk (MD5 key)
#    - RAG filtered by detected command (faster, less noise)
#    - top_k reduced to 1 in smart mode (300 tokens max)
#    - Silent perf log at ~/.config/tuxaide/logs/perf.log
#    - Destructive command warning shown before code blocks
#
#  To disable RAG:   tuxaide mode llm
#  To re-enable RAG: tuxaide mode smart
#  To uninstall:     tuxaide-uninstall
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────
R="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
CY="\033[36m"; GR="\033[32m"; YL="\033[33m"; RD="\033[31m"; MG="\033[35m"

# ── Helpers ───────────────────────────────────────────────────────────
banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🐧  TuxAide v2.1 — Complete Installer             ║${R}"
    echo -e "${CY}${BOLD}║   Local AI assistant with Smart RAG                 ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
}
step()  { echo -e "\n${CY}${BOLD}[$((++STEP))/$TOTAL_STEPS] $*${R}"; }
ok()    { echo -e "  ${GR}✓${R}  $*"; }
warn()  { echo -e "  ${YL}⚠${R}  $*"; }
info()  { echo -e "  ${DIM}→  $*${R}"; }
err()   { echo -e "\n${RD}${BOLD}  ✗  ERROR: $*${R}\n"; exit 1; }
ask()   { echo -e "  ${MG}?${R}  $*"; }

STEP=0
TOTAL_STEPS=9
INSTALL_RAG=false
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
        RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        RAM_GB=$((RAM_BYTES / 1024 / 1024 / 1024))
    else
        RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
        RAM_GB=$((RAM_KB / 1024 / 1024))
    fi
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
    if [[ $RAM_GB -ge 8 ]]; then
        MODEL="qwen2.5-coder:7b"
        MODEL_SIZE="4.7 GB"
        MODEL_NOTE="Linux/code specialist — best quality"
        RAG_CAPABLE=true
    elif [[ $RAM_GB -ge 5 ]]; then
        MODEL="qwen2.5:3b"
        MODEL_SIZE="1.9 GB"
        MODEL_NOTE="good Linux knowledge, 5-8 GB RAM"
        RAG_CAPABLE=true
    else
        MODEL="qwen2.5:3b"
        MODEL_SIZE="1.9 GB"
        MODEL_NOTE="best lightweight option — RAM is limited"
        RAG_CAPABLE=false
    fi

    # ── Print diagnosis summary ────────────────────────────────────────
    echo ""
    echo -e "  ${CY}${BOLD}┌─────────────────────────────────────────────────────┐${R}"
    echo -e "  ${CY}${BOLD}│  System Diagnosis Summary                           │${R}"
    echo -e "  ${CY}${BOLD}├─────────────────────────────────────────────────────┤${R}"
    printf "  ${CY}│${R}  %-25s %-28s${CY}│${R}\n" "RAM:" "${RAM_GB} GB"
    printf "  ${CY}│${R}  %-25s %-28s${CY}│${R}\n" "Free disk:" "${DISK_FREE_GB} GB available"
    printf "  ${CY}│${R}  %-25s %-28s${CY}│${R}\n" "GPU:" "$GPU_INFO"
    printf "  ${CY}│${R}  %-25s %-28s${CY}│${R}\n" "AI model:" "$MODEL ($MODEL_SIZE)"
    echo -e "  ${CY}${BOLD}├─────────────────────────────────────────────────────┤${R}"

    # v1 assessment
    if [[ $RAM_GB -ge 5 && $DISK_FREE_GB -ge 6 ]]; then
        echo -e "  ${CY}│${R}  ${GR}✓${R} TuxAide v1 (LLM mode)    ${GR}READY${R}                    ${CY}│${R}"
    else
        echo -e "  ${CY}│${R}  ${RD}✗${R} TuxAide v1 (LLM mode)    ${RD}INSUFFICIENT RESOURCES${R}   ${CY}│${R}"
    fi

    # RAG assessment
    if [[ "$RAG_CAPABLE" == "true" && $DISK_FREE_GB -ge 8 ]]; then
        echo -e "  ${CY}│${R}  ${GR}✓${R} TuxAide v2.1 (Smart RAG) ${GR}AVAILABLE${R}                ${CY}│${R}"
        RAG_AVAILABLE=true
    else
        if [[ "$RAG_CAPABLE" == "false" ]]; then
            echo -e "  ${CY}│${R}  ${YL}⚠${R} TuxAide v2.1 (Smart RAG) ${YL}RAM < 5 GB — not recommended${R} ${CY}│${R}"
        else
            echo -e "  ${CY}│${R}  ${YL}⚠${R} TuxAide v2.1 (Smart RAG) ${YL}DISK SPACE LOW${R}           ${CY}│${R}"
        fi
        RAG_AVAILABLE=false
    fi

    echo -e "  ${CY}${BOLD}└─────────────────────────────────────────────────────┘${R}"

    # Warnings
    echo ""
    if [[ $RAM_GB -lt 5 ]]; then
        warn "RAM is below 5 GB. Installation will proceed but performance may be poor."
    fi
    if [[ $DISK_FREE_GB -lt 6 ]]; then
        warn "Less than 6 GB free disk space. The AI model requires ~5 GB."
        warn "Free up space before continuing."
    fi
    if [[ $HAS_GPU == "false" ]]; then
        warn "No GPU detected. Responses will be slower (~4-10s per query on CPU)."
    fi

    # Confirmation
    echo ""
    ask "Proceed with installation? [Y/n] "
    read -r CONFIRM </dev/tty
    CONFIRM="${CONFIRM:-y}"
    if [[ ! "$CONFIRM" =~ ^[yYsS]$ ]]; then
        echo ""
        echo -e "  ${YL}Installation cancelled.${R}"
        echo ""
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 2 — Ask about RAG
# ═══════════════════════════════════════════════════════════════════════
ask_rag() {
    step "RAG mode — man page knowledge base"

    echo ""
    echo -e "  ${BOLD}What is Smart RAG mode?${R}"
    echo -e "  TuxAide v2.1 can index the man pages installed on this system"
    echo -e "  and use them as a knowledge base — but only when the question"
    echo -e "  actually needs local documentation. This means:"
    echo ""
    echo -e "  ${GR}✓${R}  Simple questions answered in 3–5s (LLM direct)"
    echo -e "  ${GR}✓${R}  Complex questions answered in 8–15s (Smart RAG)"
    echo -e "  ${GR}✓${R}  Repeated questions answered instantly (cache)"
    echo -e "  ${GR}✓${R}  Drastically reduced hallucinations on local docs"
    echo -e "  ${GR}✓${R}  Responses cite the source: man page + section"
    echo ""
    echo -e "  ${DIM}Extra requirements: ~300 MB RAM + ~10 min indexing (one-time)${R}"
    echo -e "  ${DIM}If skipped now, you can enable later with: tuxaide mode smart${R}"
    echo ""

    if [[ "$RAG_AVAILABLE" == "false" ]]; then
        warn "RAG mode is not recommended for this system (insufficient RAM or disk)."
        warn "Installing in LLM-only mode (v1 behaviour)."
        INSTALL_RAG=false
        return
    fi

    ask "Install Smart RAG mode? (recommended) [Y/n] "
    read -r RAG_CONFIRM </dev/tty
    RAG_CONFIRM="${RAG_CONFIRM:-y}"
    if [[ "$RAG_CONFIRM" =~ ^[yYsS]$ ]]; then
        INSTALL_RAG=true
        ok "Smart RAG mode will be installed"
    else
        INSTALL_RAG=false
        info "Skipping RAG — installing LLM mode only (v1 behaviour)"
        info "Enable later with: tuxaide mode smart"
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
    _need unzip

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
        if ! id -u ollama &>/dev/null; then
            if [[ $EUID -eq 0 ]]; then useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true
            else sudo useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true; fi
        fi
        if [[ ! -f /etc/systemd/system/ollama.service ]]; then
            local svc="[Unit]
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
        sleep 1; ((n++))
        [[ $n -ge 40 ]] && err "Ollama did not respond in 40s. Check: journalctl -u ollama -n 20"
        printf "."
    done
    printf "\n"
    ok "Ollama available at http://localhost:11434"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 5 — AI Models
# ═══════════════════════════════════════════════════════════════════════
download_models() {
    step "Downloading AI models"

    # Main LLM
    if ollama list 2>/dev/null | grep -q "^${MODEL%:*}"; then
        ok "Model $MODEL already exists"
    else
        info "Downloading $MODEL ($MODEL_SIZE) — this may take a few minutes..."
        echo ""
        ollama pull "$MODEL" || err "Failed to download $MODEL"
        echo ""
        ok "Model $MODEL ready"
    fi

    # Embedding model for RAG
    if [[ "$INSTALL_RAG" == "true" ]]; then
        if ollama list 2>/dev/null | grep -q "^nomic-embed-text"; then
            ok "Embedding model nomic-embed-text already exists"
        else
            info "Downloading embedding model: nomic-embed-text (274 MB)..."
            ollama pull nomic-embed-text || warn "Failed to download embedding model — RAG will be disabled"
            ok "Embedding model ready"
        fi
    fi
}

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

fetch_component() {
    local name="$1" dest="$2"
    local src_dir="$3"

    if [[ -n "$src_dir" && -f "${src_dir}/${name}" ]]; then
        cp "${src_dir}/${name}" "$dest"
        return 0
    fi

    local repo="${TUXAIDE_REPO:-deltaxmodules/tuxaide}"
    local ref="${TUXAIDE_REF:-main}"
    local base_url="${TUXAIDE_RAW_BASE:-https://raw.githubusercontent.com/${repo}/${ref}}"
    curl -fsSL "${base_url}/${name}" -o "$dest" || return 1
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
    local SRC_DIR
    SRC_DIR="$(resolve_source_dir)"

    mkdir -p "$BIN" "$CFG"

    fetch_component "agent.py" "${BIN}/tuxaide" "$SRC_DIR" || err "Failed to fetch agent.py"
    use_venv_python "${BIN}/tuxaide"
    chmod +x "${BIN}/tuxaide"
    ok "Binary installed → ${BIN}/tuxaide"

    local mode_val="llm"
    [[ "$INSTALL_RAG" == "true" ]] && mode_val="smart"

    # Keeping a resident 4.7 GB model warm on small machines hurts more than it helps.
    local prewarm_val="once"
    [[ $RAM_GB -lt 8 ]] && prewarm_val="off"

    # Merge with any existing config: settings the user already has win,
    # new keys get these defaults. Values are passed as arguments, not interpolated.
    local cfg_msg
    cfg_msg=$(python3 - "${CFG}/config.json" "$MODEL" "$mode_val" "$prewarm_val" <<'PYEOF'
import json, os, sys
path, model, mode, prewarm = sys.argv[1:5]
defaults = {
    "ollama_url": "http://localhost:11434",
    "model": model,
    "embed_model": "nomic-embed-text",
    "max_tokens": 300,
    "temperature": 0.1,
    "color": True,
    "mode": mode,
    "session_capture": True,
    "rag_top_k": 1,
    "rag_timeout": 8,
    "rag_db_path": "~/.config/tuxaide/vectordb",
    "enabled": True,
    "prewarm": prewarm,
    "keep_alive": "10m",
    "cache_ttl_days": 30,
    "action_menu": True,
    "failure_hint": True,
}
existing = {}
try:
    with open(path) as f: existing = json.load(f)
except Exception:
    pass
merged = {**defaults, **existing}
tmp = path + ".tmp"
with open(tmp, "w") as f: json.dump(merged, f, indent=4)
os.replace(tmp, path)
print(f"kept existing settings, mode: {merged['mode']}" if existing else f"mode: {merged['mode']}")
PYEOF
) || err "Failed to write ${CFG}/config.json"
    ok "Config → ${CFG}/config.json  (${cfg_msg})"

    fetch_component "hook.sh" "${CFG}/hook.sh" "$SRC_DIR" || err "Failed to fetch hook.sh"
    ok "Hook installed → ${CFG}/hook.sh"

    fetch_component "session_writer.py" "${CFG}/session_writer.py" "$SRC_DIR" || err "Failed to fetch session_writer.py"
    chmod +x "${CFG}/session_writer.py"
    ok "Session writer installed → ${CFG}/session_writer.py"

    fetch_component "uninstall.sh" "${BIN}/tuxaide-uninstall" "$SRC_DIR" || err "Failed to fetch uninstall.sh"
    chmod +x "${BIN}/tuxaide-uninstall"
    ok "Uninstaller → ${BIN}/tuxaide-uninstall"

    if [[ "$INSTALL_RAG" == "true" ]]; then
        fetch_component "indexer.py" "${BIN}/tuxaide-index" "$SRC_DIR" || err "Failed to fetch indexer.py"
        use_venv_python "${BIN}/tuxaide-index"
        chmod +x "${BIN}/tuxaide-index"
        ok "Indexer installed → ${BIN}/tuxaide-index"
    fi
}
# ═══════════════════════════════════════════════════════════════════════
# STEP 7 — Index man pages (RAG only)
# ═══════════════════════════════════════════════════════════════════════
index_man_pages() {
    [[ "$INSTALL_RAG" != "true" ]] && return

    step "Indexing man pages (Smart RAG knowledge base)"

    info "This runs once and takes approximately 5-10 minutes."
    info "Indexing the top 100 most useful Linux commands..."
    echo ""

    if "${HOME}/.local/bin/tuxaide-index" --all; then
        ok "Man pages indexed successfully"
    else
        warn "Indexing failed — Smart RAG mode will fallback to LLM automatically"
        python3 -c "
import json, os
f = os.path.expanduser('~/.config/tuxaide/config.json')
with open(f) as fp: c = json.load(fp)
c['mode'] = 'llm'
with open(f, 'w') as fp: json.dump(c, fp, indent=4)
" 2>/dev/null || true
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 8 — Activate in shell
# ═══════════════════════════════════════════════════════════════════════
activate_shell() {
    step "Activating in shell"

    local CFG="${HOME}/.config/tuxaide"
    local BIN="${HOME}/.local/bin"
    local HOOK_LINE="source \"${CFG}/hook.sh\"  # TuxAide"
    local PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\"  # TuxAide"

    local -a RCS=()
    [[ "$CURRENT_SHELL" == "zsh"  ]] && RCS+=("${HOME}/.zshrc")
    [[ "$CURRENT_SHELL" == "bash" ]] && RCS+=("${HOME}/.bashrc")
    [[ ${#RCS[@]} -eq 0 ]] && RCS=("${HOME}/.bashrc" "${HOME}/.zshrc")

    for RC in "${RCS[@]}"; do
        [[ -f "$RC" ]] || touch "$RC"
        if ! grep -qF "local/bin" "$RC" 2>/dev/null; then
            echo "$PATH_LINE" >> "$RC"
            ok "PATH added to $RC"
        fi
        if grep -qF "tuxaide/hook.sh" "$RC" 2>/dev/null; then
            ok "Hook already present in $RC"
        else
            { echo ""; echo "$HOOK_LINE"; } >> "$RC"
            ok "Hook added to $RC"
        fi
    done

    export PATH="${HOME}/.local/bin:${PATH}"
    # shellcheck disable=SC1090
    source "${CFG}/hook.sh"
    ok "Hook active in current session"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 9 — Final check and summary
# ═══════════════════════════════════════════════════════════════════════
final_check() {
    step "Final check"

    local ok_count=0 fail_count=0

    _chk() {
        local desc="$1" cmd="$2"
        if eval "$cmd" &>/dev/null; then ok "$desc"; ok_count=$((ok_count+1))
        else warn "$desc  ← FAILED"; fail_count=$((fail_count+1)); fi
    }

    _chk "Ollama installed"         "command -v ollama"
    _chk "Ollama responding"        "curl -s http://localhost:11434/api/tags"
    _chk "Model $MODEL available"   "ollama list | grep -q '${MODEL%:*}'"
    _chk "tuxaide binary"           "test -x ${HOME}/.local/bin/tuxaide"
    _chk "Hook in shell RC"         "grep -q tuxaide/hook.sh ${HOME}/.bashrc 2>/dev/null || grep -q tuxaide/hook.sh ${HOME}/.zshrc 2>/dev/null"

    if [[ "$INSTALL_RAG" == "true" ]]; then
        _chk "nomic-embed-text model" "ollama list | grep -q nomic-embed-text"
        _chk "ChromaDB installed"     "'${VENV}/bin/python' -c 'import chromadb'"
        _chk "Vector DB exists"       "test -d ${HOME}/.config/tuxaide/vectordb"
    fi

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        echo -e "${GR}${BOLD}  ✓ Everything installed! ($ok_count checks passed)${R}"
    else
        echo -e "${YL}  ⚠ $ok_count ok, $fail_count with issues — check warnings above${R}"
    fi
    return 0
}

print_summary() {
    local mode_label="LLM only (v1 behaviour)"
    [[ "$INSTALL_RAG" == "true" ]] && mode_label="Smart RAG (uses local docs only when needed)"

    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🐧  TuxAide v2.1 installed and ready!             ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${YL}${BOLD}⚡ Required — run this now to activate:${R}"
    echo ""
    echo -e "  ${BOLD}    source ~/.bashrc${R}    ${DIM}# Linux${R}"
    echo -e "  ${BOLD}    source ~/.zshrc${R}     ${DIM}# macOS${R}"
    echo ""
    echo -e "  ${DIM}(Future sessions activate automatically.)${R}"
    echo ""
    echo -e "  ${BOLD}Active mode:${R}  ${CY}${mode_label}${R}"
    echo -e "  ${BOLD}AI model:${R}     ${CY}${MODEL}${R}"
    echo ""
    echo -e "  ${BOLD}How to use:${R}"
    echo -e "  ${CY}how do I list hidden files${R}        ← type directly"
    echo -e "  ${CY}como listar ficheiros ocultos${R}     ← any language"
    echo -e "  ${CY}tuxaide how to check open ports${R}   ← explicit mode"
    echo ""
    echo -e "  ${BOLD}Mode control:${R}"
    echo -e "  ${CY}tuxaide mode smart${R} — Smart RAG (default, recommended)"
    echo -e "  ${CY}tuxaide mode deep${R}  — full RAG for every question"
    echo -e "  ${CY}tuxaide mode llm${R}   — LLM only, no man pages"
    echo -e "  ${CY}tuxaide status${R}     — show current mode"
    echo -e "  ${CY}tuxaide --timing${R}   — show recent query performance"
    if [[ "$INSTALL_RAG" == "true" ]]; then
        echo ""
        echo -e "  ${BOLD}Re-index after system updates:${R}"
        echo -e "  ${CY}tuxaide reindex${R}      — re-index all man pages"
        echo -e "  ${CY}tuxaide index nginx${R}  — index a specific command"
    fi
    echo ""
    echo -e "  ${BOLD}Uninstall:${R}  ${CY}tuxaide-uninstall${R}"
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
    install_dependencies
    install_ollama
    start_ollama
    download_models
    install_agent
    index_man_pages
    activate_shell
    final_check || true
    print_summary || true
}

main
