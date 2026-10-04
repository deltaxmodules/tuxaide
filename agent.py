#!/usr/bin/env python3
"""TuxAide — Local AI assistant for Linux terminal with Smart RAG."""
import sys, os, re, json, hashlib, time, urllib.request, urllib.error, urllib.parse
import textwrap, shutil, threading, itertools, subprocess, base64, select, shlex, tempfile

CFG_FILE  = os.path.expanduser("~/.config/tuxaide/config.json")
CACHE_DIR = os.path.expanduser("~/.config/tuxaide/cache")
LOG_DIR   = os.path.expanduser("~/.config/tuxaide/logs")
PERF_LOG  = os.path.join(LOG_DIR, "perf.log")
SESSION_FILE = os.path.expanduser("~/.config/tuxaide/session.json")
PENDING_DIR  = os.path.expanduser("~/.config/tuxaide/pending")
HISTORY_FILE = os.path.expanduser("~/.config/tuxaide/history.json")
HOOK_FILE    = os.path.expanduser("~/.config/tuxaide/hook.sh")
BIN_DIR      = os.path.expanduser("~/.local/bin")

# The one place the version lives. install.sh and the README must match it
# (tests/test_version.py checks).
__version__ = "2.3.0"

DEFAULTS = {
    "backend":      "ollama",  # "ollama", or "openai" for any OpenAI-compatible API
    "ollama_url":   "http://localhost:11434",
    "api_base":     "",        # backend "openai": e.g. http://localhost:1234/v1 (LM Studio)
    "api_key_env":  "OPENAI_API_KEY",  # the API key is read from this variable, never stored
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
    "failure_hint": True,     # after a failed command, hint that `?` explains it
    "typo_suggest": True,     # "Did you mean: git status?" for mistyped commands
    "followup_window": 600,   # seconds a conversation stays open for follow-ups
    "followup_turns": 3,      # previous exchanges sent with a follow-up
    "system_context": True,   # tell the model which OS / package manager / shell this is
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

def _parse_int(lo, hi):
    def parse(v):
        try:
            n = int(v)
        except ValueError:
            raise ValueError("expected a whole number") from None
        if not lo <= n <= hi:
            raise ValueError(f"expected a number from {lo} to {hi}")
        return n
    return parse

def _parse_float(lo, hi):
    def parse(v):
        try:
            n = float(v)
        except ValueError:
            raise ValueError("expected a number") from None
        if not lo <= n <= hi:
            raise ValueError(f"expected a number from {lo} to {hi}")
        return n
    return parse

def _parse_url(v):
    if not re.fullmatch(r"https?://[^\s/]+(/\S*)?", v):
        raise ValueError("expected a URL like http://localhost:11434")
    return v.rstrip("/")

def _parse_env_name(v):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", v):
        raise ValueError("expected the name of an environment variable, like OPENAI_API_KEY")
    return v

def _parse_duration(v):
    # Ollama's keep_alive: "30s", "10m", "1h", "0" (unload at once), "-1" (keep forever)
    if not re.fullmatch(r"-1|0|\d+[smh]", v):
        raise ValueError("expected a duration like 30s, 10m or 1h (0 = unload at once, -1 = never)")
    return v

# Settings `tuxaide config set` (and `--set`) may change, with their validators.
SETTABLE = {
    "enabled":         _parse_bool,
    "mode":            _parse_choice("llm", "smart", "deep"),
    "backend":         _parse_choice("ollama", "openai"),
    "model":           _parse_model,
    "embed_model":     _parse_model,
    "ollama_url":      _parse_url,
    "api_base":        _parse_url,
    "api_key_env":     _parse_env_name,
    "session_capture": _parse_bool,
    "color":           _parse_bool,
    "prewarm":         _parse_choice("off", "once", "always"),
    "keep_alive":      _parse_duration,
    "temperature":     _parse_float(0, 2),
    "rag_timeout":     _parse_int(1, 120),
    "cache_ttl_days":  _parse_int(0, 3650),
    "action_menu":     _parse_bool,
    "failure_hint":    _parse_bool,
    "typo_suggest":    _parse_bool,
    "followup_window": _parse_int(0, 86400),
    "followup_turns":  _parse_int(0, 10),
    "system_context":  _parse_bool,
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

    @classmethod
    def off(cls):
        for k in ("Z", "B", "D", "G", "Y", "R", "O", "RD"):
            setattr(cls, k, "")

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
    WHY_TERMS = {"why", "porque", "porquê", "pourquoi", "warum", "wieso", "perché", "qué"}

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
        has_why = any(tok in cls.WHY_TERMS for tok in tokens)
        # A pronoun alone ("and reverse it") is a follow-up to the conversation,
        # not a question about the last command's error.
        return short_phrase and (has_error_word or (has_deictic and has_why))

    @classmethod
    def should_explain_last(cls, text, session_capture_enabled, has_last_run):
        if not session_capture_enabled or not has_last_run:
            return False
        return cls.looks_like_context_followup(text)

# ── Explain the last command (`?` / `tuxaide why`) ────────────────────
# Re-running is the only way to see the error text (the hook records the
# command and exit code, never output). Only read-only commands are re-run
# without asking; anything else needs an explicit "y".
SAFE_RERUN = {
    "ls", "cat", "head", "tail", "grep", "egrep", "fgrep", "rg", "find", "stat",
    "file", "wc", "du", "df", "which", "type", "whereis", "id", "groups", "whoami",
    "uname", "hostname", "free", "uptime", "ss", "dig", "nslookup", "host",
    "readlink", "realpath", "tree", "printenv", "date", "diff", "cmp",
    "md5sum", "sha256sum", "lsblk", "blkid", "getent", "test", "[",
}
SAFE_SUBCOMMANDS = {
    "git":       {"status", "log", "diff", "show", "branch", "remote", "rev-parse", "ls-files", "blame"},
    "systemctl": {"status", "is-active", "is-enabled", "is-failed", "cat", "list-units", "show"},
    "docker":    {"ps", "images", "inspect", "logs", "version", "info"},
    "apt":       {"list", "show", "search", "policy"},
    "brew":      {"list", "info", "search"},
    "pip":       {"list", "show"}, "pip3": {"list", "show"},
    "npm":       {"ls", "list", "view"},
    "kubectl":   {"get", "describe", "logs"},
}
INTERACTIVE = {
    "vim", "vi", "nvim", "nano", "emacs", "less", "more", "man", "top", "htop", "ssh",
    "tmux", "screen", "mysql", "psql", "sqlite3", "ftp", "sftp", "watch", "telnet",
}
REPL_WITHOUT_ARGS = {"python", "python3", "node", "irb", "bash", "zsh", "sh"}
UNSAFE_SHELL = re.compile(r"[;&|<>`]|\$\(")
RERUN_TIMEOUT = 10

def _cmd_words(cmd):
    try:
        words = shlex.split(cmd)
    except ValueError:
        return []
    while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):  # FOO=bar cmd
        words = words[1:]
    return words

def rerun_policy(cmd):
    """'safe' (re-run silently), 'ask' (re-run only after y) or 'never' (interactive)."""
    words = _cmd_words(cmd)
    if not words:
        return "ask"
    w0 = os.path.basename(words[0])
    if (w0 in INTERACTIVE or (w0 in REPL_WITHOUT_ARGS and len(words) == 1)
            or (w0 == "tail" and any(a.startswith("-f") or a == "-F" for a in words))):
        return "never"
    if UNSAFE_SHELL.search(cmd):
        return "ask"
    if w0 in SAFE_SUBCOMMANDS:
        return "safe" if len(words) > 1 and words[1] in SAFE_SUBCOMMANDS[w0] else "ask"
    if w0 == "find" and any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir",
                                  "-fprint", "-fprint0", "-fprintf", "-fls") for a in words):
        return "ask"
    return "safe" if w0 in SAFE_RERUN else "ask"

def _clip_lines(text, head=20, tail=60):
    lines = text.splitlines()
    if len(lines) <= head + tail:
        return text, False
    return "\n".join(lines[:head] + [f"[... {len(lines) - head - tail} lines omitted ...]"] + lines[-tail:]), True

