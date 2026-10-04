# Settings

Settings live in `~/.config/tuxaide/config.json`. Change them with `tuxaide config set <key> <value>` — values are checked, and the change applies in the current terminal too — or go back with `tuxaide config reset <key>`. Reinstalling or updating keeps your values.

## Answers

| Key | Default | Meaning |
| --- | --- | --- |
| `model` | picked for your RAM | The model that answers ([models](/guide/models-and-memory)) |
| `mode` | `llm` | `llm`, `smart` or `deep` ([Smart RAG](/guide/smart-rag)) |
| `temperature` | `0.1` | 0–2; low keeps answers focused |
| `action_menu` | `true` | After an answer, offer to put a command on the prompt or copy it |
| `cache_ttl_days` | `30` | Cached answers older than this are ignored (0–3650) |
| `color` | `true` | Colours in answers |
| `system_context` | `true` | Tell the model your OS, package manager, shell and init system |
| `followup_window` | `600` | Seconds a conversation stays open for follow-ups (`0` turns them off) |
| `followup_turns` | `3` | Previous exchanges sent with a follow-up (0–10) |

## The shell

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Set by `tuxaide on` / `off` |
| `failure_hint` | `true` | After a failed command, show “type ? to ask TuxAide why” |
| `typo_suggest` | `true` | Suggest fixes for mistyped commands |
| `session_capture` | `true` | Keep the output of `tuxaide run` for the next question |

## Ollama and backends

| Key | Default | Meaning |
| --- | --- | --- |
| `backend` | `ollama` | `ollama`, or `openai` for an OpenAI-compatible API ([remote backends](/guide/remote-backends)) |
| `ollama_url` | `http://localhost:11434` | Where Ollama runs |
| `api_base` | — | Backend `openai`: the API address, e.g. `http://localhost:1234/v1` |
| `api_key_env` | `OPENAI_API_KEY` | Backend `openai`: the environment variable holding the key (the key itself is never stored) |
| `prewarm` | `once` (`off` under 8 GB) | Load the model when a terminal opens: `off`, `once` (at most every 10 min), `always` |
| `keep_alive` | `10m` | How long Ollama keeps the model in memory after a question (`30s`, `1h`, `0`, `-1` = forever) |
| `embed_model` | `nomic-embed-text` | Embedding model for Smart RAG |
| `rag_timeout` | `8` | Seconds to wait for the man-page lookup before answering without it (1–120) |

`max_tokens`, `rag_top_k` and `rag_db_path` are set by `tuxaide mode`; edit the file to change them by hand.
