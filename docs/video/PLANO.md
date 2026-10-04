# Vídeo de demonstração — plano e guião

**Estado:** decisões tomadas pelo assistente com a autorização do PO (2026-10-04: «avance até onde puder, eu aceito todas as suas decisões»). Gerado com `scripts/demo-video.sh`.

Modelo: o vídeo do codeTAC (`codetac2/docs/video/PLANO.md`) — gerado por script, sem voz, com legendas, refeito com um comando a cada versão.

## Decisões

| # | Pergunta | Decisão |
|---|---|---|
| 1 | Ferramenta | **[VHS](https://github.com/charmbracelet/vhs)** num contentor Docker (imagem oficial + zsh, git, socat). Grava um terminal real a partir de ficheiros `.tape` no repositório (`scripts/demo/`). Nada a instalar no computador de quem gera o vídeo além do Docker. |
| 2 | Um vídeo ou vários? | **Um vídeo de ~1min30** com 5 cenas, para o manual; **um GIF curto** para o README (pergunta → resposta → comando no prompt → comando falha → `?` explica). |
| 3 | Narração | **Sem voz, sem música.** Cada cena começa com uma legenda no próprio terminal (uma linha a cor no topo), em inglês como o produto. |
| 4 | Modelo | **Real**: `qwen2.5-coder:7b` no Ollama do computador que grava, visto de dentro do contentor como `localhost:11434` (um `socat`), por isso o cabeçalho mostra «Ollama» e não «☁ remote» — é a mesma máquina. As respostas são do modelo, por isso mudam um pouco entre gravações; as cenas esperam pelo texto (`Wait`), não por tempos fixos. |
| 5 | Ambiente | O TuxAide do repositório instalado como o instalador o faz (`~/.local/bin`, `~/.config/tuxaide`, `tuxaide setup`), uma pasta `~/demo` com ficheiros de exemplo e um repositório git. Nada privado aparece: o prompt mostra só `~/demo`. |
| 6 | Formato | Vídeo 1280×800 MP4 (H.264) com capa `.jpg`; GIF 1000×600. |

## Guião (`scripts/demo/tuxaide.tape`)

| # | Legenda | O que acontece |
|---|---|---|
| 0 | **TuxAide — ask your terminal in plain English** | título |
| 1 | **1. Type a question, as if it were a command. Press 1: the command lands on your prompt.** | `how do I find files bigger than 100MB in this folder` → resposta em streaming com comandos numerados → `1` → o comando `find` no prompt → Enter encontra o `.iso` de 150 MB (ficheiro esparso) |
| 2 | **2. Follow-ups, in any language — destructive commands come with a warning** | `and how do I delete them?` (marcado «follow-up», com o aviso ⚠ antes do `-delete`) → `como vejo o espaço livre no disco` (resposta em português) |
| 3 | **3. A command failed? Type ?** | `tar -xzf backup.tar` (um tar sem gzip) → erro + 💡 → `?` → pergunta se pode voltar a correr (`tar` não é só de leitura) → `y` → explicação |
| 4 | **4. Typos are fixed instantly, without the model** | `gti status` → «Did you mean: git status» → Enter → no prompt → Enter |
| 5 | **5. Something off? tuxaide doctor** | `tuxaide doctor` |
| 6 | **Local · free · open source** + instalação e endereço do manual | cartão final |

## GIF do README (`scripts/demo/readme.tape`)

Cenas 1 e 3 sem legendas: pergunta → streaming → `1` → no prompt → Enter; `ls /var/log/nginx` → `?` → explicação. O P11 pedia 15 s; com o modelo real a responder ao seu ritmo fica um pouco acima (a velocidade não é acelerada, para não enganar).

## Cuidados

- Nada sai do computador: o modelo é o Ollama local.
- Sem caminhos, nomes de utilizador ou máquina: o prompt é `~/demo $`.
- Se um texto do produto mudar (por exemplo «put on prompt»), o `Wait` falha e o vídeo não é gerado, em vez de sair errado.

## Ajustes ao gravar (2026-10-04)

- O VHS arranca o zsh sem ler o `~/.zshrc`: cada tape começa por carregá-lo, escondido.
- A primeira pergunta passou de «list hidden files sorted by size» para «find files bigger than 100MB»: com a primeira, o modelo respondeu `du -ah . | grep '^-'`, que não faz o que se pediu. Uma demonstração não pode mostrar uma resposta errada.
- Cena 3: `ls /var/log/nginx` deu uma explicação fraca («crie a pasta»); passou para `tar -xzf` num tar sem gzip, que também mostra a pergunta antes de voltar a correr um comando que não é só de leitura. O GIF do README mantém o `ls` (curto, sem pergunta).
- Na primeira gravação o modelo respondeu com `find /path/to/search …` (um caminho de exemplo): a pergunta passou a dizer «in this folder».
- O follow-up «and how do I delete them?» revelou um bug: `find -exec rm`, `find -delete` e `xargs rm` não tinham o aviso de comando destrutivo. Corrigido num commit próprio.
- O contentor precisava de `LANG=C.UTF-8`: sem isso, o zsh mostrava os acentos e os símbolos como bytes.
