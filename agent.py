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
