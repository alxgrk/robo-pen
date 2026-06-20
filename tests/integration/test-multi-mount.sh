#!/usr/bin/env bash
# Property: rp-fuse mounts multiple FUSE trees in one process when init.sh
# is given a multi-value RP_WORKSPACE. Each workspace gets its own shadow
# store under /var/lib/rp/shadow/<sha8>/.
#
# Driven via `container create` directly so we exercise the multi-bind +
# multi-RP_WORKSPACE path without depending on the rp CLI (the wrapper
# does not expose this yet — that comes in a later phase).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

ws_a=$(mk_probe multi-a)
ws_b=$(mk_probe multi-b)

cd "$ws_a"; "$RP" init >/dev/null
cd "$ws_b"; "$RP" init >/dev/null

echo "from-a" > "$ws_a/marker.txt"
echo "from-b" > "$ws_b/marker.txt"

# Build image once. We piggy-back on ws_a (the project-image build needs
# a workspace dir to read .rp/config.yaml + agent profile from); both
# workspaces share that image.
cont=rp-claude-code-multi-mount
container delete --force "$cont" >/dev/null 2>&1 || true
container image rm -f "$cont:latest-rp" >/dev/null 2>&1 || true
remember_container "$cont"

image_tag=$("$REPO_DIR/scripts/build-project-image.sh" "$ws_a" "$cont" 2>/dev/null | tail -1)
[ -n "$image_tag" ] || fail "build-project-image.sh did not emit a tag"

# Multi-bind + multi-value RP_WORKSPACE. The wrapper script would do this
# translation; here we wire it by hand.
container create \
    --name "$cont" \
    --cap-add SYS_ADMIN \
    -l "rp.host_path=$ws_a" \
    -l "rp.agent=claude-code" \
    -l "rp.managed=true" \
    -e "RP_WORKSPACE=$ws_a $ws_b" \
    -v "$ws_a:$ws_a" \
    -v "$ws_b:$ws_b" \
    "$image_tag" >/dev/null
container start "$cont" >/dev/null

# Wait for both FUSE mounts to appear.
n=0
for _ in $(seq 1 30); do
    n=$(container exec -u 0 "$cont" sh -c "awk '\$3 ~ /^fuse/' /proc/mounts | wc -l" 2>/dev/null || echo 0)
    [ "$n" -ge 2 ] && break
    sleep 0.2
done
[ "$n" -ge 2 ] || fail "expected 2 fuse mounts at $ws_a + $ws_b, got $n"

# Each marker is visible through its OWN workspace (the FUSE layer reads
# from the captured fd, which points at the right host bind).
got_a=$(container exec -u coder --workdir "$ws_a" "$cont" cat marker.txt 2>&1)
assert_eq "$got_a" "from-a" "ws_a marker visible through workspace A"

got_b=$(container exec -u coder --workdir "$ws_b" "$cont" cat marker.txt 2>&1)
assert_eq "$got_b" "from-b" "ws_b marker visible through workspace B"

# Per-workspace shadow stores — each workspace got its own subdir.
shadow_count=$(container exec -u 0 "$cont" sh -c 'ls /var/lib/rp/shadow 2>/dev/null | wc -l')
[ "$shadow_count" -ge 2 ] \
    || fail "expected >=2 per-workspace shadow subdirs, got $shadow_count"

echo "OK test-multi-mount"
