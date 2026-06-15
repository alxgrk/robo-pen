# claude-container — default per-project image used when a workspace has no
# `.ccr/config.yaml` or `.ccr/Dockerfile`. Adds the standard Claude-friendly
# toolchain (Node, Python+uv, R, DuckDB, just, build-essential, Claude CLI)
# on top of ccr-base. Build it with `ccr build` after `ccr build-base`.

FROM ccr-base

USER root

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages (tools the default user-image expects) ──────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-utils git curl \
        build-essential \
        python3 python3-dev python3-venv \
        r-base \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 via NodeSource ────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── DuckDB CLI (architecture-aware) ─────────────────────────────
ARG DUCKDB_VERSION=1.4.3
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${ARCH}.zip" -o /tmp/duckdb.zip \
    && apt-get update && apt-get install -y --no-install-recommends unzip \
    && unzip /tmp/duckdb.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/duckdb \
    && rm /tmp/duckdb.zip \
    && apt-get purge -y unzip && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# ── just ─────────────────────────────────────────────────────────
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# ── ccr container instructions (agent-agnostic + image toolchain) ──
# 00-container.md describes the ccr container model (workspace, shadow, no-sudo)
# and is image-agnostic. 10-toolchain.md describes what's installed in *this*
# image (the default robo-pen-default toolchain). At the end of the build we
# concatenate /etc/ccr/instructions/*.md into the agent's instruction file.
COPY config/00-container.md /etc/ccr/instructions/00-container.md
COPY config/10-toolchain-default.md /etc/ccr/instructions/10-toolchain.md

# ── claude-code profile (agent-specific bits) ─────────────────────
RUN mkdir -p /home/coder/.claude && chown -R coder:coder /home/coder/.claude
COPY --chown=coder:coder agent.profiles/claude-code/settings/settings.json /home/coder/.claude/settings.json
COPY agent.profiles/claude-code/instructions.md /etc/ccr/instructions/20-agent.md
COPY agent.profiles/claude-code/run.sh /usr/local/lib/ccr/run.sh
COPY agent.profiles/claude-code/run-gated.sh /usr/local/lib/ccr/run-gated.sh
COPY agent.profiles/claude-code/login.sh /usr/local/lib/ccr/login.sh
RUN chmod 0755 /usr/local/lib/ccr/run.sh /usr/local/lib/ccr/run-gated.sh /usr/local/lib/ccr/login.sh

USER coder
WORKDIR /home/coder

# ── uv (Python package manager) ─────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/coder/.local/bin:${PATH}"

# ── Claude Code installer (from agent.profiles/claude-code/install.sh) ──
COPY --chown=coder:coder agent.profiles/claude-code/install.sh /tmp/agent-install.sh
RUN bash /tmp/agent-install.sh && rm /tmp/agent-install.sh

# ── Compose CLAUDE.md from /etc/ccr/instructions/*.md (lexical order, ──
# ── with a blank line between fragments).                              ──
USER root
RUN awk 'FNR==1 && NR>1 {print ""} {print}' /etc/ccr/instructions/*.md \
        > /home/coder/.claude/CLAUDE.md \
    && chown coder:coder /home/coder/.claude/CLAUDE.md
USER coder

WORKDIR /workspace
