#!/usr/bin/env bash
# Installs the Claude Code CLI. Runs as the configured container user during
# overlay build. Must be idempotent and rely on user-writable paths only — no
# sudo is available.
set -euo pipefail

curl -fsSL https://claude.ai/install.sh | bash
