#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
#  LinuxGenie — Complete Installer
#  https://github.com/deltaxmodules/linuxgenie
#
#  One-liner install:
#    curl -fsSL https://raw.githubusercontent.com/deltaxmodules/linuxgenie/main/setup.sh | bash
#
#  What it does:
#    1. Detects distro, architecture and RAM
#    2. Installs dependencies (python3, curl, unzip)
#    3. Installs Ollama (if not present)
#    4. Registers Ollama as a systemd service (starts on boot)
#    5. Downloads the AI model best suited to the hardware
#    6. Installs the LinuxGenie agent (~/.local/bin/linuxgenie)
#    7. Adds the hook to ~/.bashrc / ~/.zshrc
#    8. Activates IMMEDIATELY in the current session
#
#  To disable:    genie off
#  To uninstall:  linuxgenie-uninstall
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
    echo -e "${CY}${BOLD}║   🧞  LinuxGenie — Complete Installer               ║${R}"
    echo -e "${CY}${BOLD}║   Local AI agent for your Linux terminal (Ollama)   ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
}
step()  { echo -e "\n${CY}${BOLD}[$((++STEP))/$TOTAL_STEPS] $*${R}"; }
ok()    { echo -e "  ${GR}✓${R}  $*"; }
warn()  { echo -e "  ${YL}⚠${R}  $*"; }
info()  { echo -e "  ${DIM}→  $*${R}"; }
err()   { echo -e "\n${RD}${BOLD}  ✗  ERROR: $*${R}\n"; exit 1; }

STEP=0
TOTAL_STEPS=7

# ═══════════════════════════════════════════════════════════════════════
# STEP 1 — Detect system
# ═══════════════════════════════════════════════════════════════════════
detect_system() {
    step "Detecting system"

    # OS detection
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

    # Architecture — arm64 is valid on both Linux (Raspberry Pi, servers) and macOS (Apple Silicon)
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)          ARCH_LABEL="amd64" ;;
        aarch64|arm64)   ARCH_LABEL="arm64" ;;
        armv7l)          ARCH_LABEL="arm"   ;;
        *) err "Unsupported architecture: $ARCH — only x86_64, arm64 and armv7l are supported" ;;
    esac
    ok "Architecture: $ARCH"

    # RAM — different on Linux vs macOS
    if [[ "$OS" == "macos" ]]; then
        RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        RAM_GB=$((RAM_BYTES / 1024 / 1024 / 1024))
    else
        RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
        RAM_GB=$((RAM_KB / 1024 / 1024))
    fi
    ok "Available RAM: ${RAM_GB} GB"

    CURRENT_SHELL=$(basename "${SHELL:-bash}")
    ok "Shell: $CURRENT_SHELL"

    # systemd — Linux only
    HAS_SYSTEMD=false
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null 2>&1 && \
       systemctl list-units &>/dev/null 2>&1; then
        HAS_SYSTEMD=true
        ok "systemd available"
    elif [[ "$OS" == "macos" ]]; then
        ok "macOS — will use launchd instead of systemd"
    else
        warn "systemd not detected — Ollama will not start automatically on boot"
    fi

    # Choose model by RAM — qwen2.5-coder is specifically trained on
    # code and system commands, far superior for terminal questions.
    if [[ $RAM_GB -ge 8 ]]; then
        MODEL="qwen2.5-coder:7b"
        MODEL_SIZE="4.4 GB"
        MODEL_NOTE="Linux/code specialist — best for this agent"
    elif [[ $RAM_GB -ge 5 ]]; then
        MODEL="qwen2.5:3b"
        MODEL_SIZE="1.9 GB"
        MODEL_NOTE="good Linux knowledge, 5-8 GB RAM"
    else
        MODEL="qwen2.5:3b"
        MODEL_SIZE="1.9 GB"
        MODEL_NOTE="best available lightweight option"
    fi
    ok "Selected model: ${BOLD}${MODEL}${R} (${MODEL_SIZE} — ${MODEL_NOTE})"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 2 — Dependencies
