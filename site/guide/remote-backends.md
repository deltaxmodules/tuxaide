# Remote backends

TuxAide is **local by default** and stays that way unless you change it. If your machine is too small for a local model, or you already run a model server, you can point TuxAide at it.

**Whenever a question leaves your computer, you can see it**: `☁ Asking <host>` while it waits, `☁ remote · <host>` in every answer header, and a warning in `tuxaide status` and `tuxaide doctor`. Pre-loading the model at shell start only ever talks to a local Ollama.

## Ollama on another computer

```bash
# on the other computer (it must listen on the network):
OLLAMA_HOST=0.0.0.0 ollama serve

# on this one:
tuxaide config set ollama_url http://192.168.1.10:11434
tuxaide model                 # pick one of its models
```

## Any OpenAI-compatible API

LM Studio, llama.cpp server, vLLM, or a cloud service — anything with `/v1/chat/completions`:

```bash
tuxaide config set backend openai
tuxaide config set api_base http://localhost:1234/v1     # e.g. LM Studio on this machine: still local
tuxaide model                                           # the models the API offers
```

### API keys

A service that needs a key reads it from an **environment variable** — TuxAide never writes it to any file, refuses `tuxaide config set api_key`, and `tuxaide doctor` flags a key found in `config.json`:

```bash
echo 'export OPENAI_API_KEY=sk-…' >> ~/.zshrc
tuxaide config set api_key_env MY_KEY_VAR     # if your variable has another name
```

Error messages never show the key.

## Small machines

On a machine with less than 3 GB of RAM, the installer offers three choices: a tiny local model (`qwen2.5:0.5b`, 398 MB), Ollama on another computer, or an OpenAI-compatible API. Remote is never chosen for you.

## Smart RAG with a remote backend

Smart RAG computes embeddings with Ollama (`ollama_url`). With the `openai` backend it still uses `ollama_url` for them — if that is remote too, the ☁ indicator says so.

## Back to local

```bash
tuxaide config reset backend
tuxaide config reset ollama_url
```
