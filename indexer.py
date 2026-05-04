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
