#!/usr/bin/env python3
"""TuxAide v2.1 — Local AI assistant for Linux terminal with Smart RAG."""
import sys, os, re, json, hashlib, time, urllib.request, urllib.error
import textwrap, shutil, threading, itertools, subprocess, base64, select

CFG_FILE  = os.path.expanduser("~/.config/tuxaide/config.json")
CACHE_DIR = os.path.expanduser("~/.config/tuxaide/cache")
LOG_DIR   = os.path.expanduser("~/.config/tuxaide/logs")
PERF_LOG  = os.path.join(LOG_DIR, "perf.log")
SESSION_FILE = os.path.expanduser("~/.config/tuxaide/session.json")
PENDING_DIR  = os.path.expanduser("~/.config/tuxaide/pending")

DEFAULTS = {
    "ollama_url":   "http://localhost:11434",
    "model":        "qwen2.5-coder:7b",
    "embed_model":  "nomic-embed-text",
    "max_tokens":   300,
    "temperature":  0.1,
    "color":        True,
    "mode":         "llm",    # "llm", "smart", "deep"
    "session_capture": True,
    "rag_top_k":    1,
    "rag_db_path":  "~/.config/tuxaide/vectordb",
    "rag_timeout":  8,        # seconds before RAG fallback to LLM
    "enabled":      True,     # persisted by `tuxaide on/off`
    "prewarm":      "once",   # "off", "once" (at most every keep_alive), "always"
    "keep_alive":   "10m",    # how long Ollama keeps the model loaded
    "cache_ttl_days": 30,
    "action_menu":  True,     # after an answer: put a command on the prompt / copy it
}

def _parse_bool(v):
    v = v.strip().lower()
    if v in ("1", "true", "yes", "on"):  return True
    if v in ("0", "false", "no", "off"): return False
    raise ValueError("expected true or false")

def _parse_choice(*choices):
    def parse(v):
        if v not in choices:
            raise ValueError(f"expected one of: {', '.join(choices)}")
        return v
    return parse

def _parse_model(v):
    if not re.fullmatch(r"[A-Za-z0-9._:/-]+", v):
        raise ValueError("model names may only contain letters, digits and . _ : / -")
    return v

SETTABLE = {
    "enabled":         _parse_bool,
    "session_capture": _parse_bool,
    "color":           _parse_bool,
    "model":           _parse_model,
    "prewarm":         _parse_choice("off", "once", "always"),
    "action_menu":     _parse_bool,
}

def cfg():
    c = DEFAULTS.copy()
    try:
        with open(CFG_FILE) as f: c.update(json.load(f))
    except Exception: pass
    return c

def save_cfg(updates):
    """Update only the given keys, keeping whatever else the user has in the file."""
    try:
        with open(CFG_FILE) as f: c = json.load(f)
    except Exception:
        c = {}
    c.update(updates)
    os.makedirs(os.path.dirname(CFG_FILE), exist_ok=True)
    tmp = CFG_FILE + ".tmp"
    with open(tmp, 'w') as f: json.dump(c, f, indent=4)
    os.replace(tmp, CFG_FILE)

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
    def stop(self):
        self._stop.set()
        if self._t.is_alive(): self._t.join()

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
    'opções','erro','configurar','neste sistema',
    'indicateurs','erreur','configurer','mon système',
    'optionen','fehler','konfigurieren','mein system',
}
RAG_KEYWORDS_RE = re.compile(
    r'\b(?:' + '|'.join(re.escape(k) for k in sorted(RAG_KEYWORDS, key=len, reverse=True)) + r')\b',
    re.I)

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

def is_context_explain_query(text):
    t = text.strip().lower()
    patterns = [
        "what does this mean", "why did this fail", "explain this output",
        "explain this error", "porque deu este erro", "explica este output",
        "por que deu este erro", "que erro foi este", "porque falhou",
        "isto significa o quê", "o que significa isto"
    ]
    return any(p in t for p in patterns)

