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

    # RAG dependencies
    if [[ "$INSTALL_RAG" == "true" ]]; then
        info "Installing RAG dependencies (chromadb, tiktoken)..."
        python3 -m pip install chromadb tiktoken --break-system-packages -q 2>/dev/null || \
        python3 -m pip install chromadb tiktoken -q 2>/dev/null || \
        pip3 install chromadb tiktoken -q 2>/dev/null || \
        warn "Could not install chromadb automatically. Run: pip install chromadb tiktoken"
        ok "RAG dependencies installed"
    fi
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
# STEP 6 — TuxAide Agent
# ═══════════════════════════════════════════════════════════════════════
install_agent() {
    step "Installing TuxAide agent"

    local BIN="${HOME}/.local/bin"
    local CFG="${HOME}/.config/tuxaide"
    mkdir -p "$BIN" "$CFG"

    # ── Main Python binary ─────────────────────────────────────────────
    cat > "${BIN}/tuxaide" << 'PYEOF'
#!/usr/bin/env python3
"""TuxAide v2.1 — Local AI assistant for Linux terminal with Smart RAG."""
import sys, os, re, json, hashlib, time, urllib.request, urllib.error
import textwrap, shutil, threading, itertools

CFG_FILE  = os.path.expanduser("~/.config/tuxaide/config.json")
CACHE_DIR = os.path.expanduser("~/.config/tuxaide/cache")
LOG_DIR   = os.path.expanduser("~/.config/tuxaide/logs")
PERF_LOG  = os.path.join(LOG_DIR, "perf.log")

DEFAULTS = {
    "ollama_url":   "http://localhost:11434",
    "model":        "qwen2.5-coder:7b",
    "embed_model":  "nomic-embed-text",
    "max_tokens":   300,
    "temperature":  0.1,
    "color":        True,
    "mode":         "llm",    # "llm", "smart", "deep"
    "rag_top_k":    1,
    "rag_db_path":  "~/.config/tuxaide/vectordb",
    "rag_timeout":  8,        # seconds before RAG fallback to LLM
}

def cfg():
    c = DEFAULTS.copy()
    try:
        with open(CFG_FILE) as f: c.update(json.load(f))
    except Exception: pass
    return c

def save_cfg(updates):
    c = cfg()
    c.update(updates)
    with open(CFG_FILE, 'w') as f: json.dump(c, f, indent=4)

class C:
    Z="\033[0m"; B="\033[1m"; D="\033[2m"
    G="\033[32m"; Y="\033[36m"; R="\033[33m"; O="\033[31m"; RD="\033[31m"

class Spinner:
    _frames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    def __init__(self, msg="Thinking"):
        self._msg = msg
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)
    def _run(self):
        for f in itertools.cycle(self._frames):
            if self._stop.is_set(): break
            sys.stderr.write(f"\r  {f}  {self._msg}...")
            sys.stderr.flush()
            time.sleep(0.09)
        sys.stderr.write("\r" + " " * (len(self._msg) + 10) + "\r")
        sys.stderr.flush()
    def start(self): self._t.start(); return self
    def stop(self):  self._stop.set(); self._t.join()

# ── Question detection ────────────────────────────────────────────────
KW_PT = ['como faço','como usar','como instalar','como ver','como listar',
         'como apagar','como criar','como mover','como copiar','como mudar',
         'como configurar','como saber','como se','para que','para quê',
         'como','porquê','por que','porque','o que','qual','quais',
         'quanto','quando','onde','quem','significa','consigo','posso',
         'possível','me diz','explica','mostra','diferença']
KW_EN = ['how to','how do','how can','how does','what is','what are',
         'what does',"what's",'can i','tell me','show me',
         'how','why','what','where','when','which','who','explain','difference']
KW_ES = ['cómo','qué','cuál','cuáles','dónde','cuándo','por qué','puedo']
KW_FR = ['comment','pourquoi','quel','quelle','où','quand','expliquez']
KW_DE = ['wie','warum','was','welche','welcher','erkläre','zeige']