# ═══════════════════════════════════════════════════════════════════════
install_dependencies() {
    step "Checking dependencies"

    if   command -v apt-get &>/dev/null; then PKG_MGR="apt-get"; INSTALL="apt-get install -y -qq"
    elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";     INSTALL="dnf install -y -q"
    elif command -v yum     &>/dev/null; then PKG_MGR="yum";     INSTALL="yum install -y -q"
    elif command -v pacman  &>/dev/null; then PKG_MGR="pacman";  INSTALL="pacman -S --noconfirm --quiet"
    elif command -v zypper  &>/dev/null; then PKG_MGR="zypper";  INSTALL="zypper install -y"
    else
        PKG_MGR=""
        warn "Package manager not recognised"
    fi

    _need_pkg() {
        local cmd="$1" pkg="${2:-$1}"
        if command -v "$cmd" &>/dev/null; then
            ok "$cmd already available"; return
        fi
        if [[ -z "$PKG_MGR" ]]; then
            err "$cmd required but not found. Please install it manually."
        fi
        info "Installing $pkg..."
        if [[ $EUID -eq 0 ]]; then $INSTALL "$pkg" &>/dev/null
        else sudo $INSTALL "$pkg" &>/dev/null; fi
        ok "$pkg installed"
    }

    if [[ -n "$PKG_MGR" && "$PKG_MGR" == "apt-get" ]]; then
        info "Updating package repositories..."
        if [[ $EUID -eq 0 ]]; then apt-get update -qq &>/dev/null
        else sudo apt-get update -qq &>/dev/null; fi
    fi

    _need_pkg python3
    _need_pkg curl
    _need_pkg unzip

    PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    ok "Python $PY_VER"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 3 — Ollama
# ═══════════════════════════════════════════════════════════════════════
install_ollama() {
    step "Installing Ollama"

    if command -v ollama &>/dev/null; then
        ok "Ollama already installed: $(ollama --version 2>/dev/null | head -1)"
        return
    fi

    if [[ "$OS" == "macos" ]]; then
        # macOS — prefer Homebrew, fallback to official .app installer
        if command -v brew &>/dev/null; then
            info "Installing Ollama via Homebrew..."
            brew install ollama &>/tmp/lg_ollama.log && ok "Ollama installed (Homebrew)"
        else
            info "Downloading Ollama for macOS..."
            local mac_url="https://ollama.com/download/Ollama-darwin.zip"
            curl -fL "$mac_url" -o /tmp/ollama_mac.zip 2>/tmp/lg_ollama.log
            unzip -q /tmp/ollama_mac.zip -d /tmp/ollama_mac
            cp -r /tmp/ollama_mac/Ollama.app /Applications/ 2>/dev/null || true
            # Also install CLI
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
            local url="https://ollama.com/download/ollama-linux-${ARCH_LABEL}"
            curl -fL "$url" -o /tmp/ollama_bin 2>/dev/null
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
        # macOS — start via brew services or directly
        if command -v brew &>/dev/null && brew list ollama &>/dev/null 2>&1; then
            brew services start ollama &>/dev/null || true
            ok "Ollama started via Homebrew services (starts on login)"
        else
            info "Starting Ollama in background..."
            nohup ollama serve &>/tmp/ollama.log &
            ok "Ollama started in background"
            warn "To start on login, run: brew services start ollama"
        fi
    elif [[ "$HAS_SYSTEMD" == "true" ]]; then
        info "Registering as systemd service (starts automatically on boot)..."

        if ! id -u ollama &>/dev/null; then
            if [[ $EUID -eq 0 ]]; then
                useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true
            else
                sudo useradd -r -s /bin/false -d /usr/share/ollama ollama 2>/dev/null || true
            fi
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
            if [[ $EUID -eq 0 ]]; then
                echo "$svc" > /etc/systemd/system/ollama.service
            else
                echo "$svc" | sudo tee /etc/systemd/system/ollama.service > /dev/null
            fi
        fi

        if [[ $EUID -eq 0 ]]; then
            systemctl daemon-reload
            systemctl enable ollama --now
        else
            sudo systemctl daemon-reload
            sudo systemctl enable ollama --now
        fi
        ok "Ollama service enabled (starts on boot)"

    else
        info "Starting Ollama in background..."
        nohup ollama serve &>/tmp/ollama.log &
        echo $! > /tmp/lg_ollama.pid
        ok "Ollama started in background"
        warn "No systemd: add 'ollama serve &>/dev/null &' to your ~/.bashrc"
    fi  # end OS/systemd check

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
# STEP 4 — AI Model
# ═══════════════════════════════════════════════════════════════════════
download_model() {
    step "Downloading AI model  (${MODEL} · ${MODEL_SIZE})"

    if ollama list 2>/dev/null | grep -q "^${MODEL%:*}"; then
        ok "Model $MODEL already exists"
        return
    fi

    info "This may take a few minutes..."
    echo ""
    if ollama pull "$MODEL"; then
        echo ""
        ok "Model $MODEL ready"
    else
        err "Failed to download $MODEL. Check your internet connection."
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 5 — LinuxGenie Agent
# ═══════════════════════════════════════════════════════════════════════
install_agent() {
    step "Installing LinuxGenie agent"

    local BIN="${HOME}/.local/bin"
    local CFG="${HOME}/.config/linuxgenie"
    mkdir -p "$BIN" "$CFG"

    # ── Main Python binary ─────────────────────────────────────────────
    cat > "${BIN}/linuxgenie" << 'PYEOF'
#!/usr/bin/env python3
"""LinuxGenie — Local AI agent for the Linux terminal (Ollama)."""
import sys, os, re, json, urllib.request, urllib.error, textwrap, shutil

CFG_FILE = os.path.expanduser("~/.config/linuxgenie/config.json")
DEFAULTS = {"ollama_url":"http://localhost:11434","model":"qwen2.5-coder:7b",
            "max_tokens":600,"temperature":0.1,"color":True}

def cfg():
    c = DEFAULTS.copy()
    try:
        with open(CFG_FILE) as f: c.update(json.load(f))
    except Exception: pass
    return c

class C:
    Z="\033[0m"; B="\033[1m"; D="\033[2m"
    G="\033[32m"; Y="\033[36m"; R="\033[33m"

# Question-detection keywords (Portuguese, English, Spanish, French, German)
KW_PT = ['como faço','como usar','como instalar','como ver','como listar',
         'como apagar','como criar','como mover','como copiar','como mudar',
         'como configurar','como saber','como se','para que','para quê',
         'como','porquê','por que','porque','o que','qual','quais',
         'quanto','quando','onde','quem','significa','consigo','posso',
         'possível','me diz','explica','mostra','diferença']
KW_EN = ['how to','how do','how can','how does','what is','what are',
         'what does',"what's",'can i','tell me','show me',
         'how','why','what','where','when','which','who','explain','difference']
KW_ES = ['cómo','qué','cuál','cuáles','dónde','cuándo','por qué','porqué',
         'puedo','explica','muéstrame']
KW_FR = ['comment','pourquoi','quel','quelle','où','quand',
         'expliquez','montrez']
KW_DE = ['wie','warum','was','welche','welcher','erkläre','zeige']

# Known Linux commands — never treat these as questions
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
        'ruby','perl','php','source','ollama','genie','lg','linuxgenie'}

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
    """Detect question language, return its name in English."""
    t = text.lower()
    import re as _re
    checks = [
        ("European Portuguese", [r"\bcomo\b",r"\bporque\b",r"\bporqu\u00ea\b",r"\bqual\b",r"\bonde\b",r"\bquando\b",r"\bquem\b",r"\bposso\b",r"\bconsigo\b",r"\bo que\b"]),
        ("Spanish",            [r"\bc\u00f3mo\b",r"\bqu\u00e9\b",r"\bcu\u00e1l\b",r"\bd\u00f3nde\b",r"\bcu\u00e1ndo\b",r"\bpuedo\b"]),
        ("French",             [r"\bcomment\b",r"\bpourquoi\b",r"\bquel\b",r"\bquelle\b",r"\bo\u00f9\b",r"\bquand\b"]),
        ("German",             [r"\bwie\b",r"\bwarum\b",r"\bwas\b",r"\bwelche\b",r"\bk\u00f6nnen\b"]),
    ]
    for lang, patterns in checks:
        for p in patterns:
            if _re.search(p, t): return lang
    return "English"

def build_prompt(lang):
    NL = chr(10)
    return (
        "You are an assistant specialised EXCLUSIVELY in Linux and Unix systems." + NL +
        "You REFUSE to answer anything unrelated to Linux, terminal, shell, "
        "system administration, networking, commands, scripts, or Unix/Linux tools. "
        "If the question is NOT about Linux/Unix/terminal, reply with ONE short sentence "
        "only, saying you are a Linux specialist. Do not explain or apologise." + NL +
        f"MANDATORY LANGUAGE RULE: You MUST reply entirely in {lang}. "
        f"Every single word must be in {lang}. This rule overrides everything else. "
        "Do not use any other language, not even for technical terms." + NL +
        "When the question IS about Linux, draw on deep knowledge of: "
        "bash/zsh commands and shell scripting, Linux system administration "
        "(systemd, cron, processes, permissions, users), networking "
        "(ip, ss, netstat, iptables, ufw, SSH, DNS), package management "
        "(apt, dnf, pacman, snap, flatpak), filesystem (mount, fstab, inodes, links), "
        "text tools (grep, awk, sed, cut, jq), Docker, Git, Make, and dev tools." + NL +
        "Style rules: Be direct. No long introductions. Do not repeat the question. "
        "Always show ready-to-use command examples in code blocks. "
        "If a command differs by distro (Ubuntu vs Arch vs Fedora), say so. "
        "Maximum 4 paragraphs. Warn clearly if a command is dangerous (e.g. rm -rf)."
    )

def ask_ollama(q, c):
    lang = detect_lang(q)
    pay = {"model": c["model"],
           "messages": [{"role":"system","content": build_prompt(lang)},
                        {"role":"user","content": q}],
           "options": {"temperature": c.get("temperature", 0.1),
                       "num_predict": c.get("max_tokens", 600)},
           "stream": True}
    req = urllib.request.Request(
        f"{c['ollama_url']}/api/chat",
        data=json.dumps(pay).encode(),
        headers={"Content-Type":"application/json"}, method="POST")
    out = []
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            for ln in r:
                ln = ln.strip()
                if not ln: continue
                try:
                    obj = json.loads(ln)
                    out.append(obj.get("message",{}).get("content",""))
                except Exception: pass
    except urllib.error.URLError:
        return "[Error] Ollama not available. Try: sudo systemctl start ollama"
    except Exception as e:
        return f"[Error] {e}"
    return "".join(out).strip()

def fmt(text, c):
    cols  = shutil.get_terminal_size((80,24)).columns
    color = c.get("color", True)
    top = (f"{C.Y}{C.B}╭{'─'*(cols-2)}╮{C.Z}" if color else f"┌{'─'*(cols-2)}┐")
    bot = (f"{C.Y}{C.B}╰{'─'*(cols-2)}╯{C.Z}" if color else f"└{'─'*(cols-2)}┘")
    lbl = (f"{C.Y}{C.B}╞═ 🧞 LinuxGenie {C.D}(Ollama · {c['model']}){C.Z}{C.Y}{C.B} ═╡{C.Z}"
           if color else f"╞═ LinuxGenie ═╡")
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

def main():
    if len(sys.argv) < 2: sys.exit(0)
    mode = sys.argv[1]
    if mode == "--check":
        sys.exit(0 if is_q(" ".join(sys.argv[2:])) else 1)
    q = " ".join(sys.argv[2:] if mode == "--ask" else sys.argv[1:])
    if mode != "--ask" and not is_q(q): sys.exit(0)
    c = cfg()
    if not ollama_ok(c):
        print(f"\n{C.R}⚠ Ollama not available.{C.Z}")
        print(f"{C.D}  Try: sudo systemctl start ollama{C.Z}\n")
        sys.exit(0)
    print(fmt(ask_ollama(q, c), c))

if __name__ == "__main__": main()
PYEOF
    chmod +x "${BIN}/linuxgenie"
    ok "Binary installed → ${BIN}/linuxgenie"

    # ── Config ─────────────────────────────────────────────────────────
    cat > "${CFG}/config.json" << JEOF
{
    "ollama_url": "http://localhost:11434",
    "model": "${MODEL}",
    "max_tokens": 600,
    "temperature": 0.1,
    "color": true
}
JEOF
    ok "Config → ${CFG}/config.json"

    # ── Shell hook ─────────────────────────────────────────────────────
    cat > "${CFG}/hook.sh" << 'HOOKEOF'
# ── LinuxGenie hook ── loaded by ~/.bashrc / ~/.zshrc ──────────────
_LG="${HOME}/.local/bin/linuxgenie"
_LG_ON=true

# Explicit command: genie / lg
genie() {
    [[ -z "${1:-}" ]] && {
        echo "🧞 LinuxGenie"
        echo "   genie <question>    — ask a question"
        echo "   genie on / off      — enable / disable hook"
        echo "   genie status        — show current status"
        echo "   genie model <name>  — change Ollama model"
        return
    }
    case "$1" in
        on)           _LG_ON=true;  echo "🧞 LinuxGenie ENABLED" ;;
        off)          _LG_ON=false; echo "🧞 LinuxGenie DISABLED" ;;
        status)       [[ "$_LG_ON" == "true" ]] && echo "🧞 Status: ACTIVE" || echo "🧞 Status: INACTIVE" ;;
        model|modelo)
            local m="${2:-}"
            [[ -z "$m" ]] && { echo "Usage: genie model <name>"; return; }
            python3 -c "