class ContextIntentDetector:
    """Isolated detector for routing contextual follow-up questions."""
    DEICTIC_TERMS = {
        "this", "that", "it", "isto", "isso", "este", "esta", "esse", "essa",
        "esto", "eso", "ceci", "cela", "dies", "das"
    }
    ERROR_TERMS = {
        "error", "failed", "fail", "issue", "problem", "erro", "falhou",
        "falha", "problema", "erroro", "erreur", "fehler"
    }

    @staticmethod
    def _tokens(text):
        return re.findall(r"[a-zA-ZÀ-ÿ']+", text.lower())

    @classmethod
    def looks_like_context_followup(cls, text):
        t = text.strip().lower()
        if not t:
            return False
        if is_context_explain_query(t):
            return True
        tokens = cls._tokens(t)
        if not tokens:
            return False
        short_phrase = len(tokens) <= 10
        has_deictic = any(tok in cls.DEICTIC_TERMS for tok in tokens)
        has_error_word = any(tok in cls.ERROR_TERMS for tok in tokens)
        return short_phrase and (has_deictic or has_error_word)

    @classmethod
    def should_explain_last(cls, text, session_capture_enabled, has_last_run):
        if not session_capture_enabled or not has_last_run:
            return False
        return cls.looks_like_context_followup(text)

def default_context_query():
    return "Explain the last shell command output and error in simple terms. Identify cause and suggest next step."

