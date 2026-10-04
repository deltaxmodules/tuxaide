#!/usr/bin/env bash
# Generate the demo video (site/public/video/tuxaide-demo.mp4 + .jpg cover) and
# the README GIF (site/public/img/tuxaide-demo.gif) — see docs/video/PLANO.md.
# Needs Docker and Ollama running on this machine with the demo model:
#   scripts/demo-video.sh [video|gif]      (both by default)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="${DEMO_MODEL:-qwen2.5-coder:7b}"
curl -fs http://localhost:11434/api/tags | grep -q "\"${model}\"" \
    || { echo "Ollama must be running here with ${model} (ollama pull ${model})" >&2; exit 1; }

docker build -q -t tuxaide-demo "$repo/scripts/demo" >/dev/null
mkdir -p "$repo/site/public/video" "$repo/site/public/img"
record() {
    docker run --rm --add-host=host.docker.internal:host-gateway -e DEMO_MODEL="$model" \
        -v "$repo":/repo tuxaide-demo "scripts/demo/$1"
}
what="${1:-all}"
if [[ "$what" == all || "$what" == video ]]; then
    record tuxaide.tape
    # Cover: a frame from scene 1, once the answer is on screen.
    ffmpeg -loglevel error -y -ss 12 -i "$repo/site/public/video/tuxaide-demo.mp4" -frames:v 1 -q:v 3 \
        "$repo/site/public/video/tuxaide-demo.jpg"
fi
[[ "$what" == all || "$what" == gif ]] && record readme.tape
ls -lh "$repo"/site/public/video/tuxaide-demo.* "$repo"/site/public/img/tuxaide-demo.gif 2>/dev/null
