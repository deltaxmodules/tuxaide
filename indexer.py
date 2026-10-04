#!/usr/bin/env python3
"""TuxAide — Man page indexer for Smart RAG mode."""
import os, sys, json, re, subprocess, urllib.request, urllib.error

try:
    import chromadb
except ImportError:
    # Homebrew / AUR run this with the system Python; chromadb lives in TuxAide's venv.
    _venv = os.path.expanduser("~/.local/share/tuxaide/venv/bin/python")
    if os.access(_venv, os.X_OK) and not os.environ.get("TUXAIDE_IN_VENV"):
        os.environ["TUXAIDE_IN_VENV"] = "1"
        os.execv(_venv, [_venv, os.path.realpath(__file__), *sys.argv[1:]])
    print("Error: chromadb not installed. Enable Smart RAG with: tuxaide setup --rag")
    sys.exit(1)

CFG_FILE = os.path.expanduser("~/.config/tuxaide/config.json")
DB_PATH  = os.path.expanduser("~/.config/tuxaide/vectordb")
PID_FILE = os.path.expanduser("~/.config/tuxaide/index.pid")   # written by `tuxaide setup`
BATCH    = 32   # chunks embedded per request

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
TOP_COMMANDS = list(dict.fromkeys(TOP_COMMANDS))  # drop duplicates, keep order

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

def man_section(cmd):
    """Section of the man page that `man cmd` shows, e.g. '1' or '8'. Defaults to '1'."""
    try:
        path = subprocess.run(["man", "-w", cmd], capture_output=True, text=True).stdout.strip()
        m = re.search(r"\.(\d\w*)(?:\.(?:gz|bz2|xz|z|Z))?$", path.splitlines()[0]) if path else None
        return m.group(1) if m else "1"
    except Exception:
        return "1"

def chunk_text(text, cmd, chunk_size=200, overlap=40, section="1"):
    """Split text into overlapping chunks (smaller = faster retrieval)."""
    words = text.split()
    chunks = []
    i = 0
    while i < len(words):
        chunk_words = words[i:i+chunk_size]
        chunks.append({
            "text": " ".join(chunk_words),
            "source": f"man {cmd}({section})",
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

_BATCH_API = True

def embed_batch(texts, model, url):
    """Embed many texts in one request (/api/embed); fall back to one request each
    on Ollama versions without the batch endpoint."""
    global _BATCH_API
    if _BATCH_API:
        req = urllib.request.Request(
            f"{url}/api/embed",
            data=json.dumps({"model": model, "input": texts}).encode(),
            headers={"Content-Type": "application/json"}, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read())["embeddings"]
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            _BATCH_API = False
    return [embed_text(t, model, url) for t in texts]

def index_command(cmd, col, cfg, verbose=True, prefix=""):
    text = get_man_text(cmd)
    if not text:
        if verbose: print(f"  {prefix}⚠  No man page: {cmd}")
        return 0
    chunks = chunk_text(text, cmd, section=man_section(cmd))
    ids = [f"{cmd}_{i}" for i in range(len(chunks))]
    try:
        existing = set(col.get(ids=ids)["ids"])
    except Exception:
        existing = set()
    todo = [(cid, ch) for cid, ch in zip(ids, chunks) if cid not in existing]
    model = cfg.get("embed_model", "nomic-embed-text")
    url = cfg.get("ollama_url", "http://localhost:11434")
    for b in range(0, len(todo), BATCH):
        batch = todo[b:b + BATCH]
        try:
            vecs = embed_batch([ch["text"] for _, ch in batch], model, url)
            col.add(
                ids=[cid for cid, _ in batch],
                embeddings=vecs,
                documents=[ch["text"] for _, ch in batch],
                metadatas=[{"source": ch["source"], "command": cmd, "chunk": ch["chunk_idx"]}
                           for _, ch in batch]
            )
        except Exception as e:
            if verbose: print(f"  {prefix}✗  Error embedding {cmd}: {e}")
            return 0
    if verbose:
        note = f", {len(existing)} already indexed" if existing else ""
        print(f"  {prefix}✓  {cmd} ({len(chunks)} chunks{note})")
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
    width = len(str(len(TOP_COMMANDS)))
    for i, cmd in enumerate(TOP_COMMANDS, 1):
        n = index_command(cmd, col, cfg, prefix=f"[{i:>{width}}/{len(TOP_COMMANDS)}] ")
        total += n
    print()
    print(f"✓ Indexing complete — {total} total chunks stored")
    print("  Smart RAG uses it now (if it's off: tuxaide mode smart)")
    try:   # a background run started by `tuxaide setup` is over
        with open(PID_FILE) as f:
            if f.read().strip() == str(os.getpid()):
                os.remove(PID_FILE)
    except OSError:
        pass

if __name__ == "__main__": main()