def rerun_capture(cmd):
    """Run cmd non-interactively in the user's shell; return (stdout, stderr, rc, truncated)."""
    shell = os.environ.get("SHELL") or "/bin/sh"
    if os.path.basename(shell) not in ("bash", "zsh", "sh", "dash", "ksh"):
        shell = "/bin/sh"
    # zsh reads ~/.zshenv even for -c; -f skips it so its noise can't end up
    # in the captured error.
    argv = [shell, "-f", "-c", cmd] if os.path.basename(shell) == "zsh" else [shell, "-c", cmd]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, errors="replace",
                           stdin=subprocess.DEVNULL, timeout=RERUN_TIMEOUT)
        out, err, rc = p.stdout, p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        dec = lambda b: (b.decode(errors="replace") if isinstance(b, bytes) else (b or ""))
        out, err, rc = dec(e.stdout), dec(e.stderr) + f"\n[stopped after {RERUN_TIMEOUT}s]", None
    out, t1 = _clip_lines(out)
    err, t2 = _clip_lines(err)
    return out, err, rc, (t1 or t2)

# `?` with no words: ask in the user's locale language, so the answer comes
# back in it (the model replies in the language of the question).
WHY_QUESTION = {
    "en": "Why did this command fail, and how do I fix it? Give the corrected command if there is one.",
    "pt": "Porque é que este comando falhou e como o corrijo? Indica o comando corrigido, se houver. Responde em português.",
    "es": "¿Por qué falló este comando y cómo lo soluciono? Da el comando corregido si lo hay. Responde en español.",
    "fr": "Pourquoi cette commande a-t-elle échoué et comment la corriger ? Donne la commande corrigée s'il y en a une. Réponds en français.",
    "de": "Warum ist dieser Befehl fehlgeschlagen und wie behebe ich das? Gib den korrigierten Befehl an, falls es einen gibt. Antworte auf Deutsch.",
    "it": "Perché questo comando è fallito e come lo risolvo? Indica il comando corretto, se esiste. Rispondi in italiano.",
}

def default_why_question():
    loc = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "")
    return WHY_QUESTION.get(loc[:2].lower(), WHY_QUESTION["en"])

def ask_yes(prompt, timeout=20):
    """y/N question on the terminal. False when there's no terminal."""
    if not (sys.stdout.isatty() and sys.stdin.isatty()):
        return False
    try:
        with open("/dev/tty", "r+b", buffering=0) as tty:
            try:
                key = read_key(tty, timeout, f"\r\033[K  {prompt}".encode())
            except KeyboardInterrupt:
                key = ""
            tty.write(b"\r\033[K"); tty.flush()
            return key.lower() == "y"
    except OSError:
        return False

def explain_last_command(c, cmd, rc, user_q=""):
    """`?`: explain the last command, re-running it (when safe or allowed) to see its error."""
    if not cmd:
        render_text("Nothing to explain yet. Run a command first, then type `?`.", c)
        return
    try: rc = int(rc)
    except (TypeError, ValueError): rc = None
    if rc == 0 and not user_q:
        render_text(f"The last command succeeded (exit 0):\n\n```text\n{cmd}\n```\n\n"
                    "Ask something about it with: `? <your question>`", c)
        return

    policy = rerun_policy(cmd)
    run_it = policy == "safe" or (
        policy == "ask" and ask_yes(f"{C.D}Re-run {C.Z}{cmd}{C.D} to read its error? [y/N]{C.Z}"))
    stdout = stderr = ""
    truncated, rerun_rc = False, None
    if run_it:
        sys.stderr.write(f"  {C.D}re-running: {cmd}{C.Z}\n"); sys.stderr.flush()
        stdout, stderr, rerun_rc, truncated = rerun_capture(cmd)
    elif policy == "never":
        stderr = "(interactive program: output was not captured)"
    else:
        stderr = "(output not captured: explain from the command and exit code)"

    question = user_q or default_why_question()
    if not run_it:
        # Said next to the question, or small models just ask for the error text.
        question += ("\n(This is about a shell command that failed on the user's system. Its error "
                     "output isn't available, so don't ask for it: list the most likely causes for "
                     "this command and exit code, and how to check each one.)")
    run = {"command": cmd, "exit_code": rc, "stdout": stdout, "stderr": stderr,
           "output_truncated": truncated}
    effective_q = build_contextual_question(question, run)
    if run_it and rerun_rc is not None and rerun_rc != rc:
        effective_q += f"\n(Note: when re-run just now it exited with {rerun_rc}.)\n"

    spinner = thinking(c)
    answer, ok, _, commands = answer_streaming(effective_q, c, None, "llm", spinner)
    if ok:   # so "and how do I fix it?" can follow
        save_turn(f"{user_q or default_why_question()}\n(about the command: {cmd}, exit code {rc})", answer)
    action_menu(commands, c)

# ── Follow-up questions ("e por tamanho?") ────────────────────────────
# The last few exchanges are kept in history.json. A question that reads like
# a follow-up, asked while the conversation is still open, is sent with them.
FOLLOWUP_START = re.compile(
    r"^(and|or|also|then|what about|how about|what if|instead|"
    r"e|ou|então|entao|e se|e para|e com|e como|e no|e na|"
    r"y|y si|y para|y con|"            # not "o": "o que é..." starts new questions
    r"et|et si|et pour|"
    r"und|oder|und wenn|und für|"
    r"e per)\b", re.I)
HISTORY_KEEP = 20
ANSWER_KEEP  = 600   # characters of each answer kept as context

def looks_like_followup(text):
    t = text.strip().lower()
    if not t:
        return False
    if FOLLOWUP_START.match(t):
        return True
    tokens = ContextIntentDetector._tokens(t)
    return len(tokens) <= 8 and any(tok in ContextIntentDetector.DEICTIC_TERMS for tok in tokens)

def load_history():
    try:
        with open(HISTORY_FILE) as f:
            entries = json.load(f)
        return entries if isinstance(entries, list) else []
    except Exception:
        return []

def recent_turns(c):
    """Exchanges of the conversation still open (the last one less than
    followup_window seconds ago, and each within that of the next)."""
    window = c.get("followup_window", 600)
    entries, turns, t_next = load_history(), [], time.time()
    for e in reversed(entries):
        if not window or t_next - e.get("t", 0) > window:
            break
        turns.append(e)
        t_next = e.get("t", 0)
        if len(turns) >= c.get("followup_turns", 3):
            break
    return list(reversed(turns))

def save_turn(question, answer):
    entries = load_history()
    entries.append({"t": time.time(), "q": question, "a": answer[:ANSWER_KEEP]})
    os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(HISTORY_FILE), prefix="history.")  # mode 0600
    with os.fdopen(fd, "w") as f:
        json.dump(entries[-HISTORY_KEEP:], f)
    os.replace(tmp, HISTORY_FILE)

def history_messages(turns):
    msgs = []
    for e in turns:
        msgs.append({"role": "user", "content": e.get("q", "")})
        msgs.append({"role": "assistant", "content": e.get("a", "")})
    return msgs

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
    """Answers depend on the model, the configured mode and the system, not just the question."""
    backend = "" if c.get("backend", "ollama") == "ollama" else f"{c.get('backend')}@{c.get('api_base')}|"
    return cache_key(f"{backend}{c.get('model')}|{c.get('mode', 'llm')}|{system_summary(c)}|{norm_q}")

# ── The user's system, so answers fit it ("dnf" on Fedora, "brew" on macOS)
# Only generic facts: never user names, host names or paths.
OS_RELEASE = "/etc/os-release"
PKG_BY_DISTRO = [   # matched against os-release ID and ID_LIKE
    ("debian", "apt"), ("ubuntu", "apt"), ("fedora", "dnf"), ("rhel", "dnf"),
    ("centos", "dnf"), ("arch", "pacman"), ("suse", "zypper"), ("alpine", "apk"),
    ("gentoo", "emerge"), ("void", "xbps-install"), ("nixos", "nix"),
]
PKG_MANAGERS = ["apt", "dnf", "yum", "pacman", "zypper", "apk", "emerge", "xbps-install", "nix", "brew"]

def _os_release():
    info = {}
    try:
        with open(OS_RELEASE) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k:
                    info[k] = v.strip().strip('"')
    except OSError:
        pass
    return info