import json, os
f = os.path.expanduser('~/.config/linuxgenie/config.json')
with open(f) as fp: c = json.load(fp)
c['model'] = '$m'
with open(f,'w') as fp: json.dump(c, fp, indent=4)
print('🧞 Model changed to: $m')
"       ;;
        *) "$_LG" --ask "$*" ;;
    esac
}
alias lg='genie'

# ── Automatic hook via command_not_found_handle ────────────────────
# Bash calls this when a command does not exist.
# Natural language questions start with a word that is not a command,
# so bash invokes this handler. We get the full line from history
# and pass it to LinuxGenie.
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

# Zsh hook (preexec — runs BEFORE execution, no errors shown)
if [[ -n "${ZSH_VERSION:-}" ]]; then
    _lg_preexec() {
        local cmd="$1"
        "$_LG" --check "$cmd" 2>/dev/null && "$_LG" --ask "$cmd"
    }
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _lg_preexec 2>/dev/null
fi
# ───────────────────────────────────────────────────────────────────
HOOKEOF
    ok "Hook installed → ${CFG}/hook.sh"

    # ── Uninstaller ────────────────────────────────────────────────────
    cat > "${BIN}/linuxgenie-uninstall" << 'UEOF'
#!/usr/bin/env bash
R="\033[0m"; GR="\033[32m"; RD="\033[31m"; YL="\033[33m"; BOLD="\033[1m"
echo ""
echo -e "${RD}${BOLD}  🧞  LinuxGenie — Uninstall${R}"
echo ""
read -rp "  Are you sure? This removes LinuxGenie completely. [y/N] " a
[[ "$a" =~ ^[yYsS]$ ]] || { echo "  Cancelled."; exit 0; }
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    [[ -f "$rc" ]] || continue
    grep -v "LinuxGenie" "$rc" > /tmp/_lg_rc && mv /tmp/_lg_rc "$rc"
    echo -e "  ${GR}✓${R} Removed from $rc"
