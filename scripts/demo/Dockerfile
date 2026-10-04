# The demo video's recorder: VHS plus what TuxAide needs (see docs/video/PLANO.md).
FROM ghcr.io/charmbracelet/vhs:latest
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends zsh git socat curl \
    && rm -rf /var/lib/apt/lists/*
# UTF-8, or zsh shows accents and symbols (—, ·, ç) as bytes.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY entrypoint.sh /usr/local/bin/demo-entrypoint
ENTRYPOINT ["/usr/local/bin/demo-entrypoint"]