def detect_system():
    """{"os", "pkg", "shell", "init", "arch"} with whatever could be detected."""
    import platform
    info = {"arch": platform.machine()}
    if sys.platform == "darwin":
        ver = platform.mac_ver()[0]
        info["os"] = f"macOS {ver}".strip()
        info["pkg"] = "brew" if shutil.which("brew") else ""
        info["init"] = "launchd"
    else:
        rel = _os_release()
        info["os"] = rel.get("PRETTY_NAME") or rel.get("NAME") or platform.system()
        try:
            with open("/proc/version") as f:
                if "microsoft" in f.read().lower():
                    info["os"] += " (WSL)"
        except OSError:
            pass
        ids = f"{rel.get('ID', '')} {rel.get('ID_LIKE', '')}".lower().split()
        pkg = next((pm for distro, pm in PKG_BY_DISTRO if distro in ids), "")
        if pkg == "dnf" and not shutil.which("dnf") and shutil.which("yum"):
            pkg = "yum"
        info["pkg"] = pkg or next((pm for pm in PKG_MANAGERS if shutil.which(pm)), "")
        info["init"] = "systemd" if os.path.isdir("/run/systemd/system") else ""
    shell = os.environ.get("TUXAIDE_SHELL") or os.path.basename(os.environ.get("SHELL", ""))
    info["shell"] = shell if shell in ("bash", "zsh", "fish", "sh", "dash", "ksh") else ""
    return info

def system_summary(c):
    """One line for the prompt, e.g. "Ubuntu 24.04 LTS, package manager apt, shell bash,
    init systemd, x86_64". Empty when system_context is off."""
    if not c.get("system_context", True):
        return ""
    i = detect_system()
    parts = [i.get("os", "")]
    if i.get("pkg"):
        parts.append(f"package manager {i['pkg']}")
    if i.get("shell"):
        parts.append(f"shell {i['shell']}")
    if i.get("init"):
        parts.append(f"init {i['init']}")
    parts.append(i.get("arch", ""))
    return ", ".join(p for p in parts if p)

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
        import chromadb  # noqa: F401  (a real import: an installed-but-broken chromadb counts as unavailable)
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
def build_prompt(passages=None, system=""):
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
        + (f"The user's system: {system}. Give commands for this system only "
           "(its package manager, its init system, its tools), unless the user asks about another one. "
           if system else
           "If a command differs by distro (Ubuntu vs Arch vs Fedora), say so. ")
        + "Maximum 3 paragraphs. Be concise."
    )
    return base

# ── Ollama query ──────────────────────────────────────────────────────
class ModelError(Exception):
    pass

OllamaError = ModelError   # older name

def chat_messages(q, c, passages=None, history=None):
    return [
        {"role": "system", "content": build_prompt(passages, system_summary(c))},
        *(history or []),
        {"role": "user",   "content": q + (
            "\n\n[Important: end your answer with exactly: Source: <man page name>]"
            if passages else ""
        )}
    ]

def stream_answer(q, c, passages=None, history=None):
    """Yield answer text chunks from the configured backend. Raises ModelError."""
    if c.get("backend") == "openai":
        return stream_openai(q, c, passages, history)
    return stream_ollama(q, c, passages, history)

def api_key(c):
    """The API key, from the environment only — never from a file."""
    return os.environ.get(c.get("api_key_env") or DEFAULTS["api_key_env"], "").strip()

def _scrub(text, c):
    key = api_key(c)
    return text.replace(key, "***") if key else text

def _api_request(c, path, payload=None):
    headers = {"Content-Type": "application/json", "User-Agent": f"tuxaide/{__version__}"}
    key = api_key(c)
    if key:
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(payload).encode() if payload is not None else None
    return urllib.request.Request(f"{c.get('api_base', '').rstrip('/')}{path}", data=data,
                                  headers=headers, method="POST" if data else "GET")

