# Models and memory

TuxAide runs a model locally through Ollama. The installer (and `tuxaide setup`) picks the one that fits your RAM:

| RAM | Model | Download | Answers |
| --- | --- | --- | --- |
| 8 GB or more | `qwen2.5-coder:7b` | 4.7 GB | Best |
| 5–8 GB | `qwen2.5:3b` | 1.9 GB | Good |
| 3–5 GB | `qwen2.5:1.5b` | 986 MB | Simpler, but usable |
| under 3 GB | `qwen2.5:0.5b`, or a [remote backend](/guide/remote-backends) | 398 MB | Basic |

Download sizes are from the Ollama registry. In a container or VM with a memory limit, the limit counts, not the host's RAM. Smart RAG needs 5 GB or more.

## Switch models

```bash
tuxaide model                 # the models in Ollama, the current one marked
tuxaide model llama3.2        # switch; offers `ollama pull` if it isn't downloaded
```

Any model in the [Ollama library](https://ollama.com/library) works. Coding-tuned models give the best commands.

## Speed

- **The first words** appear as soon as the model writes them — answers stream in.
- **Pre-loading**: when a terminal opens, TuxAide asks Ollama to load the model (`prewarm`: `once` per 10 minutes by default, `off` on machines under 8 GB, or `always`). `keep_alive` (10 min) is how long Ollama keeps it in memory after a question.
- **Repeated questions** come from the cache instantly.
- A GPU makes answers much faster but isn't needed.

`tuxaide --timing` shows how long recent questions took (from `~/.config/tuxaide/logs/perf.log`). `tuxaide doctor` warns when free memory is too low for the model and suggests a smaller one.
