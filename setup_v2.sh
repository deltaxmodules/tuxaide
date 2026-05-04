#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
#  TuxAide v2 — Complete Installer with RAG
#  https://github.com/deltaxmodules/tuxaide
#
#  One-liner install:
#    curl -fsSL https://raw.githubusercontent.com/deltaxmodules/tuxaide/main/setup_v2.sh | bash
#
#  What it does:
#    1.  Detects distro, architecture, RAM and GPU
#    2.  Shows system diagnosis and asks for confirmation
#    3.  Installs all v1 components (Ollama, model, shell hook)
#    4.  Asks if user wants RAG mode (man page knowledge base)
#    5.  If yes: installs ChromaDB, embedding model, indexes man pages
#    6.  Activates immediately — no terminal restart needed
#
#  To disable RAG:   tuxaide mode llm
#  To re-enable RAG: tuxaide mode rag
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
    echo -e "${CY}${BOLD}║   🐧  TuxAide v2 — Complete Installer               ║${R}"
    echo -e "${CY}${BOLD}║   Local AI assistant with RAG knowledge base        ║${R}"
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
        echo -e "  ${CY}│${R}  ${GR}✓${R} TuxAide v2 (RAG mode)    ${GR}AVAILABLE${R}                ${CY}│${R}"
        RAG_AVAILABLE=true
    else
        if [[ "$RAG_CAPABLE" == "false" ]]; then
            echo -e "  ${CY}│${R}  ${YL}⚠${R} TuxAide v2 (RAG mode)    ${YL}RAM < 5 GB — not recommended${R} ${CY}│${R}"
        else
            echo -e "  ${CY}│${R}  ${YL}⚠${R} TuxAide v2 (RAG mode)    ${YL}DISK SPACE LOW${R}           ${CY}│${R}"
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
    read -r CONFIRM
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
    echo -e "  ${BOLD}What is RAG mode?${R}"
    echo -e "  TuxAide v2 can index the man pages installed on this system"
    echo -e "  and use them as a knowledge base. This means:"
    echo ""
    echo -e "  ${GR}✓${R}  Answers based on the documentation of THIS system"
    echo -e "  ${GR}✓${R}  Drastically reduced hallucinations"
    echo -e "  ${GR}✓${R}  Responses cite the source: man page + section"
    echo -e "  ${GR}✓${R}  Specific to your installed software versions"
    echo ""
    echo -e "  ${DIM}Extra requirements: ~300 MB RAM + ~10 min indexing (one-time)${R}"
    echo -e "  ${DIM}If skipped now, you can enable later with: tuxaide mode rag${R}"
    echo ""

    if [[ "$RAG_AVAILABLE" == "false" ]]; then
        warn "RAG mode is not recommended for this system (insufficient RAM or disk)."
        warn "Installing in LLM-only mode (v1 behaviour)."
        INSTALL_RAG=false
        return
    fi

    ask "Install RAG mode? (recommended) [Y/n] "
    read -r RAG_CONFIRM
    RAG_CONFIRM="${RAG_CONFIRM:-y}"
    if [[ "$RAG_CONFIRM" =~ ^[yYsS]$ ]]; then
        INSTALL_RAG=true
        ok "RAG mode will be installed"
    else
        INSTALL_RAG=false
        info "Skipping RAG — installing LLM mode only (v1 behaviour)"
        info "Enable later with: tuxaide mode rag"
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
"""TuxAide v2 — Local AI assistant for Linux terminal with optional RAG."""
import sys, os, re, json, urllib.request, urllib.error, textwrap, shutil

CFG_FILE = os.path.expanduser("~/.config/tuxaide/config.json")
DEFAULTS = {
    "ollama_url": "http://localhost:11434",
    "model": "qwen2.5-coder:7b",
    "embed_model": "nomic-embed-text",
    "max_tokens": 600,
    "temperature": 0.1,
    "color": True,
    "mode": "llm",           # "llm" or "rag"
    "rag_top_k": 3,          # number of passages to retrieve
    "rag_db_path": "~/.config/tuxaide/vectordb",
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
    G="\033[32m"; Y="\033[36m"; R="\033[33m"; O="\033[31m"

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
        'ruby','perl','php','source','ollama','tuxaide','tux','lg'}

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