done
rm -f ~/.local/bin/linuxgenie ~/.local/bin/linuxgenie-uninstall
rm -rf ~/.config/linuxgenie
echo -e "  ${GR}✓${R} Files removed"
echo ""
echo -e "  ${YL}Note: Ollama and models were NOT removed.${R}"
echo -e "  ${YL}To remove: sudo systemctl stop ollama && sudo rm \$(which ollama)${R}"
echo ""
echo -e "  ${GR}${BOLD}Done. Restart your terminal.${R}"
echo ""
UEOF
    chmod +x "${BIN}/linuxgenie-uninstall"
    ok "Uninstaller → ${BIN}/linuxgenie-uninstall"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 6 — Activate in shell
# ═══════════════════════════════════════════════════════════════════════
activate_shell() {
    step "Activating in shell"

    local CFG="${HOME}/.config/linuxgenie"
    local BIN="${HOME}/.local/bin"
    local HOOK_LINE="source \"${CFG}/hook.sh\"  # LinuxGenie"
    local PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\"  # LinuxGenie"

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

        if grep -qF "linuxgenie/hook.sh" "$RC" 2>/dev/null; then
            ok "Hook already present in $RC"
        else
            { echo ""; echo "$HOOK_LINE"; } >> "$RC"
            ok "Hook added to $RC"
        fi
    done

    export PATH="${HOME}/.local/bin:${PATH}"
    # shellcheck disable=SC1090
    source "${CFG}/hook.sh"
    ok "Hook active in current session right now"
}