def load_last_shell_context():
    try:
        with open(SESSION_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        run = data.get("last_shell_run")
        if not isinstance(run, dict):
            return None
        return run
    except Exception:
        return None

def build_contextual_question(q, run):
    if not run:
        return q
    cmd = run.get("command", "")
    rc = run.get("exit_code", "")
    out = run.get("stdout", "")
    err = run.get("stderr", "")
    trunc = run.get("output_truncated", False)
    extra = (
        "\n\n[Session context: last shell run]\n"
        f"Command: {cmd}\n"
        f"Exit code: {rc}\n"
        f"Output truncated: {trunc}\n"
        f"STDOUT:\n{out}\n\n"
        f"STDERR:\n{err}\n"
    )
    return q + extra

# ── Normalisation & cache ─────────────────────────────────────────────
def normalize(q):
    """Normalise question for cache key: lowercase, strip, collapse spaces, remove trailing punctuation."""
    q = q.lower().strip()
    q = re.sub(r"[?!.]+$", "", q)
    q = re.sub(r"\s+", " ", q)
    return q

def cache_key(text):
    return hashlib.md5(text.encode()).hexdigest()

def answer_cache_key(norm_q, c):
    """Answers depend on the model and the configured mode, not just the question."""
    return cache_key(f"{c.get('model')}|{c.get('mode', 'llm')}|{norm_q}")

def cache_get(kind, key, max_age_days=None):
    """kind: 'answers' or 'embeddings'. Entries older than max_age_days are ignored."""
    path = os.path.join(CACHE_DIR, kind, key + ".json")
    try:
        if max_age_days and time.time() - os.path.getmtime(path) > max_age_days * 86400:
            return None
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
def perf_log(question, mode, t_embed, t_rag, t_llm, cache_hit, ttft=None):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        total = t_embed + t_rag + t_llm
        ts = time.strftime("%Y-%m-%dT%H:%M:%S")
        line = (f"{ts}\t{mode}\t"
                f"embed={t_embed:.2f}s\trag={t_rag:.2f}s\t"
                f"llm={t_llm:.2f}s\t"
                f"ttft={'-' if ttft is None else f'{ttft:.2f}s'}\t"
                f"total={total:.2f}s\t"
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
    # Explicit RAG keywords (whole words only)
    if RAG_KEYWORDS_RE.search(question):
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
def build_prompt(passages=None):
    NL = chr(10)
    base = (
        "You are TuxAide, an assistant specialised EXCLUSIVELY in Linux and Unix systems." + NL +
        "You REFUSE to answer anything unrelated to Linux, terminal, shell, "
        "system administration, networking, commands, scripts, or Unix/Linux tools. "
        "If the question is NOT about Linux/Unix/terminal, reply with ONE short sentence "
        "only, saying you are a Linux specialist. Do not explain or apologise." + NL +
        "MANDATORY LANGUAGE RULE: Reply entirely in the same language the user wrote "
        "their question in (the user's question is the text before any [Session context] block). "
        "If the question mixes languages, use the language of most of its words. "
        "This rule overrides everything else." + NL
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
class OllamaError(Exception):
    pass

def stream_ollama(q, c, passages=None):
    """Yield answer text chunks as Ollama generates them. Raises OllamaError."""
    pay = {
        "model": c["model"],
        "messages": [
            {"role": "system", "content": build_prompt(passages)},
            {"role": "user",   "content": q + (
                "\n\n[Important: end your answer with exactly: Source: <man page name>]"
                if passages else ""
            )}
        ],
        "options": {"temperature": c.get("temperature", 0.1),
                    "num_predict": c.get("max_tokens", 300),
                    "num_gpu": c.get("num_gpu", 99)},
        "keep_alive": c.get("keep_alive", "10m"),
        "stream": True
    }
    req = urllib.request.Request(
        f"{c['ollama_url']}/api/chat",
        data=json.dumps(pay).encode(),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            for ln in r:
                ln = ln.strip()
                if not ln: continue
                try: msg = json.loads(ln)
                except Exception: continue
                if msg.get("error"):
                    raise OllamaError(msg["error"])
                chunk = msg.get("message", {}).get("content", "")
                if chunk:
                    yield chunk
    except OllamaError:
        raise
    except urllib.error.HTTPError as e:
        detail = ""
        try: detail = json.loads(e.read()).get("error", "")
        except Exception: pass
        raise OllamaError(detail or f"HTTP {e.code}")
    except urllib.error.URLError:
        raise OllamaError("Ollama not available. Try: sudo systemctl start ollama")
    except Exception as e:
        raise OllamaError(str(e) or e.__class__.__name__)

# ── Formatting ────────────────────────────────────────────────────────
class Renderer:
    """Incremental formatter: prints the answer box line by line as text streams in.

    Code blocks are buffered until they close so the destructive-command warning
    can be shown above the block that triggered it.
    """
    def __init__(self, c, mode="llm", out=None, numbered=False):
        self.out   = out or sys.stdout
        self.numbered = numbered
        self.commands = []     # runnable commands found in shell code blocks
        self.color = c.get("color", True)
        self.model = c.get("model", "")
        self.mode  = mode
        self.cols  = max(shutil.get_terminal_size((80, 24)).columns, 24)
        self.buf   = ""
        self.code  = None      # list of lines while inside a code block
        self.code_lang = "shell"
        self.started = False
        self.last_blank = True

    def _w(self, line=""):
        self.out.write(line + "\n")
        self.out.flush()
        self.last_blank = not line

    def header(self):
        if self.started: return
        self.started = True
        cols, color = self.cols, self.color
        mode_label = " · Smart RAG" if self.mode == "smart" else (" · RAG" if self.mode == "deep" else "")
        self._w()
        self._w(f"{C.Y}{C.B}╭{'─'*(cols-2)}╮{C.Z}" if color else f"┌{'─'*(cols-2)}┐")
        self._w(f"{C.Y}{C.B}╞═ 🐧 TuxAide {C.D}(Ollama · {self.model}{mode_label}){C.Z}{C.Y}{C.B} ═╡{C.Z}"
                if color else "╞═ TuxAide ═╡")

    def feed(self, chunk):
        self.header()
        self.buf += chunk
        while "\n" in self.buf:
            line, self.buf = self.buf.split("\n", 1)
            self._line(line)

    def finish(self):
        self.header()
        if self.buf:
            self._line(self.buf)
            self.buf = ""
        if self.code is not None:
            self._flush_code()
        self._w(f"{C.Y}{C.B}╰{'─'*(self.cols-2)}╯{C.Z}" if self.color else f"└{'─'*(self.cols-2)}┘")
        self._w()

    def _flush_code(self):
        color = self.color
        if is_destructive("\n".join(self.code)):
            if not self.last_blank:
                self._w()
            warning = ("⚠  WARNING: This command is destructive and irreversible."
                       " Verify carefully before running.")
            for w in textwrap.wrap(warning, width=self.cols - 4):
                self._w(f"  {C.RD}{C.B}{w}{C.Z}" if color else f"  {w}")
        self._w(f"  {C.D}┄ {self.code_lang} ┄{C.Z}" if color else f"  ┄ {self.code_lang} ┄")
        starts = {}
        if self.numbered and self.code_lang.lower() in SHELL_LANGS:
            for idx, cmd in extract_commands(self.code):
                if len(self.commands) < MAX_COMMANDS:
                    self.commands.append(cmd)
                    starts[idx] = len(self.commands)
        pad = "    " if self.numbered and self.commands else ""
        for i, line in enumerate(self.code):
            if i in starts:
                num = f"[{starts[i]}] "
                self._w(f"  {C.Y}{num}{C.Z}{C.G}{line}{C.Z}" if color else f"  {num}{line}")
            else:
                self._w(f"  {pad}{C.G}{line}{C.Z}" if color else f"  {pad}{line}")
        rule = "┄" * (len(self.code_lang) + 4)
        self._w(f"  {C.D}{rule}{C.Z}" if color else f"  {rule}")
        self.code = None

    def _line(self, line):
        if line.strip().startswith("```"):
            if self.code is None:
                self.code = []
                self.code_lang = line.strip()[3:].strip() or "shell"
            else:
                self._flush_code()
            return
        if self.code is not None:
            self.code.append(line)
            return
        if not line.strip():
            self._w(); return
        if self.color:
            line = re.sub(r'\*\*(.+?)\*\*', f'{C.B}\\1{C.Z}', line)
            line = re.sub(r'`([^`]+)`', f'{C.G}\\1{C.Z}', line)
        # Escape codes count towards the width, so coloured lines wrap a little
        # early but never overflow the terminal.
        for w in textwrap.wrap(line, width=self.cols - 4, break_long_words=False):
            self._w(f"  {w}")

SHELL_LANGS  = {"shell", "bash", "sh", "zsh", "console", "terminal"}
MAX_COMMANDS = 9

def extract_commands(lines):
    """Return [(line_index, command)] for the runnable lines of a shell code block.

    Skips blank lines and comments, strips a leading "$ " prompt and joins
    backslash continuations into one command.
    """
    out, i = [], 0
    while i < len(lines):
        s = lines[i].strip()
        if not s or s.startswith("#"):
            i += 1; continue
        if s.startswith("$ "):
            s = s[2:].strip()
        start, parts = i, [s]
        while parts[-1].endswith("\\") and i + 1 < len(lines):
            i += 1
            parts.append(lines[i].strip())
        cmd = "\n".join(parts).strip()
        if cmd and cmd not in (c for _, c in out):
            out.append((start, cmd))
        i += 1
    return out

def menu_enabled(c):
    return bool(c.get("action_menu", True)) and sys.stdout.isatty() and sys.stdin.isatty()

def render_text(text, c, mode="llm"):
    """Render a complete answer (cache hits, messages) in one go. Returns the commands found."""
    r = Renderer(c, mode, numbered=menu_enabled(c))
    r.feed(text)
    r.finish()
    return r.commands

def answer_streaming(q, c, passages, mode, spinner):
    """Stream the answer to the terminal. Returns (answer, ok, ttft, commands)."""
    r = Renderer(c, mode, numbered=menu_enabled(c))
    parts, ttft, ok = [], None, True
    t0 = time.time()
    try:
        for chunk in stream_ollama(q, c, passages):
            if ttft is None:
                ttft = time.time() - t0
                spinner.stop()
            parts.append(chunk)
            r.feed(chunk)
    except OllamaError as e:
        ok = False
        spinner.stop()
        r.feed(("\n\n" if parts else "") + f"[Error] {e}")
    except KeyboardInterrupt:
        ok = False
        spinner.stop()
        r.feed("\n\n[Interrupted]")
    spinner.stop()
    answer = "".join(parts).strip()
    if not answer and ok:
        ok = False
        r.feed("[Error] Empty answer from the model.")
    r.finish()
    return answer, ok, ttft, (r.commands if ok else [])

# ── After-answer actions: put a command on the prompt, or copy it ─────
def read_key(tty, timeout, prompt=b""):
    """Show prompt, then read one keypress without echo. Returns '' on timeout.

    Raw mode is entered *before* the prompt is shown: keys typed while the
    answer was streaming are discarded, and nothing pressed after the prompt
    appears can be lost.
    """
    import termios, tty as ttymod
    fd = tty.fileno()
    old = termios.tcgetattr(fd)
    try:
        ttymod.setcbreak(fd, termios.TCSAFLUSH)
        tty.write(prompt); tty.flush()
        ready, _, _ = select.select([fd], [], [], timeout)
        if not ready:
            return ""
        ch = os.read(fd, 1)
        if ch == b"\x1b":                      # swallow the rest of an escape sequence
            while select.select([fd], [], [], 0.02)[0]:
                os.read(fd, 16)
        return ch.decode(errors="ignore")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

def copy_to_clipboard(text, tty):
    """Copy with the first available tool; fall back to OSC 52 (works over SSH)."""
    tools = [["pbcopy"]]
    if os.environ.get("WAYLAND_DISPLAY"):
        tools.append(["wl-copy"])
    tools += [["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]]
    for tool in tools:
        if shutil.which(tool[0]):
            try:
                subprocess.run(tool, input=text.encode(), check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
                return True
            except Exception:
                continue
    try:
        tty.write(f"\033]52;c;{base64.b64encode(text.encode()).decode()}\a".encode())
        tty.flush()
        return True
    except Exception:
        return False

def stage_for_prompt(cmd):
    """Hand the command to the parent shell's prompt hook. False if no hook is listening."""
    pid = os.environ.get("TUXAIDE_SHELL_PID", "")
    if not pid.isdigit():
        return False
    try:
        os.makedirs(PENDING_DIR, exist_ok=True)
        with open(os.path.join(PENDING_DIR, pid), "w") as f:
            f.write(cmd)
        return True
    except OSError:
        return False

def action_menu(commands, c, timeout=15):
    if not commands or not menu_enabled(c):
        return
    try:
        tty = open("/dev/tty", "r+b", buffering=0)
    except OSError:
        return
    n = len(commands)
    def say(msg, end="\n"):
        tty.write(f"\r\033[K  {msg}{end}".encode()); tty.flush()
    def pick(prompt):
        try:
            return read_key(tty, timeout, f"\r\033[K  {C.D}{prompt}{C.Z}".encode())
        except KeyboardInterrupt:
            return ""
        finally:
            tty.write(b"\r\033[K"); tty.flush()
    def number(key):
        return int(key) if key.isdigit() and 1 <= int(key) <= n else None

    keys = "1" if n == 1 else f"1-{n}"
    key = pick(f"{keys} put on prompt · c copy · Enter skip")
    try:
        if key.lower() == "c":
            idx = 1 if n == 1 else number(pick(f"copy which? {keys}"))
            if idx and copy_to_clipboard(commands[idx - 1], tty):
                say(f"{C.G}✓ Copied:{C.Z} {commands[idx - 1]}")
            return
        idx = number(key)
        if not idx:
            return
        cmd = commands[idx - 1]
        if is_destructive(cmd):
            if pick(f"{C.RD}⚠ Destructive command.{C.Z}{C.D} Put it on the prompt anyway? [y/N]").lower() != "y":
                say(f"{C.D}Skipped.{C.Z}")
                return
        if stage_for_prompt(cmd):
            if os.environ.get("TUXAIDE_SHELL") == "zsh":
                say(f"{C.G}✓ On your prompt{C.Z}{C.D} — edit it or press Enter to run{C.Z}")
            else:
                say(f"{C.G}✓ Press ↑{C.Z}{C.D} to get it on your prompt{C.Z}")
        elif copy_to_clipboard(cmd, tty):
            say(f"{C.G}✓ Copied:{C.Z} {cmd}")
    finally:
        tty.close()

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

    # --set KEY VALUE: persist a config value (used by the shell hook)
    if mode_arg == "--set":
        if len(sys.argv) != 4 or sys.argv[2] not in SETTABLE:
            print(f"Usage: tuxaide --set <{'|'.join(sorted(SETTABLE))}> <value>")
            sys.exit(2)
        key, raw = sys.argv[2], sys.argv[3]
        try:
            save_cfg({key: SETTABLE[key](raw)})
        except ValueError as e:
            print(f"Invalid value for {key}: {e}")
            sys.exit(2)
        return

    # --explain-last: force contextual explanation from last shell run
    if mode_arg == "--explain-last":
        c = cfg()
        if not ollama_ok(c):
            print(f"\n{C.O}⚠ Ollama not available.{C.Z}")
            print(f"{C.D}  Try: sudo systemctl start ollama{C.Z}\n")
            return
        last_run = load_last_shell_context()
        if not last_run:
            msg = "No recent shell execution context found in this session. Run a command with: tuxaide run \"<command>\""
            render_text(msg, c, "llm")
            return
        user_q = " ".join(sys.argv[2:]).strip() or default_context_query()
        effective_q = build_contextual_question(user_q, last_run)
        spinner = Spinner().start()
        _, _, _, commands = answer_streaming(effective_q, c, None, "llm", spinner)
        action_menu(commands, c)
        return

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
            print(f"{C.O}⚠ RAG requires chromadb, which isn't installed.{C.Z}")
            print(f"{C.D}  Re-run the TuxAide installer and answer Y to Smart RAG.{C.Z}"); return
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
        subprocess.run(["tuxaide-index", cmd])
        return

    # reindex: re-index all man pages
    if mode_arg == "reindex":
        print("🐧 Re-indexing all man pages...")
        subprocess.run(["tuxaide-index", "--all"])
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

    effective_q = q
    last_run = load_last_shell_context() if c.get("session_capture", False) else None
    context_query = ContextIntentDetector.should_explain_last(
        q,
        c.get("session_capture", False),
        bool(last_run),
    )
    if context_query and last_run:
        effective_q = build_contextual_question(q, last_run)

    norm_q    = normalize(effective_q if context_query else q)
    ans_key   = answer_cache_key(norm_q, c)
    t_embed   = 0.0
    t_rag     = 0.0
    t_llm     = 0.0
    cache_hit = False

    # ── Answer cache lookup ───────────────────────────────────────────
    cached_answer = None if context_query else cache_get(
        "answers", ans_key, c.get("cache_ttl_days", 30))
    if cached_answer and cached_answer.get("answer"):
        cache_hit = True
        answer    = cached_answer["answer"]
        act_mode  = cached_answer.get("mode", "llm")
        perf_log(norm_q, act_mode + "+cache", 0, 0, 0, True)
        action_menu(render_text(answer, c, act_mode), c)
        return

    # ── Determine mode and whether to use RAG ────────────────────────
    current_mode = c.get("mode", "llm")
    passages     = []
    detected_cmd = None
    act_mode     = "llm"

    spinner = Spinner().start()

    if context_query:
        passages = []
        act_mode = "llm"
    elif current_mode == "smart" and rag_available():
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

    # ── LLM call, streamed straight to the terminal ───────────────────
    t_llm_start = time.time()
    answer, ok, ttft, commands = answer_streaming(
        effective_q, c, passages if passages else None, act_mode, spinner)
    t_llm = time.time() - t_llm_start

    # ── Cache the answer (never errors or partial answers) ────────────
    if ok and not context_query:
        cache_set("answers", ans_key, {"answer": answer, "mode": act_mode})

    perf_log(norm_q, act_mode, t_embed, t_rag, t_llm, False, ttft)

    action_menu(commands, c)

if __name__ == "__main__": main()
