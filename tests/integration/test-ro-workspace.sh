#!/usr/bin/env bash
# Property: a workspace tagged `:ro` in RP_WORKSPACE is mounted read-only.
# Writes return EROFS from the kernel; the agent sees a standard
# "Read-only file system" error.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

ws=$(mk_probe rows)
cd "$ws"
"$RP" init >/dev/null

cont=rp-claude-code-rows
container delete --force "$cont" >/dev/null 2>&1 || true
container image rm -f "$cont:latest-rp" >/dev/null 2>&1 || true
remember_container "$cont"

image_tag=$("$REPO_DIR/scripts/build-project-image.sh" "$ws" "$cont" 2>/dev/null | tail -1)
[ -n "$image_tag" ] || fail "build-project-image.sh did not emit a tag"

container create \
    --name "$cont" \
    --cap-add SYS_ADMIN \
    -l "rp.host_path=$ws" \
    -l "rp.agent=claude-code" \
    -l "rp.managed=true" \
    -e "RP_WORKSPACE=$ws:ro" \
    -v "$ws:$ws" \
    "$image_tag" >/dev/null
container start "$cont" >/dev/null

# Wait for the fuse mount.
for _ in $(seq 1 30); do
    container exec -u 0 "$cont" awk -v m="$ws" '$2==m && $3 ~ /^fuse/' /proc/mounts 2>/dev/null | grep -q . && break
    sleep 0.2
done

# Fuse mount line should mention 'ro' in the options (field 4 is the
# comma-separated mount options).
line=$(container exec -u 0 "$cont" awk -v m="$ws" '$2==m && $3 ~ /^fuse/' /proc/mounts 2>&1)
opts=$(awk '{print $4}' <<<"$line")
echo ",$opts," | grep -q ',ro,' || fail "fuse mount not flagged ro: $line"

# Writing fails. Capture stderr — any of EROFS / "Read-only file system" /
# operation-not-permitted is fine (kernels phrase it differently across
# variants).
out=$(container exec -u coder --workdir "$ws" "$cont" sh -c 'touch newfile.txt 2>&1; echo EXIT=$?' 2>&1)
echo "$out" | grep -q 'EXIT=0' && fail "expected touch to fail on ro mount, but it succeeded: $out"
echo "$out" | grep -qi 'read[ -]only\|EROFS' || fail "expected read-only error, got: $out"

# Reading still works.
reads=$(container exec -u coder --workdir "$ws" "$cont" ls -A 2>&1)
echo "$reads" | grep -q '\.rp' || fail "expected .rp/ visible on ro mount, got: $reads"

echo "OK test-ro-workspace"