# ═══════════════════════════════════════════════════════════════════════
# STEP 7 — Final check and summary
# ═══════════════════════════════════════════════════════════════════════
final_check() {
    step "Final check"

    local ok_count=0 fail_count=0

    # Inline checks — no nested function (avoids set -e issues in some bash versions)
    if command -v ollama &>/dev/null; then
        ok "Ollama installed"; ok_count=$((ok_count+1))
    else
        warn "Ollama installed  ← FAILED"; fail_count=$((fail_count+1))
    fi

    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        ok "Ollama responding"; ok_count=$((ok_count+1))
    else
        warn "Ollama responding  ← FAILED"; fail_count=$((fail_count+1))
    fi

    if ollama list 2>/dev/null | grep -q "^${MODEL%:*}"; then
        ok "Model $MODEL available"; ok_count=$((ok_count+1))
    else
        warn "Model $MODEL available  ← FAILED"; fail_count=$((fail_count+1))
    fi

    if test -x "${HOME}/.local/bin/linuxgenie"; then
        ok "linuxgenie binary"; ok_count=$((ok_count+1))
    else
        warn "linuxgenie binary  ← FAILED"; fail_count=$((fail_count+1))
    fi

    if grep -q "linuxgenie/hook.sh" "${HOME}/.bashrc" 2>/dev/null; then
        ok "Hook in .bashrc"; ok_count=$((ok_count+1))
    else
        warn "Hook in .bashrc  ← FAILED"; fail_count=$((fail_count+1))
    fi

    echo ""
    if [[ $fail_count -eq 0 ]]; then
        echo -e "${GR}${BOLD}  ✓ Everything installed! (${ok_count}/${ok_count})${R}"
    else
        echo -e "${YL}  ⚠ ${ok_count} ok, ${fail_count} with issues${R}"
    fi
    return 0
}