CMDS = {'ls','cd','pwd','mkdir','rm','cp','mv','cat','echo','grep','find',
        'chmod','chown','sudo','apt','apt-get','yum','dnf','pip','python',
        'python3','bash','sh','zsh','git','docker','systemctl','journalctl',
        'ps','top','htop','kill','killall','ssh','scp','curl','wget','tar',
        'zip','unzip','nano','vim','vi','less','more','head','tail','sort',
        'uniq','wc','awk','sed','cut','diff','patch','make','man','which',
        'whereis','type','alias','export','env','set','history','clear',
        'reset','exit','logout','reboot','shutdown','mount','umount','df',
        'du','free','uname','hostname','ifconfig','ip','ping','netstat',
        'ss','lsof','file','stat','touch','ln','date','uptime','who','id',
        'crontab','screen','tmux','xargs','tee','tr','rsync','nc','iptables',
        'ufw','service','snap','flatpak','node','npm','npx','yarn','go',
        'ruby','perl','php','source','ollama','tuxaide','tux','lg',
        'nginx','apache2','mysql','postgresql','redis','useradd','userdel',
        'passwd','groupadd','fdisk','lsblk','mkfs','fsck','strace','nmap',
        'dig','nslookup','blkid','vmstat','iostat','sar'}

# Keywords that signal the question needs local documentation
RAG_KEYWORDS = {
    'options','flags','man','error','configure','setup','my system',
    'opções','flags','man','erro','configurar','neste sistema',
    'options','indicateurs','erreur','configurer','mon système',
    'optionen','fehler','konfigurieren','mein system',
}

# Destructive command patterns — shown with a warning
DESTRUCTIVE_PATTERNS = [
    r'\brm\s+-[^\s]*r',        # rm -r, rm -rf, rm -Rf
    r'\brm\s+-[^\s]*f',        # rm -f
    r'\bdd\b',                  # dd
    r'\bmkfs\b',                # mkfs.*
    r'\bfdisk\b',               # fdisk
    r'\bparted\b',              # parted
    r'\bshred\b',               # shred
    r'\bwipefs\b',              # wipefs
    r'>\s*/dev/',               # redirect to /dev/
    r'\bchmod\s+777\b',         # chmod 777
    r'\bsudo\s+rm\b',           # sudo rm
    r'DROP\s+TABLE',            # SQL DROP TABLE
    r'DROP\s+DATABASE',         # SQL DROP DATABASE
    r':\(\)\s*\{.*\}',          # fork bomb
    r'\bkillall\b',             # killall
]

def is_q(text):
    t = text.strip().lower()
    if len(t) < 4: return False
    if t.split()[0] in CMDS: return False
    if '|' in t or '>' in t or t.startswith('-'): return False
    for kw in KW_PT + KW_EN + KW_ES + KW_FR + KW_DE:
        if re.search(r'\b' + re.escape(kw) + r'\b', t, re.I):
            return True
    return t.endswith('?')

def detect_lang(text):
    t = text.lower()
    checks = [
        ("European Portuguese", ['como','porque','porquê','qual','onde','quando','quem','posso']),
        ("Spanish",             ['cómo','qué','cuál','dónde','cuándo','puedo']),
        ("French",              ['comment','pourquoi','quel','quelle','où','quand']),
        ("German",              ['wie','warum','was','welche','können']),
    ]
    for lang, kws in checks:
        for kw in kws:
            if re.search(r'\b' + kw + r'\b', t): return lang
    return "English"

# ── Normalisation & cache ─────────────────────────────────────────────
def normalize(q):
    """Normalise question for cache key: lowercase, strip, collapse spaces, remove trailing punctuation."""
    q = q.lower().strip()
    q = re.sub(r"[?!.]+$", "", q)
    q = re.sub(r"\s+", " ", q)
    return q

def cache_key(text):
    return hashlib.md5(text.encode()).hexdigest()

def cache_get(kind, key):
    """kind: 'answers' or 'embeddings'"""
    path = os.path.join(CACHE_DIR, kind, key + ".json")
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None

def cache_set(kind, key, value):
    d = os.path.join(CACHE_DIR, kind)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, key + ".json")
    try:
        with open(path, "w") as f:
            json.dump(value, f)
    except Exception:
        pass

# ── Performance log ───────────────────────────────────────────────────
def perf_log(question, mode, t_embed, t_rag, t_llm, cache_hit):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        total = t_embed + t_rag + t_llm
        ts = time.strftime("%Y-%m-%dT%H:%M:%S")
        line = (f"{ts}\t{mode}\t"
                f"embed={t_embed:.2f}s\trag={t_rag:.2f}s\t"
                f"llm={t_llm:.2f}s\ttotal={total:.2f}s\t"
                f"cache={'hit' if cache_hit else 'miss'}\t"
                f"q={question[:80].replace(chr(9),' ')}\n")
        with open(PERF_LOG, "a") as f:
            f.write(line)
    except Exception:
        pass

