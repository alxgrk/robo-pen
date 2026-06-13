#!/usr/bin/env bash
# /usr/local/bin/ccr-init.sh
#
# Runs as PID 1 (root, CAP_SYS_ADMIN) at container start.
# Launches ccr-fuse to overlay-mount the host workspace bind onto /workspace.
#
# Layout:
#   /workspace-real           bind from host (where ccr-fuse reads pass-through paths)
#   /var/lib/ccr/overlay      container-local writable store for paths in .ccrignore
#   /workspace                FUSE mount that user/Claude sees
#
# .ccrignore (in /workspace-real, one path per line):
#   - Listed paths: host content invisible; container's reads/writes go to overlay
#   - Unlisted paths: passthrough to host
#
# The container exits if ccr-fuse exits (so failures are visible).
set +e

REAL=/workspace-real
MNT=/workspace
OVERLAY=/var/lib/ccr/overlay
RULES="$REAL/.ccrignore"

if [ ! -d "$REAL" ]; then
    echo "ccr-init: $REAL does not exist; nothing to mount" >&2
    exec sleep infinity
fi

mkdir -p "$MNT" "$OVERLAY"
chown coder:coder "$OVERLAY"

# If already mounted (e.g., container restart with stale state), unmount first.
if mountpoint -q "$MNT"; then
    fusermount3 -u "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null
fi

RULES_FLAG=""
if [ -f "$RULES" ]; then
    RULES_FLAG="--rules $RULES"
    echo "ccr-init: using rules from $RULES" >&2
else
    echo "ccr-init: no .ccrignore in workspace; pure passthrough" >&2
fi

# Launch ccr-fuse in the foreground so the container exits if it dies.
echo "ccr-init: launching ccr-fuse" >&2
exec /usr/local/bin/ccr-fuse \
    --backing "$REAL" \
    --overlay "$OVERLAY" \
    --mount "$MNT" \
    $RULES_FLAG