# ── RAG functions ─────────────────────────────────────────────────────
def rag_available():
    try:
        import chromadb
        return True
    except ImportError:
        return False

def embed(text, model, url):
    req = urllib.request.Request(
        f"{url}/api/embeddings",
        data=json.dumps({"model": model, "prompt": text}).encode(),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())["embedding"]

def retrieve(question, c):
    """Retrieve top-K relevant passages from man page vector database."""
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
        results = col.query(query_embeddings=[q_embed], n_results=c.get("rag_top_k", 3))
        passages = []
        for doc, meta in zip(results["documents"][0], results["metadatas"][0]):
            source = meta.get("source", "man page")
            passages.append({"text": doc, "source": source})
        return passages
    except Exception:
        return []

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
            "Base your answer on these excerpts. "
            "At the end of your answer, cite the source (e.g. 'Source: man ls(1)')." + NL +
            "Man page excerpts:" + NL + context + NL
        )
    base += (
        "Answer rules: Be direct — no long introductions, do not repeat the question. "
        "Always show ready-to-use command examples in code blocks. "
        "If a command differs by distro (Ubuntu vs Arch vs Fedora), say so. "
        "Maximum 4 paragraphs. Warn clearly if a command is dangerous (e.g. rm -rf)."
    )
    return base

# ── Ollama query ──────────────────────────────────────────────────────
def ask_ollama(q, c, passages=None):
    lang = detect_lang(q)
    pay = {
        "model": c["model"],
        "messages": [
            {"role": "system", "content": build_prompt(lang, passages)},
            {"role": "user",   "content": q}
        ],
        "options": {"temperature": c.get("temperature", 0.1),
                    "num_predict": c.get("max_tokens", 600)},
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
def fmt(text, c, mode="llm"):
    cols  = shutil.get_terminal_size((80,24)).columns
    color = c.get("color", True)
    mode_label = f" · RAG" if mode == "rag" else ""
    top = (f"{C.Y}{C.B}╭{'─'*(cols-2)}╮{C.Z}" if color else f"┌{'─'*(cols-2)}┐")
    bot = (f"{C.Y}{C.B}╰{'─'*(cols-2)}╯{C.Z}" if color else f"└{'─'*(cols-2)}┘")
    lbl = (f"{C.Y}{C.B}╞═ 🐧 TuxAide {C.D}(Ollama · {c['model']}{mode_label}){C.Z}{C.Y}{C.B} ═╡{C.Z}"
           if color else f"╞═ TuxAide ═╡")
    out = ["", top, lbl]
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

    # mode: switch between llm and rag
    if mode_arg == "mode":
        if len(sys.argv) < 3:
            c = cfg()
            print(f"🐧 TuxAide mode: {c.get('mode','llm').upper()}")
            return
        new_mode = sys.argv[2].lower()
        if new_mode not in ("llm", "rag"):
            print("Usage: tuxaide mode [llm|rag]"); return
        if new_mode == "rag" and not rag_available():
            print(f"{C.O}⚠ RAG requires chromadb: pip install chromadb{C.Z}"); return
        save_cfg({"mode": new_mode})
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

    # ask
    q = " ".join(sys.argv[2:] if mode_arg == "--ask" else sys.argv[1:])
    if mode_arg != "--ask" and not is_q(q): sys.exit(0)

    c = cfg()
    if not ollama_ok(c):
        print(f"\n{C.O}⚠ Ollama not available.{C.Z}")
        print(f"{C.D}  Try: sudo systemctl start ollama{C.Z}\n")
        sys.exit(0)

    # RAG or LLM
    current_mode = c.get("mode", "llm")
    passages = []
    if current_mode == "rag" and rag_available():
        passages = retrieve(q, c)

    answer = ask_ollama(q, c, passages if passages else None)
    actual_mode = "rag" if passages else "llm"
    print(fmt(answer, c, actual_mode))

if __name__ == "__main__": main()
PYEOF
    chmod +x "${BIN}/tuxaide"
    ok "Binary installed → ${BIN}/tuxaide"

    # ── Config ─────────────────────────────────────────────────────────
    local mode_val="llm"
    [[ "$INSTALL_RAG" == "true" ]] && mode_val="rag"

    cat > "${CFG}/config.json" << JEOF
{
    "ollama_url": "http://localhost:11434",
    "model": "${MODEL}",
    "embed_model": "nomic-embed-text",
    "max_tokens": 600,
    "temperature": 0.1,
    "color": true,
    "mode": "${mode_val}",
    "rag_top_k": 3,
    "rag_db_path": "~/.config/tuxaide/vectordb"
}
JEOF
    ok "Config → ${CFG}/config.json  (mode: ${mode_val})"

    # ── Man page indexer script ────────────────────────────────────────
    if [[ "$INSTALL_RAG" == "true" ]]; then
        cat > "${BIN}/tuxaide-index" << 'IDXEOF'
#!/usr/bin/env python3
"""TuxAide — Man page indexer for RAG mode."""
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
        # Remove backspace formatting (bold/underline in man pages)
        text = re.sub(r'.\x08', '', text)
        text = re.sub(r'\x1b\[[0-9;]*m', '', text)
        text = re.sub(r'\n{3,}', '\n\n', text)
        return text.strip() if len(text.strip()) > 100 else None
    except Exception:
        return None

def chunk_text(text, cmd, chunk_size=400, overlap=80):
    """Split text into overlapping chunks."""
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
        # Check if already indexed
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
        # Index a specific command
        cmd = sys.argv[1]
        print(f"🐧 Indexing: {cmd}")
        n = index_command(cmd, col, cfg)
        print(f"   Done — {n} chunks indexed")
        return

    # Index all top commands
    print(f"🐧 Indexing {len(TOP_COMMANDS)} man pages...")
    print(f"   Database: {DB_PATH}")
    print()
    total = 0
    for cmd in TOP_COMMANDS:
        n = index_command(cmd, col, cfg)
        total += n
    print()
    print(f"✓ Indexing complete — {total} total chunks stored")
    print(f"  Run 'tuxaide mode rag' to activate RAG mode")

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
        echo "🐧 TuxAide v2"
        echo "   tuxaide <question>       — ask a question"
        echo "   tuxaide on / off         — enable / disable hook"
        echo "   tuxaide status           — show status and mode"
        echo "   tuxaide mode [llm|rag]   — switch knowledge mode"
        echo "   tuxaide model <name>     — change Ollama model"
        echo "   tuxaide index <cmd>      — index a man page"
        echo "   tuxaide reindex          — re-index all man pages"
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
        mode|index|reindex) "$_LG" "$@" ;;
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
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _lg_preexec() {
        local cmd="$1"
        "$_LG" --check "$cmd" 2>/dev/null && "$_LG" --ask "$cmd"
    }
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _lg_preexec 2>/dev/null
fi
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

    step "Indexing man pages (RAG knowledge base)"

    info "This runs once and takes approximately 5-10 minutes."
    info "Indexing the top 100 most useful Linux commands..."
    echo ""

    if python3 "${HOME}/.local/bin/tuxaide-index" --all; then
        ok "Man pages indexed successfully"
    else
        warn "Indexing failed — RAG mode will fallback to LLM automatically"
        # Switch to llm mode in config
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
    [[ "$INSTALL_RAG" == "true" ]] && mode_label="RAG + LLM (man page knowledge base)"

    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🐧  TuxAide v2 installed and ready!               ║${R}"
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
    echo -e "  ${CY}tuxaide mode rag${R}   — use man page knowledge base"
    echo -e "  ${CY}tuxaide mode llm${R}   — use general LLM only"
    echo -e "  ${CY}tuxaide status${R}     — show current mode"
    if [[ "$INSTALL_RAG" == "true" ]]; then
        echo ""
        echo -e "  ${BOLD}Re-index after system updates:${R}"
        echo -e "  ${CY}tuxaide reindex${R}   — re-index all man pages"
        echo -e "  ${CY}tuxaide index nginx${R} — index a specific command"
    fi
    echo ""
    echo -e "  ${BOLD}Uninstall:${R}  ${CY}tuxaide-uninstall${R}"
    echo ""
    echo -e "  ${DIM}Config: ~/.config/tuxaide/config.json${R}"
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