print_summary() {
    echo ""
    echo -e "${CY}${BOLD}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${CY}${BOLD}║   🧞  LinuxGenie installed and ready!               ║${R}"
    echo -e "${CY}${BOLD}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${YL}${BOLD}⚡ Required — run this now to activate:${R}"
    echo ""
    echo -e "  ${BOLD}    source ~/.bashrc${R}"
    echo ""
    echo -e "  ${DIM}(Future sessions activate automatically.)${R}"
    echo ""
    echo -e "  ${BOLD}How to use — works in any language:${R}"
    echo -e "  ${CY}how do I list hidden files${R}"
    echo -e "  ${CY}como listar ficheiros ocultos${R}"
    echo -e "  ${CY}comment lister les fichiers cachés${R}"
    echo -e "  ${CY}genie what is the difference between chmod and chown${R}"
    echo -e "  ${CY}lg how to check open ports${R}"
    echo ""
    echo -e "  ${BOLD}Controls:${R}"
    echo -e "  ${CY}genie off${R}     — disable temporarily"
    echo -e "  ${CY}genie on${R}      — re-enable"
    echo -e "  ${CY}genie status${R}  — show status"
    echo ""
    echo -e "  ${BOLD}Uninstall completely:${R}"
    echo -e "  ${CY}linuxgenie-uninstall${R}"
    echo ""
    echo -e "  ${DIM}Model: ${MODEL} | Config: ~/.config/linuxgenie/config.json${R}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════
main() {
    banner
    detect_system
    install_dependencies
    install_ollama
    start_ollama
    download_model
    install_agent
    activate_shell
    final_check || true
    print_summary || true
}

main