# ── Smart router ──────────────────────────────────────────────────────
def detect_command(question):
    """Return the primary Linux command mentioned in the question, or None."""
    t = question.lower()
    for cmd in sorted(CMDS, key=len, reverse=True):  # longest first to avoid partial matches
        if re.search(r'\b' + re.escape(cmd) + r'\b', t):
            return cmd
    return None

def should_use_rag(question):
    """Return True if the question likely needs local man page documentation."""
    t = question.lower()
    # Explicit RAG keywords
    for kw in RAG_KEYWORDS:
        if kw in t:
            return True
    # Mentions a specific command → probably needs docs
    if detect_command(question):
        return True
    return False

# ── RAG functions ─────────────────────────────────────────────────────
def rag_available():
    try:
        import chromadb
        return True
    except ImportError:
        return False

def embed(text, model, url):
    """Generate embedding with disk cache."""
    key = cache_key(f"{model}:{text}")
    cached = cache_get("embeddings", key)
    if cached is not None:
        return cached
    req = urllib.request.Request(
        f"{url}/api/embeddings",
        data=json.dumps({"model": model, "prompt": text}).encode(),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        vec = json.loads(r.read())["embedding"]
    cache_set("embeddings", key, vec)
    return vec

def retrieve(question, c, detected_cmd=None):
    """Retrieve top-K passages. Filter by command if detected."""
    try:
        import chromadb
        db_path = os.path.expanduser(c.get("rag_db_path", "~/.config/tuxaide/vectordb"))
        if not os.path.exists(db_path):
            return []
        client = chromadb.PersistentClient(path=db_path)
        try:
            col = client.get_collection("tuxaide_manpages")
        except Exception:
            return []
        q_embed = embed(question, c.get("embed_model", "nomic-embed-text"), c["ollama_url"])
        top_k = c.get("rag_top_k", 1)
        # Filter by command if detected — much faster and less noisy
        if detected_cmd:
            try:
                results = col.query(
                    query_embeddings=[q_embed],
                    n_results=top_k,
                    where={"command": detected_cmd}
                )
            except Exception:
                # Fallback to global search if command not in DB
                results = col.query(query_embeddings=[q_embed], n_results=top_k)
        else:
            results = col.query(query_embeddings=[q_embed], n_results=top_k)
        passages = []
        for doc, meta in zip(results["documents"][0], results["metadatas"][0]):
            source = meta.get("source", "man page")
            passages.append({"text": doc, "source": source})
        return passages
    except Exception:
        return []

# ── Destructive command check ─────────────────────────────────────────
def is_destructive(text):
    """Return True if the text contains a potentially destructive command."""
    for pattern in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False

# ── Prompt builders ───────────────────────────────────────────────────
def build_prompt(lang, passages=None):
    NL = chr(10)
    base = (
        "You are TuxAide, an assistant specialised EXCLUSIVELY in Linux and Unix systems." + NL +
        "You REFUSE to answer anything unrelated to Linux, terminal, shell, "
        "system administration, networking, commands, scripts, or Unix/Linux tools. "
        "If the question is NOT about Linux/Unix/terminal, reply with ONE short sentence "
        "only, saying you are a Linux specialist. Do not explain or apologise." + NL +
        f"MANDATORY LANGUAGE RULE: You MUST reply entirely in {lang}. "
        f"Every single word must be in {lang}. This rule overrides everything else." + NL
    )
    if passages:
        context = "\n\n".join(
            f"[Source: {p['source']}]\n{p['text']}" for p in passages
        )
        base += (
            "Use the following excerpts from this system's man pages as your PRIMARY source. "
            "Base your answer ONLY on these excerpts — do not add information not present in them. "
            "MANDATORY: The LAST line of your answer MUST be exactly: "
            "'Source: ' followed by the man page name (e.g. Source: man ls(1)). "
            "Never skip the source citation." + NL +
            "Man page excerpts:" + NL + context + NL
        )
    base += (
        "Answer rules: Be direct — no long introductions, do not repeat the question. "
        "Always show ready-to-use command examples in code blocks. "
        "If a command differs by distro (Ubuntu vs Arch vs Fedora), say so. "
        "Maximum 3 paragraphs. Be concise."
    )
    return base

# ── Ollama query ──────────────────────────────────────────────────────
def ask_ollama(q, c, passages=None):
    lang = detect_lang(q)
    pay = {
        "model": c["model"],
        "messages": [
            {"role": "system", "content": build_prompt(lang, passages)},
            {"role": "user",   "content": q + (
                "\n\n[Important: end your answer with exactly: Source: <man page name>]"
                if passages else ""
            )}
        ],
        "options": {"temperature": c.get("temperature", 0.1),
                    "num_predict": c.get("max_tokens", 300),
                    "num_gpu": c.get("num_gpu", 99)},
        "stream": True
    }
    req = urllib.request.Request(
        f"{c['ollama_url']}/api/chat",
        data=json.dumps(pay).encode(),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    out = []
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            for ln in r:
                ln = ln.strip()
                if not ln: continue
                try: out.append(json.loads(ln).get("message",{}).get("content",""))
                except Exception: pass
    except urllib.error.URLError:
        return "[Error] Ollama not available. Try: sudo systemctl start ollama"
    except Exception as e:
        return f"[Error] {e}"
    return "".join(out).strip()

# ── Formatting ────────────────────────────────────────────────────────
def fmt(text, c, mode="llm", destructive=False):
    cols  = shutil.get_terminal_size((80,24)).columns
    color = c.get("color", True)
    mode_label = f" · Smart RAG" if mode == "smart" else (" · RAG" if mode == "deep" else "")
    top = (f"{C.Y}{C.B}╭{'─'*(cols-2)}╮{C.Z}" if color else f"┌{'─'*(cols-2)}┐")
    bot = (f"{C.Y}{C.B}╰{'─'*(cols-2)}╯{C.Z}" if color else f"└{'─'*(cols-2)}┘")
    lbl = (f"{C.Y}{C.B}╞═ 🐧 TuxAide {C.D}(Ollama · {c['model']}{mode_label}){C.Z}{C.Y}{C.B} ═╡{C.Z}"
           if color else f"╞═ TuxAide ═╡")
    out = ["", top, lbl]
    # Destructive warning — shown before any code block
    if destructive:
        warn_line = (
            f"  {C.RD}{C.B}⚠  WARNING: This command is destructive and irreversible."
            f" Verify carefully before running.{C.Z}"
            if color else
            "  ⚠  WARNING: This command is destructive and irreversible. Verify carefully before running."
        )
        out.append("")
        out.append(warn_line)
    in_code = False
    for line in text.split('\n'):
        if line.startswith('```'):
            in_code = not in_code
            lang = line[3:].strip() or "shell"
            out.append(f"  {C.D}┄ {lang} ┄{C.Z}" if color else f"  ┄ {lang} ┄")
            continue
        if in_code:
            out.append(f"  {C.G}{line}{C.Z}" if color else f"  {line}")
            continue
        if not line.strip():
            out.append(""); continue
        if color:
            line = re.sub(r'\*\*(.+?)\*\*', f'{C.B}\\1{C.Z}', line)
            line = re.sub(r'`([^`]+)`', f'{C.G}\\1{C.Z}', line)
        for w in textwrap.wrap(line, width=cols-4+20, break_long_words=False):
            out.append(f"  {w}")
    out += [bot, ""]
    return "\n".join(out)

def ollama_ok(c):
    try:
        with urllib.request.urlopen(
            urllib.request.Request(f"{c['ollama_url']}/api/tags"), timeout=3) as r:
            return r.status == 200
    except Exception: return False

# ── CLI ───────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2: sys.exit(0)
    mode_arg = sys.argv[1]

    # --check: is this a question?
    if mode_arg == "--check":
        sys.exit(0 if is_q(" ".join(sys.argv[2:])) else 1)

    # mode: switch between llm, smart, deep (rag kept as alias for deep)
    if mode_arg == "mode":
        if len(sys.argv) < 3:
            c = cfg()
            print(f"🐧 TuxAide mode: {c.get('mode','llm').upper()}")
            return
        new_mode = sys.argv[2].lower()
        if new_mode == "rag": new_mode = "deep"  # backwards compat
        if new_mode not in ("llm", "smart", "deep"):
            print("Usage: tuxaide mode [llm|smart|deep]"); return
        if new_mode in ("smart", "deep") and not rag_available():
            print(f"{C.O}⚠ RAG requires chromadb: pip install chromadb{C.Z}"); return
        top_k = 1 if new_mode == "smart" else 3
        max_tokens = 300 if new_mode in ("llm", "smart") else 600
        save_cfg({"mode": new_mode, "rag_top_k": top_k, "max_tokens": max_tokens})
        print(f"🐧 TuxAide mode switched to: {new_mode.upper()}")
        return

    # index: index a specific man page
    if mode_arg == "index":
        cmd = sys.argv[2] if len(sys.argv) > 2 else None
        if not cmd:
            print("Usage: tuxaide index <command>  (e.g. tuxaide index nginx)")
            return
        print(f"🐧 Indexing man page for: {cmd}")
        os.system(f"tuxaide-index {cmd}")
        return

    # reindex: re-index all man pages
    if mode_arg == "reindex":
        print("🐧 Re-indexing all man pages...")
        os.system("tuxaide-index --all")
        return

    # timing: show last N lines of perf log
    if mode_arg == "--timing":
        try:
            with open(PERF_LOG) as f:
                lines = f.readlines()
            print(f"\n🐧 TuxAide — last {min(10,len(lines))} queries:\n")
            for line in lines[-10:]:
                print(" ", line.rstrip())
            print()
        except FileNotFoundError:
            print("No performance log yet. Ask a question first.")
        return

    # ask
    q = " ".join(sys.argv[2:] if mode_arg == "--ask" else sys.argv[1:])
    if mode_arg != "--ask" and not is_q(q): sys.exit(0)

    c = cfg()
    if not ollama_ok(c):
        print(f"\n{C.O}⚠ Ollama not available.{C.Z}")
        print(f"{C.D}  Try: sudo systemctl start ollama{C.Z}\n")
        sys.exit(0)

    norm_q    = normalize(q)
    ans_key   = cache_key(norm_q)
    t_embed   = 0.0
    t_rag     = 0.0
    t_llm     = 0.0
    cache_hit = False

    # ── Answer cache lookup ───────────────────────────────────────────
    cached_answer = cache_get("answers", ans_key)
    if cached_answer:
        cache_hit = True
        answer    = cached_answer["answer"]
        act_mode  = cached_answer.get("mode", "llm")
        perf_log(norm_q, act_mode + "+cache", 0, 0, 0, True)
        print(fmt(answer, c, act_mode, is_destructive(answer)))
        return

    # ── Determine mode and whether to use RAG ────────────────────────
    current_mode = c.get("mode", "llm")
    passages     = []
    detected_cmd = None
    act_mode     = "llm"

    spinner = Spinner().start()

    if current_mode == "smart" and rag_available():
        if should_use_rag(norm_q):
            detected_cmd = detect_command(norm_q)
            t0 = time.time()
            try:
                # Respect RAG timeout — fall back to LLM if too slow
                import signal
                def _timeout(signum, frame): raise TimeoutError()
                signal.signal(signal.SIGALRM, _timeout)
                signal.alarm(c.get("rag_timeout", 8))
                t_embed_start = time.time()
                passages = retrieve(norm_q, c, detected_cmd)
                t_embed = time.time() - t_embed_start
                signal.alarm(0)
            except (TimeoutError, Exception):
                signal.alarm(0)
                passages = []
            t_rag = time.time() - t0 - t_embed
            if passages:
                act_mode = "smart"

    elif current_mode == "deep" and rag_available():
        detected_cmd = detect_command(norm_q)
        t0 = time.time()
        t_embed_start = time.time()
        passages = retrieve(norm_q, c, detected_cmd)
        t_embed = time.time() - t_embed_start
        t_rag = time.time() - t0 - t_embed
        if passages:
            act_mode = "deep"

    # ── LLM call ──────────────────────────────────────────────────────
    t_llm_start = time.time()
    answer = ask_ollama(q, c, passages if passages else None)
    t_llm = time.time() - t_llm_start

    spinner.stop()

    # ── Cache the answer ──────────────────────────────────────────────
    cache_set("answers", ans_key, {"answer": answer, "mode": act_mode})

    # ── Perf log ──────────────────────────────────────────────────────
    perf_log(norm_q, act_mode, t_embed, t_rag, t_llm, False)

    # ── Output ────────────────────────────────────────────────────────
    print(fmt(answer, c, act_mode, is_destructive(answer)))

if __name__ == "__main__": main()
PYEOF
    chmod +x "${BIN}/tuxaide"
    ok "Binary installed → ${BIN}/tuxaide"

    # ── Config ─────────────────────────────────────────────────────────
    local mode_val="llm"
    [[ "$INSTALL_RAG" == "true" ]] && mode_val="smart"

    cat > "${CFG}/config.json" << JEOF
{
    "ollama_url": "http://localhost:11434",
    "model": "${MODEL}",
    "embed_model": "nomic-embed-text",
    "max_tokens": 300,
    "temperature": 0.1,
    "color": true,
    "mode": "${mode_val}",
    "rag_top_k": 1,
    "rag_timeout": 8,
    "rag_db_path": "~/.config/tuxaide/vectordb"
}
JEOF
    ok "Config → ${CFG}/config.json  (mode: ${mode_val})"

    # ── Man page indexer script ────────────────────────────────────────
    if [[ "$INSTALL_RAG" == "true" ]]; then
        cat > "${BIN}/tuxaide-index" << 'IDXEOF'
#!/usr/bin/env python3
"""TuxAide — Man page indexer for Smart RAG mode."""
import os, sys, json, re, subprocess, urllib.request

try:
    import chromadb
except ImportError:
    print("Error: chromadb not installed. Run: pip install chromadb")
    sys.exit(1)

CFG_FILE = os.path.expanduser("~/.config/tuxaide/config.json")
DB_PATH  = os.path.expanduser("~/.config/tuxaide/vectordb")

# Top 100 most useful man pages for Linux beginners
TOP_COMMANDS = [
    "ls","cd","pwd","mkdir","rm","cp","mv","cat","less","more","head","tail",
    "grep","find","chmod","chown","ln","touch","stat","file","which","whereis",
    "echo","printf","read","test","expr","sort","uniq","wc","cut","tr","sed",
    "awk","diff","patch","tar","gzip","zip","unzip","curl","wget","ssh","scp",
    "rsync","ping","ip","ss","netstat","ifconfig","nmap","dig","host","nslookup",
    "ps","top","htop","kill","killall","nice","nohup","jobs","bg","fg","wait",
    "systemctl","journalctl","service","cron","at","watch","sleep","date","cal",
    "uname","hostname","uptime","who","w","last","id","whoami","su","sudo",
    "useradd","userdel","passwd","groupadd","groups","chmod","umask","ulimit",
    "df","du","mount","umount","fdisk","lsblk","blkid","mkfs","fsck","lsof",
    "free","vmstat","iostat","mpstat","sar","strace","ltrace","ldd","nm",
    "git","make","gcc","python3","pip","vim","nano","tmux","screen","man","info",
    "apt","apt-get","dpkg","yum","dnf","pacman","snap","flatpak","docker",
    "nginx","apache2","mysql","postgresql","redis","crontab","env","export",
    "set","alias","history","source","bash","sh","awk","xargs","tee","tty"
]

def load_config():
    try:
        with open(CFG_FILE) as f: return json.load(f)
    except Exception:
        return {"ollama_url": "http://localhost:11434", "embed_model": "nomic-embed-text"}

def get_man_text(cmd):
    """Extract plain text from a man page."""
    try:
        result = subprocess.run(
            ["man", cmd], capture_output=True, text=True,
            env={**os.environ, "MANPAGER": "cat", "COLUMNS": "80"}
        )
        if result.returncode != 0:
            return None
        text = result.stdout
        text = re.sub(r'.\x08', '', text)
        text = re.sub(r'\x1b\[[0-9;]*m', '', text)
        text = re.sub(r'\n{3,}', '\n\n', text)
        return text.strip() if len(text.strip()) > 100 else None
    except Exception:
        return None

def chunk_text(text, cmd, chunk_size=200, overlap=40):
    """Split text into overlapping chunks (smaller = faster retrieval)."""
    words = text.split()
    chunks = []
    i = 0
    while i < len(words):
        chunk_words = words[i:i+chunk_size]
        chunks.append({
            "text": " ".join(chunk_words),
            "source": f"man {cmd}(1)",
            "command": cmd,
            "chunk_idx": len(chunks)
        })
        i += chunk_size - overlap
    return chunks

def embed_text(text, model, url):
    req = urllib.request.Request(
        f"{url}/api/embeddings",
        data=json.dumps({"model": model, "prompt": text}).encode(),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())["embedding"]

def index_command(cmd, col, cfg, verbose=True):
    text = get_man_text(cmd)
    if not text:
        if verbose: print(f"  ⚠  No man page: {cmd}")
        return 0
    chunks = chunk_text(text, cmd)
    for i, chunk in enumerate(chunks):
        chunk_id = f"{cmd}_{i}"
        try:
            existing = col.get(ids=[chunk_id])
            if existing["ids"]: continue
        except Exception: pass
        try:
            vec = embed_text(chunk["text"], cfg.get("embed_model","nomic-embed-text"),
                            cfg.get("ollama_url","http://localhost:11434"))
            col.add(
                ids=[chunk_id],
                embeddings=[vec],
                documents=[chunk["text"]],
                metadatas=[{"source": chunk["source"], "command": cmd, "chunk": i}]
            )
        except Exception as e:
            if verbose: print(f"  ✗ Error embedding {cmd}: {e}")
    if verbose: print(f"  ✓  {cmd} ({len(chunks)} chunks)")
    return len(chunks)

def main():
    cfg = load_config()
    os.makedirs(DB_PATH, exist_ok=True)
    client = chromadb.PersistentClient(path=DB_PATH)
    col    = client.get_or_create_collection(
        "tuxaide_manpages",
        metadata={"hnsw:space": "cosine"}
    )

    if len(sys.argv) > 1 and sys.argv[1] != "--all":
        cmd = sys.argv[1]
        print(f"🐧 Indexing: {cmd}")
        n = index_command(cmd, col, cfg)
        print(f"   Done — {n} chunks indexed")
        return

    print(f"🐧 Indexing {len(TOP_COMMANDS)} man pages...")
    print(f"   Database: {DB_PATH}")
    print()
    total = 0
    for cmd in TOP_COMMANDS:
        n = index_command(cmd, col, cfg)
        total += n
    print()
    print(f"✓ Indexing complete — {total} total chunks stored")
    print(f"  Run 'tuxaide mode smart' to activate Smart RAG mode")

if __name__ == "__main__": main()
IDXEOF
        chmod +x "${BIN}/tuxaide-index"
        ok "Indexer installed → ${BIN}/tuxaide-index"
    fi

    # ── Shell hook ─────────────────────────────────────────────────────
    cat > "${CFG}/hook.sh" << 'HOOKEOF'
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
HOOKEOF
    ok "Hook installed → ${CFG}/hook.sh"

    # ── Uninstaller ────────────────────────────────────────────────────
    cat > "${BIN}/tuxaide-uninstall" << 'UEOF'
#!/usr/bin/env bash
R="\033[0m"; GR="\033[32m"; RD="\033[31m"; YL="\033[33m"; BOLD="\033[1m"
echo ""
echo -e "${RD}${BOLD}  🐧  TuxAide — Uninstall${R}"
echo ""
read -rp "  Are you sure? This removes TuxAide completely. [y/N] " a
[[ "$a" =~ ^[yYsS]$ ]] || { echo "  Cancelled."; exit 0; }
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    [[ -f "$rc" ]] || continue
    grep -v "TuxAide" "$rc" > /tmp/_tux_rc && mv /tmp/_tux_rc "$rc"
    echo -e "  ${GR}✓${R} Removed from $rc"
done
rm -f ~/.local/bin/tuxaide ~/.local/bin/tuxaide-index ~/.local/bin/tuxaide-uninstall
rm -rf ~/.config/tuxaide
echo -e "  ${GR}✓${R} Files removed"
echo ""
echo -e "  ${YL}Note: Ollama and models were NOT removed.${R}"
echo -e "  ${YL}To remove: sudo systemctl stop ollama && sudo rm \$(which ollama)${R}"
echo ""
echo -e "  ${GR}${BOLD}Done. Restart your terminal.${R}"
echo ""
UEOF
    chmod +x "${BIN}/tuxaide-uninstall"
    ok "Uninstaller → ${BIN}/tuxaide-uninstall"
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

    if python3 "${HOME}/.local/bin/tuxaide-index" --all; then
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
        _chk "ChromaDB installed"     "python3 -c 'import chromadb'"
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