def stream_openai(q, c, passages=None, history=None):
    """Yield answer chunks from an OpenAI-compatible /chat/completions (LM Studio,
    llama.cpp server, vLLM, cloud services). Raises ModelError."""
    if not c.get("api_base"):
        raise ModelError("No API address set. Set one with: tuxaide config set api_base <url>")
    pay = {"model": c["model"], "messages": chat_messages(q, c, passages, history),
           "temperature": c.get("temperature", 0.1), "max_tokens": c.get("max_tokens", 300),
           "stream": True}
    try:
        with urllib.request.urlopen(_api_request(c, "/chat/completions", pay), timeout=60) as r:
            for ln in r:
                ln = ln.decode("utf-8", "replace").strip()
                if not ln.startswith("data:"):
                    continue
                data = ln[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    msg = json.loads(data)
                except ValueError:
                    continue
                if msg.get("error"):
                    err = msg["error"]
                    raise ModelError(_scrub(err.get("message", str(err)) if isinstance(err, dict) else str(err), c))
                for choice in msg.get("choices") or []:
                    chunk = (choice.get("delta") or {}).get("content") or ""
                    if chunk:
                        yield chunk
    except ModelError:
        raise
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            err = json.loads(e.read()).get("error", "")
            detail = err.get("message", "") if isinstance(err, dict) else str(err)
        except Exception:
            pass
        if e.code in (401, 403):
            detail = (f"The API refused the key (HTTP {e.code}). Check ${c.get('api_key_env')}."
                      + (f" {detail}" if detail else ""))
        raise ModelError(_scrub(detail or f"HTTP {e.code}", c))
    except urllib.error.URLError:
        raise ModelError(f"Can't reach the API at {c.get('api_base')}.")
    except Exception as e:
        raise ModelError(_scrub(str(e) or e.__class__.__name__, c))

def stream_ollama(q, c, passages=None, history=None):
    """Yield answer text chunks as Ollama generates them. Raises ModelError."""
    pay = {
        "model": c["model"],
        "messages": chat_messages(q, c, passages, history),
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
        raise OllamaError(f"Ollama not available. {ollama_down_hint(c)}")
    except Exception as e:
        raise OllamaError(str(e) or e.__class__.__name__)

# ── Formatting ────────────────────────────────────────────────────────
class Renderer:
    """Incremental formatter: prints the answer box line by line as text streams in.

    Code blocks are buffered until they close so the destructive-command warning
    can be shown above the block that triggered it.
    """
    def __init__(self, c, mode="llm", out=None, numbered=False, followup=False):
        self.out   = out or sys.stdout
        self.followup = followup
        self.numbered = numbered
        self.commands = []     # runnable commands found in shell code blocks
        self.color = c.get("color", True)
        self.model = c.get("model", "")
        self.where = backend_label(c)
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
        if self.followup:
            mode_label += " · follow-up"
        self._w()
        self._w(f"{C.Y}{C.B}╭{'─'*(cols-2)}╮{C.Z}" if color else f"┌{'─'*(cols-2)}┐")
        self._w(f"{C.Y}{C.B}╞═ 🐧 TuxAide {C.D}({self.where} · {self.model}{mode_label}){C.Z}{C.Y}{C.B} ═╡{C.Z}"
                if color else f"╞═ TuxAide ({self.where} · {self.model}{mode_label}) ═╡")

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

def answer_streaming(q, c, passages, mode, spinner, history=None):
    """Stream the answer to the terminal. Returns (answer, ok, ttft, commands)."""
    r = Renderer(c, mode, numbered=menu_enabled(c), followup=bool(history))
    parts, ttft, ok = [], None, True
    t0 = time.time()
    try:
        for chunk in stream_answer(q, c, passages, history):
            if ttft is None:
                ttft = time.time() - t0
                spinner.stop()
            parts.append(chunk)
            r.feed(chunk)
    except ModelError as e:
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

def staged_message():
    if os.environ.get("TUXAIDE_SHELL") == "zsh":
        return f"{C.G}✓ On your prompt{C.Z}{C.D} — edit it or press Enter to run{C.Z}"
    return f"{C.G}✓ Press ↑{C.Z}{C.D} to get it on your prompt{C.Z}"

# ── Typo suggestions for unknown commands ("gti status" → "git status") ──
# No model involved: an edit distance against the commands on PATH plus the
# shell's aliases, functions and builtins (piped in by the hook).
def edit_distance(a, b, limit):
    """Optimal string alignment distance (a swap of two neighbours counts as 1)."""
    if abs(len(a) - len(b)) > limit:
        return limit + 1
    prev2, prev = None, list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                cur[j] = min(cur[j], prev2[j - 2] + 1)
        prev2, prev = prev, cur
    return prev[-1]

def path_commands():
    names = set()
    for d in os.environ.get("PATH", "").split(os.pathsep):
        try:
            with os.scandir(d or ".") as it:
                names.update(e.name for e in it)
        except OSError:
            pass
    return names

def best_command_match(typed, names, common=()):
    """Closest command name, or None. At most 1 edit for names up to 4 letters, else 2.
    Ties go to swapped letters ("sl" → "ls"), then well-known commands, then the
    closest length."""
    limit = 1 if len(typed) <= 4 else 2
    best = None
    for n in names:
        if n == typed or n.startswith("_") or abs(len(n) - len(typed)) > limit:
            continue
        d = edit_distance(typed, n, limit)
        if d > limit:
            continue
        key = (d, sorted(n) != sorted(typed), n not in common, abs(len(n) - len(typed)), n)
        if best is None or key < best:
            best = key
    return best[-1] if best else None

SUBCOMMAND_TOOLS = set(SAFE_SUBCOMMANDS) | {"cargo", "go", "yarn", "dnf", "snap", "flatpak", "ollama"}

def suggest_fix(line, extra_names=()):
    """Corrected command line for a mistyped first word, or None."""
    stripped = line.lstrip()
    if not stripped:
        return None
    typed = stripped.split()[0]
    rest = stripped[len(typed):]
    if "=" in typed or len(typed) < 2:
        return None
    if "/" not in typed and os.path.isfile(typed) and os.access(typed, os.X_OK):
        return "./" + stripped                      # forgot the ./ for a local script
    extra = {n for n in extra_names if n and not n.startswith("_")}
    names = path_commands() | extra
    if typed in names:
        return None                                 # exists; failed for another reason
    # Missing space: "cd.." → "cd ..", "ls-la" → "ls -la", "cd/etc" → "cd /etc",
    # and a dash for a space: "git-status" → "git status"
    for k in range(len(typed) - 1, 1, -1):
        head, tail = typed[:k], typed[k:]
        if head not in names:
            continue
        if head in SUBCOMMAND_TOOLS and re.fullmatch(r"-[a-z][a-z-]*", tail):
            return f"{head} {tail[1:]}{rest}"        # "git-log" → "git log"
        if re.fullmatch(r"\.+(/.*)?|[/~].*|-[A-Za-z]{1,3}", tail):
            return f"{head} {tail}{rest}"
        if re.fullmatch(r"-[a-z][a-z-]{3,}", tail):
            return f"{head} {tail[1:]}{rest}"
    if "/" in typed:
        return None
    match = best_command_match(typed, names, CMDS | extra)
    return match + rest if match else None

def not_found_message(typed):
    if os.environ.get("TUXAIDE_SHELL") == "zsh":
        return f"zsh: command not found: {typed}"
    return f"bash: {typed}: command not found"

def mark_pending(kind):
    """Tell this shell's prompt hook what the not-found handler did (asked / suggested)."""
    pid = os.environ.get("TUXAIDE_SHELL_PID", "")
    if pid.isdigit():
        try:
            os.makedirs(PENDING_DIR, exist_ok=True)
            open(os.path.join(PENDING_DIR, f"{pid}.{kind}"), "w").close()
        except OSError:
            pass

CNF_HELPER = "/usr/lib/command-not-found"

def command_not_found_helper(typed):
    """The distro's own hint for a missing command, or "" when it has nothing
    to offer (its bare "x: command not found" adds nothing)."""
    if not typed or not os.path.exists(CNF_HELPER):
        return ""
    try:
        p = subprocess.run([CNF_HELPER, "--", typed], capture_output=True, text=True, timeout=5)
    except Exception:
        return ""
    msg = (p.stderr or p.stdout).strip()
    return msg if "install" in msg or "did you mean" in msg.lower() else ""

def suggest_main(line, extra=()):
    """Handle an unknown command that isn't a question. 0 if we printed the
    message ourselves, 1 to let the shell print its usual "command not found"."""
    c = cfg()
    if not c.get("typo_suggest", True):
        return 1
    fixed = suggest_fix(line, extra)
    typed = (line.split() or [""])[0]
    # Debian/Ubuntu know which package provides a missing command ("htop" →
    # "apt install htop"). Show that first; a typo fix, if any, comes after.
    packaged = command_not_found_helper(typed)
    if packaged:
        print(packaged, file=sys.stderr)
    if not fixed:
        return 0 if packaged else 1
    if not packaged:
        print(not_found_message(typed), file=sys.stderr)
    bold, reset = (C.B, C.Z) if c.get("color", True) and sys.stderr.isatty() else ("", "")
    hint = f"🐧 Did you mean: {bold}{fixed}{reset}"
    tty = None
    if sys.stdout.isatty() and not is_destructive(fixed):
        try:
            tty = open("/dev/tty", "r+b", buffering=0)
        except OSError:
            tty = None
    if tty is None:
        print(hint, file=sys.stderr)
        return 0
    with tty:
        try:
            key = read_key(tty, 10, f"{hint} {C.D}[Enter/y] put on prompt · other key skips{C.Z}".encode())
        except KeyboardInterrupt:
            key = ""
        tty.write(b"\r\033[K"); tty.flush()
        if key in ("\n", "\r", "y", "Y") and stage_for_prompt(fixed):
            tty.write(f"{hint}  {staged_message()}\n".encode()); tty.flush()
    return 0

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
            say(staged_message())
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

def _ollama_get(c, path, timeout=3):
    """GET an Ollama endpoint as JSON, or None when it doesn't answer."""
    try:
        with urllib.request.urlopen(f"{c['ollama_url']}{path}", timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return None

def ollama_models(c):
    """Installed models as [{"name", "size", ...}], or None when Ollama doesn't answer."""
    tags = _ollama_get(c, "/api/tags")
    return None if tags is None else tags.get("models") or []

def find_model(name, models):
    """The installed model called `name` ("llama3.2" means "llama3.2:latest"), or None."""
    for m in models:
        if m.get("name") in (name, f"{name}:latest"):
            return m
    return None

def ollama_is_local(c):
    return is_loopback(urllib.parse.urlparse(c["ollama_url"]).hostname or "")

def ollama_start_hint():
    """The command that starts Ollama on this system."""
    if sys.platform == "darwin":
        if os.path.isdir("/Applications/Ollama.app"):
            return "open -a Ollama"
        return "brew services start ollama" if shutil.which("brew") else "ollama serve"
    if os.path.isdir("/run/systemd/system"):
        return "sudo systemctl start ollama"
    return "ollama serve > /tmp/ollama.log 2>&1 &"

def ollama_install_hint():
    if sys.platform == "darwin":
        return "brew install ollama" if shutil.which("brew") else "download it from https://ollama.com/download"
    return "curl -fsSL https://ollama.com/install.sh | sh"

def ollama_down_hint(c):
    """What to try when Ollama doesn't answer, for this system and this ollama_url."""
    if not ollama_is_local(c):
        return f"Check that Ollama is running at {c['ollama_url']}"
    if not shutil.which("ollama"):
        return f"Ollama isn't installed: {ollama_install_hint()}"
    return f"Try: {ollama_start_hint()}"

def print_ollama_down(c):
    print(f"\n{C.O}⚠ Ollama not available.{C.Z}")
    print(f"{C.D}  {ollama_down_hint(c)}{C.Z}\n")

# ── Which backend answers, and is it on this machine? ─────────────────
LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1")

def backend_url(c):
    return c.get("api_base", "") if c.get("backend") == "openai" else c.get("ollama_url", DEFAULTS["ollama_url"])

def is_loopback(host):
    return host in LOCAL_HOSTS or host.startswith("127.")

def remote_host(c):
    """The first host outside this machine that will see the question, or None.
    That's the backend, plus Ollama for RAG embeddings when the backend is an API."""
    urls = [backend_url(c)]
    if c.get("backend") == "openai" and c.get("mode", "llm") in ("smart", "deep"):
        urls.append(c.get("ollama_url", DEFAULTS["ollama_url"]))
    for url in urls:
        host = urllib.parse.urlparse(url).hostname or ""
        if host and not is_loopback(host):
            return host
    return None

def is_remote(c):
    """True when questions leave this machine (another computer, or a cloud API)."""
    return remote_host(c) is not None

def backend_label(c):
    """"Ollama", "API", or "☁ remote · host" — shown on every answer."""
    name = "API" if c.get("backend") == "openai" else "Ollama"
    return f"☁ remote · {remote_host(c)}" if is_remote(c) else name

def thinking(c):
    """The spinner, started before any request: says so when the question leaves the machine."""
    return Spinner(f"☁ Asking {remote_host(c)}" if is_remote(c) else "Thinking").start()

def api_models(c):
    """Model ids the OpenAI-compatible API offers, or None when it doesn't say."""
    try:
        with urllib.request.urlopen(_api_request(c, "/models"), timeout=5) as r:
            return [m.get("id", "") for m in json.loads(r.read()).get("data", [])]
    except Exception:
        return None

def backend_ok(c):
    """Does the backend answer at all? (An HTTP error still means it's there.)"""
    if c.get("backend") != "openai":
        return ollama_ok(c)
    if not c.get("api_base"):
        return False
    try:
        with urllib.request.urlopen(_api_request(c, "/models"), timeout=5):
            return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False

def print_backend_down(c):
    if c.get("backend") != "openai":
        return print_ollama_down(c)
    print(f"\n{C.O}⚠ The model API isn't answering.{C.Z}")
    hint = (f"Check that it's running at {c['api_base']}" if c.get("api_base")
            else "Set its address with: tuxaide config set api_base <url>")
    print(f"{C.D}  {hint}{C.Z}\n")

def human_size(n):
    if n >= 1024 ** 3:
        return f"{n / 1024 ** 3:.1f} GB"
    return f"{n / 1024 ** 2:.0f} MB"

# ── help / version ────────────────────────────────────────────────────
HELP = """\
   tuxaide <question>            — ask a question
   ?  [question]                 — explain why the last command failed
   tuxaide new                   — start a new conversation (forget follow-ups)
   tuxaide history               — show your recent questions
   tuxaide on / off              — enable / disable the hook
   tuxaide status                — show status and mode
   tuxaide doctor                — check that everything works, with fixes
   tuxaide config [set KEY VAL]  — show or change settings
   tuxaide model [name]          — list models, or switch to another one
   tuxaide mode [llm|smart|deep] — switch knowledge mode
   tuxaide system                — show what TuxAide tells the model about this machine
   tuxaide run <cmd>             — run and capture shell context
   tuxaide index <cmd>           — index a man page
   tuxaide reindex               — re-index all man pages
   tuxaide cache [clear]         — show / clear cached answers
   tuxaide update [--check]      — update to the latest release
   tuxaide --timing              — show recent query performance
   tuxaide --version             — show the version"""

def print_help():
    print(f"🐧 TuxAide {__version__}")
    print(HELP)

# ── config ────────────────────────────────────────────────────────────
def set_mode(new_mode):
    """Switch llm / smart / deep (with their RAG settings). Returns an exit code."""
    new_mode = new_mode.lower()
    if new_mode == "rag": new_mode = "deep"  # backwards compat
    if new_mode not in ("llm", "smart", "deep"):
        print("Usage: tuxaide mode [llm|smart|deep]")
        return 2
    if new_mode in ("smart", "deep") and not rag_available():
        print(f"{C.O}⚠ RAG requires chromadb, which isn't installed.{C.Z}")
        print(f"{C.D}  Re-run the TuxAide installer and answer Y to Smart RAG.{C.Z}")
        return 1
    top_k = 1 if new_mode == "smart" else 3
    max_tokens = 300 if new_mode in ("llm", "smart") else 600
    save_cfg({"mode": new_mode, "rag_top_k": top_k, "max_tokens": max_tokens})
    return 0

def _config_text(v):
    return v if isinstance(v, str) else json.dumps(v)

SECRET_KEYS = ("api_key", "key", "token", "openai_api_key", "password")

def set_setting(key, raw):
    """Validate and save one setting. Returns an exit code; prints why on error."""
    if key.lower() in SECRET_KEYS:
        env = cfg().get("api_key_env", DEFAULTS["api_key_env"])
        print("TuxAide never stores API keys in its settings. Put the key in an environment\n"
              f"variable instead (e.g. in your shell rc): export {env}=…\n"
              "To use a different variable name: tuxaide config set api_key_env <NAME>")
        return 2
    if key not in SETTABLE:
        if key in DEFAULTS:
            print(f"{key} can't be changed with tuxaide config; edit {CFG_FILE}")
        else:
            print(f"Unknown setting: {key}. See the list with: tuxaide config")
        return 2
    try:
        value = SETTABLE[key](raw)
    except ValueError as e:
        print(f"Invalid value for {key}: {e}")
        return 2
    if key == "mode":
        return set_mode(value)
    save_cfg({key: value})
    return 0

def backend_notes(key):
    """After `config set` of a backend setting: what to do next, and whether answers now leave the machine."""
    c = cfg()
    if key == "backend" and c.get("backend") == "openai" and not c.get("api_base"):
        print(f"{C.D}   Now set the API address, e.g.: tuxaide config set api_base http://localhost:1234/v1{C.Z}")
    if key in ("backend", "api_base", "ollama_url", "mode") and is_remote(c):
        print(f"{C.R}☁ Questions will be sent to {remote_host(c)}, outside this machine.{C.Z}")

def config_cmd(args):
    if not args or args == ["list"]:
        c = cfg()
        print(f"🐧 Settings ({CFG_FILE.replace(os.path.expanduser('~'), '~', 1)})")
        for key in list(DEFAULTS) + sorted(set(c) - set(DEFAULTS)):
            note = "" if key in SETTABLE else "  (edit the file)"
            if key in DEFAULTS and c[key] != DEFAULTS[key]:
                note = f"  (default: {_config_text(DEFAULTS[key])})" + note
            print(f"  {key:<16} {_config_text(c[key])}" + (f"{C.D}{note}{C.Z}" if note else ""))
        print(f"{C.D}   Change one with: tuxaide config set <key> <value>{C.Z}")
        return 0
    if args[0] == "get" and len(args) == 2:
        c = cfg()
        if args[1] not in c:
            print(f"Unknown setting: {args[1]}")
            return 2
        print(_config_text(c[args[1]]))
        return 0
    if args[0] == "set" and len(args) >= 3:
        key, raw = args[1], " ".join(args[2:])
        rc = set_setting(key, raw)
        if rc == 0:
            print(f"🐧 {key} = {_config_text(cfg()[key])}")
            backend_notes(key)
        return rc
    if args[0] == "reset" and len(args) == 2 and args[1] in SETTABLE:
        key = args[1]
        if key == "mode":
            return set_mode(DEFAULTS["mode"])
        save_cfg({key: DEFAULTS[key]})
        print(f"🐧 {key} = {_config_text(DEFAULTS[key])} (default)")
        return 0
    print("Usage: tuxaide config                   — show all settings\n"
          "       tuxaide config get <key>\n"
          "       tuxaide config set <key> <value>\n"
          "       tuxaide config reset <key>       — back to the default")
    return 2

# ── model ─────────────────────────────────────────────────────────────
def pull_model(name, c):
    """Offer to download a model with `ollama pull`. True when it's there afterwards."""
    if not shutil.which("ollama"):
        print(f"{C.D}  Download it where Ollama runs: ollama pull {name}{C.Z}")
        return False
    if not ask_yes(f"Download it now with 'ollama pull {name}'? [y/N] "):
        print(f"{C.D}  Download it with: ollama pull {name}{C.Z}")
        return False
    env = {**os.environ, "OLLAMA_HOST": c["ollama_url"]}
    try:
        return subprocess.run(["ollama", "pull", name], env=env).returncode == 0
    except (OSError, KeyboardInterrupt):
        return False

def api_model_cmd(args, c):
    """`tuxaide model` with an OpenAI-compatible backend: models are the API's, never pulled."""
    offered = api_models(c)
    if not args:
        if offered is None:
            print(f"🐧 Model: {c['model']} ({backend_label(c)})")
            print(f"{C.D}   The API at {c.get('api_base') or '(not set)'} doesn't list its models.{C.Z}")
            return 0
        print(f"🐧 Models offered by {c['api_base']}:")
        for name in sorted(offered):
            print(f"  {f'{C.G}*{C.Z}' if name == c['model'] else ' '} {name}")
        print(f"{C.D}   Switch with: tuxaide model <name>{C.Z}")
        return 0
    name = args[0]
    try:
        _parse_model(name)
    except ValueError as e:
        print(f"Invalid model name: {e}")
        return 2
    if offered is not None and name not in offered:
        print(f"🐧 The API at {c['api_base']} doesn't offer {name}. See the list with: tuxaide model")
        return 1
    save_cfg({"model": name})
    print(f"🐧 Model changed to: {name}")
    return 0

def model_cmd(args):
    c = cfg()
    if c.get("backend") == "openai":
        return api_model_cmd(args, c)
    models = ollama_models(c)
    if not args:
        if models is None:
            print_ollama_down(c)
            return 1
        current = find_model(c["model"], models)
        print(f"🐧 Models in Ollama ({c['ollama_url']}):")
        for m in sorted(models, key=lambda m: m.get("name", "")):
            mark = f"{C.G}*{C.Z}" if m is current else " "
            print(f"  {mark} {m.get('name', ''):<32} {human_size(m.get('size', 0))}")
        if not models:
            print(f"  (none yet — download one with: ollama pull {DEFAULTS['model']})")
        if not current:
            print(f"{C.O}  ⚠ The configured model, {c['model']}, isn't downloaded.{C.Z}")
        print(f"{C.D}   Switch with: tuxaide model <name>{C.Z}")
        return 0
    name = args[0]
    try:
        _parse_model(name)
    except ValueError as e:
        print(f"Invalid model name: {e}")
        return 2
    if models is None:
        print(f"{C.O}⚠ Ollama isn't answering, so TuxAide couldn't check that {name} is downloaded.{C.Z}")
    elif not find_model(name, models):
        print(f"🐧 {name} isn't downloaded yet.")
        if not pull_model(name, c):
            print("   Model not changed.")
            return 1
    save_cfg({"model": name})
    print(f"🐧 Model changed to: {name}")
    return 0

# ── status ────────────────────────────────────────────────────────────
def status_cmd():
    c = cfg()
    if not c.get("enabled", True):
        print("🐧 Status: INACTIVE")
        return 0
    print(f"🐧 Status: ACTIVE | Mode: {c.get('mode', 'llm').upper()} | Model: {c['model']} ({backend_label(c)})"
          f" | Session capture: {str(bool(c.get('session_capture'))).lower()} | Session file: {SESSION_FILE}")
    if is_remote(c):
        print(f"{C.R}☁ Questions are sent to {remote_host(c)} — they are not answered on this machine.{C.Z}")
    return 0

# ── cache ─────────────────────────────────────────────────────────────
def cache_cmd(args):
    kinds = ("answers", "embeddings")
    def files(kind):
        d = os.path.join(CACHE_DIR, kind)
        return [os.path.join(d, f) for f in os.listdir(d)] if os.path.isdir(d) else []
    if not args:
        for kind in kinds:
            fs = files(kind)
            size = sum(os.path.getsize(f) for f in fs)
            print(f"🐧 {kind:<10} {len(fs):>5} entries  {human_size(size)}")
        print(f"{C.D}   Clear with: tuxaide cache clear{C.Z}")
        return 0
    if args == ["clear"]:
        counts = []
        for kind in kinds:
            counts.append(len(files(kind)))
            shutil.rmtree(os.path.join(CACHE_DIR, kind), ignore_errors=True)
        print(f"🐧 Cache cleared ({counts[0]} answers, {counts[1]} embeddings).")
        return 0
    print("Usage: tuxaide cache [clear]")
    return 2

# ── doctor ────────────────────────────────────────────────────────────
def available_memory():
    """Bytes of memory free for a model, or None when unknown."""
    try:
        if sys.platform == "darwin":
            out = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=3).stdout
            page = int(re.search(r"page size of (\d+)", out).group(1))
            pages = {k.strip(): int(v.strip(" .")) for k, v in re.findall(r"^(Pages [^:]+):\s+(\d+)", out, re.M)}
            return page * sum(pages.get(k, 0) for k in ("Pages free", "Pages inactive", "Pages speculative"))
        free = None
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    free = int(line.split()[1]) * 1024
        # In a container, the cgroup limit is what's really left.
        try:
            with open("/sys/fs/cgroup/memory.max") as f:
                limit = f.read().strip()
            with open("/sys/fs/cgroup/memory.current") as f:
                used = int(f.read())
            with open("/sys/fs/cgroup/memory.stat") as f:      # file cache can be reclaimed
                stat = dict(line.split() for line in f if line.count(" ") == 1)
            used -= int(stat.get("inactive_file", 0))
            if limit.isdigit():
                free = min(free if free is not None else int(limit), int(limit) - used)
        except (OSError, ValueError):
            pass
        return free
    except Exception:
        pass
    return None

# Smaller models to suggest, largest first (download sizes from registry.ollama.ai).
LIGHT_MODELS = [("qwen2.5:3b", 1_929_911_945), ("qwen2.5:1.5b", 986_061_405), ("qwen2.5:0.5b", 397_820_829)]

def smaller_model_hint(size):
    """What to switch to when a model of `size` bytes doesn't fit."""
    for name, s in LIGHT_MODELS:
        if s < size * 0.8:
            return f"switch to a smaller model: tuxaide model {name}"
    return "use Ollama on another computer or an API (see the README: Remote backends)"

def shell_rc_files():
    return [os.path.expanduser(f"~/{n}") for n in (".zshrc", ".bashrc")]

class Doctor:
    def __init__(self):
        self.failed = self.warned = 0

    def _line(self, mark, color, msg, fix=None):
        print(f"  {color}{mark}{C.Z} {msg}")
        if fix: print(f"    {C.D}→ {fix}{C.Z}")

    def ok(self, msg):            self._line("✓", C.G, msg)
    def info(self, msg):          self._line("·", C.D, msg)
    def warn(self, msg, fix=None):
        self.warned += 1
        self._line("⚠", C.R, msg, fix)
    def fail(self, msg, fix=None):
        self.failed += 1
        self._line("✗", C.O, msg, fix)

def c_env(raw):
    return raw.get("api_key_env") or DEFAULTS["api_key_env"]

def doctor_api(d, c):
    """doctor's checks for an OpenAI-compatible backend."""
    base, env = c.get("api_base"), c.get("api_key_env") or DEFAULTS["api_key_env"]
    if not base:
        d.fail("Backend is openai, but no API address is set",
               "tuxaide config set api_base <url>   (e.g. http://localhost:1234/v1)")
        return
    if api_key(c):
        d.ok(f"API key read from ${env}")
    elif is_remote(c):
        d.fail(f"No API key: ${env} is empty in this shell",
               f"export {env}=…   (in your shell rc; TuxAide never stores it)")
    else:
        d.info(f"No API key in ${env} (fine for local servers)")
    try:
        with urllib.request.urlopen(_api_request(c, "/models"), timeout=5) as r:
            offered = [x.get("id", "") for x in json.loads(r.read()).get("data", [])]
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            d.fail(f"The API at {base} refused the key (HTTP {e.code})", f"check ${env}")
        else:
            d.ok(f"API answering at {base} (it doesn't list models: HTTP {e.code})")
        return
    except Exception:
        d.fail(f"The API isn't answering at {base}", "check that the server is running and the address is right")
        return
    d.ok(f"API answering at {base}")
    if c["model"] in offered:
        d.ok(f"Model {c['model']} offered")
    else:
        d.fail(f"The API doesn't offer model {c['model']}", "pick one of its models: tuxaide model")

def doctor():
    """Check the whole setup; every problem comes with the command that fixes it.
    Exit code 1 when something is broken, so it also works in scripts and CI."""
    import platform
    d = Doctor()
    home = os.path.expanduser("~")
    short = lambda p: p.replace(home, "~", 1)  # noqa: E731
    sysinfo = detect_system()
    print(f"🐧 TuxAide {__version__} — doctor")
    print(f"   {sysinfo.get('os', '')} {sysinfo.get('arch', '')} · Python {platform.python_version()}"
          f" · shell {os.environ.get('TUXAIDE_SHELL') or os.path.basename(os.environ.get('SHELL', '')) or '?'}")
    print()

    # Settings
    if not os.path.exists(CFG_FILE):
        d.warn(f"No settings file ({short(CFG_FILE)}): using the defaults", "re-run the installer")
    else:
        try:
            with open(CFG_FILE) as f:
                raw = json.load(f)
            bad = []
            for key in raw:
                if key.lower() in SECRET_KEYS:
                    d.fail(f"{short(CFG_FILE)} contains \"{key}\": TuxAide never reads keys from files",
                           f"remove it and use an environment variable: export {c_env(raw)}=…")
            for key, value in raw.items():
                if key in SETTABLE and value != DEFAULTS.get(key):
                    try:
                        SETTABLE[key](value if isinstance(value, str) else json.dumps(value))
                    except ValueError as e:
                        bad.append((key, value, e))
            if bad:
                for key, value, e in bad:
                    d.warn(f"Setting {key} = {json.dumps(value)} isn't valid ({e})",
                           f"tuxaide config reset {key}")
            else:
                d.ok(f"Settings: {short(CFG_FILE)}")
        except Exception as e:
            d.fail(f"{short(CFG_FILE)} isn't valid JSON ({e})",
                   f"fix it, or start from the defaults: rm {short(CFG_FILE)} and re-run the installer")
    c = cfg()
    if not c.get("enabled", True):
        d.warn("TuxAide is turned off", "tuxaide on")

    # The model backend
    model = c["model"]
    m = None
    models = None
    if c.get("backend") == "openai":
        doctor_api(d, c)
    else:
        models = ollama_models(c)
        if models is None:
            if ollama_is_local(c) and not shutil.which("ollama"):
                d.fail("Ollama isn't installed", ollama_install_hint())
            elif ollama_is_local(c):
                d.fail(f"Ollama isn't answering at {c['ollama_url']}", ollama_start_hint())
            else:
                d.fail(f"Ollama isn't answering at {c['ollama_url']}",
                       "start it on that machine, or use the local one: "
                       f"tuxaide config set ollama_url {DEFAULTS['ollama_url']}")
        else:
            version = (_ollama_get(c, "/api/version") or {}).get("version")
            d.ok(f"Ollama {version + ' ' if version else ''}answering at {c['ollama_url']}")
            m = find_model(model, models)
            if m:
                d.ok(f"Model {model} downloaded ({human_size(m.get('size', 0))})")
            else:
                d.fail(f"Model {model} isn't downloaded",
                       f"ollama pull {model}   (or pick an installed one: tuxaide model)")
    if is_remote(c):
        d.info(f"☁ Questions are sent to {remote_host(c)}: they leave this machine")

    # Smart RAG
    mode = c.get("mode", "llm")
    if mode in ("smart", "deep"):
        embed_model = c.get("embed_model", "nomic-embed-text")
        if models is None and c.get("backend") == "openai":
            models = ollama_models(c)       # embeddings still come from Ollama
            if models is None:
                d.fail(f"Mode {mode} needs Ollama for embeddings, and it isn't answering at {c['ollama_url']}",
                       "tuxaide mode llm")
        if models is not None:
            if find_model(embed_model, models):
                d.ok(f"Embedding model {embed_model} downloaded")
            else:
                d.fail(f"Embedding model {embed_model} isn't downloaded (needed by mode {mode})",
                       f"ollama pull {embed_model}")
        if not rag_available():
            d.fail(f"Mode is {mode}, but ChromaDB isn't installed",
                   "re-run the installer and answer Y to Smart RAG, or: tuxaide mode llm")
        else:
            db_path = os.path.expanduser(c.get("rag_db_path", "~/.config/tuxaide/vectordb"))
            count = 0
            try:
                import chromadb
                if os.path.exists(db_path):
                    count = chromadb.PersistentClient(path=db_path).get_collection("tuxaide_manpages").count()
            except Exception:
                count = 0
            if count:
                d.ok(f"Man-page index: {count} passages")
            else:
                d.warn("The man-page index is empty", "tuxaide reindex")
    else:
        d.info(f"Mode {mode.upper()}: the man-page knowledge base isn't used")

    # Shell integration
    hooked = []
    for rc in shell_rc_files():
        try:
            with open(rc, errors="replace") as f:
                if "tuxaide/hook.sh" in f.read():
                    hooked.append(short(rc))
        except OSError:
            pass
    shell = os.environ.get("TUXAIDE_SHELL") or os.path.basename(os.environ.get("SHELL", "")) or "bash"
    if hooked:
        d.ok(f"Hook in {', '.join(hooked)}")
    else:
        d.fail("The hook isn't in ~/.zshrc or ~/.bashrc",
               f"echo 'source \"$HOME/.config/tuxaide/hook.sh\"  # TuxAide' >> ~/.{shell}rc")
    if not os.path.exists(HOOK_FILE):
        d.fail(f"{short(HOOK_FILE)} is missing", "re-run the installer")
    if not os.environ.get("TUXAIDE_SHELL_PID"):
        d.warn("The hook isn't loaded in this terminal", f"source ~/.{shell}rc   (or open a new terminal)")
    handler = os.environ.get("TUXAIDE_HANDLER", "")
    if handler == "ours":
        d.ok("TuxAide answers unknown commands in this shell")
    elif handler == "other":
        d.fail("Another command-not-found handler replaced TuxAide's in this shell "
               "(e.g. oh-my-zsh's command-not-found plugin)",
               f"move the TuxAide line to the end of ~/.{shell}rc")
    elif handler == "none":
        d.fail("No command-not-found handler in this shell", f"source ~/.{shell}rc")
    elif handler == "old-bash":
        d.fail(f"bash {os.environ.get('BASH_VERSION', '')} is too old for TuxAide's hook (needs bash 4+)",
               "use zsh (chsh -s /bin/zsh), or a newer bash: brew install bash")
    if BIN_DIR not in os.environ.get("PATH", "").split(os.pathsep):
        d.warn("~/.local/bin isn't on your PATH (tuxaide-index and tuxaide-uninstall need it)",
               f"echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.{shell}rc")

    # Memory for the model
    if m and m.get("size") and not is_remote(c):
        loaded = any(p.get("name") == m.get("name") for p in (_ollama_get(c, "/api/ps") or {}).get("models", []))
        free = available_memory()
        need = m["size"]
        if loaded:
            d.ok(f"Model {model} is loaded in memory")
        elif free is not None and free < need * 1.2:
            d.warn(f"Only {human_size(free)} of memory free; {model} needs about {human_size(need)}",
                   f"close some programs, or {smaller_model_hint(need)}")
        elif free is not None:
            d.ok(f"Memory: {human_size(free)} free, {model} needs about {human_size(need)}")

    print()
    if d.failed:
        print(f"{d.failed} problem(s), {d.warned} warning(s). Run the commands after → to fix them.")
        return 1
    print("All good." if not d.warned else f"No problems, {d.warned} warning(s).")
    return 0

# ── update ────────────────────────────────────────────────────────────
# Only `tuxaide update` contacts GitHub: TuxAide never checks for updates by itself.
UPDATE_FILES = [   # repository file → where the installer put it
    ("agent.py",          os.path.join(BIN_DIR, "tuxaide")),
    ("hook.sh",           HOOK_FILE),
    ("session_writer.py", os.path.expanduser("~/.config/tuxaide/session_writer.py")),
    ("uninstall.sh",      os.path.join(BIN_DIR, "tuxaide-uninstall")),
    ("indexer.py",        os.path.join(BIN_DIR, "tuxaide-index")),   # only with Smart RAG
]

def version_tuple(v):
    return tuple(int(n) for n in re.findall(r"\d+", v)[:3])

def _github(url):
    req = urllib.request.Request(url, headers={"User-Agent": f"tuxaide/{__version__}",
                                               "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()

def latest_release():
    """(tag, page URL) of the newest GitHub release."""
    api = os.environ.get("TUXAIDE_GITHUB_API", "https://api.github.com")
    repo = os.environ.get("TUXAIDE_REPO", "deltaxmodules/tuxaide")
    rel = json.loads(_github(f"{api}/repos/{repo}/releases/latest"))
    return rel["tag_name"], rel.get("html_url", f"https://github.com/{repo}/releases")

def _check_download(name, data, tag):
    """Refuse to install something that isn't what it should be."""
    text = data.decode("utf-8")
    if name.endswith(".py"):
        compile(text, name, "exec")
    if name == "agent.py":
        m = re.search(r'^__version__ = "([^"]+)"', text, re.M)
        if not m or version_tuple(m.group(1)) != version_tuple(tag):
            raise ValueError(f"agent.py says version {m.group(1) if m else '?'}, release is {tag}")
    if not text.startswith("#") or "TuxAide" not in text:
        raise ValueError("unexpected content")

def _install_file(dest, data):
    """Replace dest atomically, keeping its first line when it points the script at
    TuxAide's RAG virtualenv (the installer rewrites that shebang)."""
    mode = 0o755
    if os.path.exists(dest):
        mode = os.stat(dest).st_mode & 0o777
        with open(dest, "rb") as f:
            old_first = f.readline()
        if old_first.startswith(b"#!") and b"python" in old_first and data.startswith(b"#!/usr/bin/env python3"):
            data = old_first + data.split(b"\n", 1)[1]
    tmp = dest + ".new"
    with open(tmp, "wb") as f:
        f.write(data)
    os.chmod(tmp, mode)
    os.replace(tmp, dest)

def update_cmd(args):
    if any(a not in ("--check", "--force") for a in args):
        print("Usage: tuxaide update [--check] [--force]")
        return 2
    print(f"🐧 Checking GitHub for a newer TuxAide (you have {__version__})...")
    try:
        tag, page = latest_release()
    except Exception as e:
        print(f"{C.O}⚠ Couldn't reach GitHub: {e}{C.Z}")
        return 1
    latest = tag.lstrip("vV")
    if version_tuple(latest) <= version_tuple(__version__) and "--force" not in args:
        print(f"{C.G}✓{C.Z} You have the latest version.")
        return 0
    if "--check" in args:
        print(f"   TuxAide {latest} is available. Update with: tuxaide update")
        print(f"{C.D}   What's new: {page}{C.Z}")
        return 0
    installed = UPDATE_FILES[0][1]
    if os.path.realpath(os.path.abspath(sys.argv[0])) != os.path.realpath(installed):
        print(f"{C.O}⚠ This TuxAide ({sys.argv[0]}) isn't the installed one ({installed}).{C.Z}")
        print(f"{C.D}  If it's a git checkout, update it with: git pull{C.Z}")
        return 1
    raw = os.environ.get("TUXAIDE_GITHUB_RAW", "https://raw.githubusercontent.com")
    repo = os.environ.get("TUXAIDE_REPO", "deltaxmodules/tuxaide")
    targets = [(n, d) for n, d in UPDATE_FILES if n != "indexer.py" or os.path.exists(d)]
    downloads = {}
    for name, _ in targets:          # download and check everything before touching anything
        try:
            data = _github(f"{raw}/{repo}/{tag}/{name}")
            _check_download(name, data, tag)
        except Exception as e:
            print(f"{C.O}⚠ Couldn't download {name} from {tag}: {e}. Nothing was changed.{C.Z}")
            return 1
        downloads[name] = data
    for name, dest in targets:
        _install_file(dest, downloads[name])
    print(f"{C.G}✓{C.Z} Updated TuxAide {__version__} → {latest}. Settings, history and cache were kept.")
    print(f"{C.D}   What's new: {page}{C.Z}")
    return 0

# ── CLI ───────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("help", "--help", "-h"):
        print_help()
        return
    mode_arg = sys.argv[1]
    args = sys.argv[2:]

    if mode_arg in ("--version", "-V", "version"):
        print(f"TuxAide {__version__}")
        return
    commands = {"doctor": lambda: doctor(), "config": lambda: config_cmd(args),
                "model": lambda: model_cmd(args), "modelo": lambda: model_cmd(args),
                "cache": lambda: cache_cmd(args), "update": lambda: update_cmd(args),
                "status": lambda: status_cmd()}
    if mode_arg in commands:
        # Plain text when piped (e.g. doctor's output pasted into a bug report).
        if not sys.stdout.isatty() or not cfg().get("color", True):
            C.off()
        sys.exit(commands[mode_arg]())

    # --check: is this a question?
    if mode_arg == "--check":
        sys.exit(0 if is_q(" ".join(sys.argv[2:])) else 1)

    # --not-found LINE: the shell's command-not-found handler, in one process.
    # A question is answered (exit 0); otherwise maybe a typo suggestion
    # (exit 3, message printed); else exit 1 and the shell prints its own.
    # TUXAIDE_NAMES carries the shell's aliases, functions and builtins.
    if mode_arg == "--not-found":
        line = " ".join(sys.argv[2:])
        # "and by size" isn't a question on its own, but is right after one.
        if not is_q(line) and not (looks_like_followup(line) and recent_turns(cfg())):
            if suggest_main(line, os.environ.get("TUXAIDE_NAMES", "").split()) == 0:
                mark_pending("suggested")
                sys.exit(3)
            sys.exit(1)
        mark_pending("asked")
        sys.argv = [sys.argv[0], "--ask", line]
        mode_arg = "--ask"

    # --set KEY VALUE: persist a config value (used by the shell hook)
    if mode_arg == "--set":
        if len(sys.argv) != 4 or sys.argv[2] not in SETTABLE:
            print(f"Usage: tuxaide --set <{'|'.join(sorted(SETTABLE))}> <value>")
            sys.exit(2)
        sys.exit(set_setting(sys.argv[2], sys.argv[3]))

    # --explain-last: force contextual explanation from last shell run
    if mode_arg == "--explain-last":
        c = cfg()
        if not backend_ok(c):
            print_backend_down(c)
            return
        last_run = load_last_shell_context()
        if not last_run:
            msg = "No recent shell execution context found in this session. Run a command with: tuxaide run \"<command>\""
            render_text(msg, c, "llm")
            return
        user_q = " ".join(sys.argv[2:]).strip() or default_context_query()
        effective_q = build_contextual_question(user_q, last_run)
        spinner = thinking(c)
        _, _, _, commands = answer_streaming(effective_q, c, None, "llm", spinner)
        action_menu(commands, c)
        return

    # --why CMD RC [QUESTION...]: explain the last command (the `?` alias)
    if mode_arg == "--why":
        c = cfg()
        if not backend_ok(c):
            print_backend_down(c)
            return
        cmd = sys.argv[2] if len(sys.argv) > 2 else ""
        rc  = sys.argv[3] if len(sys.argv) > 3 else ""
        explain_last_command(c, cmd.strip(), rc, " ".join(sys.argv[4:]).strip())
        return

    # mode: switch between llm, smart, deep (rag kept as alias for deep)
    if mode_arg == "mode":
        if len(sys.argv) < 3:
            c = cfg()
            print(f"🐧 TuxAide mode: {c.get('mode','llm').upper()}")
            return
        if set_mode(sys.argv[2]) == 0:
            print(f"🐧 TuxAide mode switched to: {cfg()['mode'].upper()}")
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

    # system: what TuxAide tells the model about this machine
    if mode_arg == "system":
        c = cfg()
        summary = system_summary(c)
        if summary:
            print(f"🐧 Sent with each question: {summary}")
            print(f"{C.D}   Turn off with: tuxaide --set system_context false{C.Z}")
        else:
            print("🐧 System context is off (tuxaide --set system_context true to enable).")
        return

    # new: forget the conversation (follow-ups start from scratch)
    if mode_arg == "new":
        try:
            os.remove(HISTORY_FILE)
        except FileNotFoundError:
            pass
        print("🐧 New conversation.")
        return

    # history: the last questions asked
    if mode_arg == "history":
        entries = load_history()
        if not entries:
            print("No questions yet.")
            return
        for e in entries:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(e.get("t", 0)))
            print(f"  {C.D}{when}{C.Z}  {e.get('q', '').splitlines()[0] if e.get('q') else ''}")
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
    if not backend_ok(c):
        print_backend_down(c)
        sys.exit(0)

    # "why did this fail?" right after a failed command → same as `?`
    shell_cmd = os.environ.get("TUXAIDE_LAST_CMD", "").strip()
    shell_rc  = os.environ.get("TUXAIDE_LAST_RC", "")
    if (shell_cmd and shell_rc not in ("", "0")
            and not re.match(r"(tuxaide|tux)\s+run\b", shell_cmd)
            and ContextIntentDetector.looks_like_context_followup(q)):
        explain_last_command(c, shell_cmd, shell_rc, q)
        return

    effective_q = q
    last_run = load_last_shell_context() if c.get("session_capture", False) else None
    context_query = ContextIntentDetector.should_explain_last(
        q,
        c.get("session_capture", False),
        bool(last_run),
    )
    if context_query and last_run:
        effective_q = build_contextual_question(q, last_run)

    # A follow-up in an open conversation is sent with the previous exchanges.
    turns = [] if context_query or not looks_like_followup(q) else recent_turns(c)
    history = history_messages(turns)

    norm_q    = normalize(effective_q if context_query else q)
    ans_key   = answer_cache_key(norm_q, c)
    t_embed   = 0.0
    t_rag     = 0.0
    t_llm     = 0.0

    # ── Answer cache lookup ───────────────────────────────────────────
    cached_answer = None if context_query or history else cache_get(
        "answers", ans_key, c.get("cache_ttl_days", 30))
    if cached_answer and cached_answer.get("answer"):
        answer    = cached_answer["answer"]
        act_mode  = cached_answer.get("mode", "llm")
        perf_log(norm_q, act_mode + "+cache", 0, 0, 0, True)
        save_turn(q, answer)
        action_menu(render_text(answer, c, act_mode), c)
        return

    # ── Determine mode and whether to use RAG ────────────────────────
    current_mode = c.get("mode", "llm")
    passages     = []
    detected_cmd = None
    act_mode     = "llm"

    spinner = thinking(c)

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
        effective_q, c, passages if passages else None, act_mode, spinner, history)
    t_llm = time.time() - t_llm_start

    # ── Cache the answer (never errors, partial answers or follow-ups) ─
    if ok and not context_query and not history:
        cache_set("answers", ans_key, {"answer": answer, "mode": act_mode})
    if ok:
        save_turn(q, answer)

    perf_log(norm_q, act_mode, t_embed, t_rag, t_llm, False, ttft)

    action_menu(commands, c)

if __name__ == "__main__": main()
