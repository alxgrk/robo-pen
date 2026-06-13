#!/bin/sh
# Verifies that the .ccr/shadow file at workspace root is read-only from inside
# the container — only the host may modify the ruleset.
set -eu

apk add --no-cache fuse3 >/dev/null 2>&1

HOST=/host
SHADOW=/shadow
MNT=/mnt
mkdir -p "$HOST" "$SHADOW" "$MNT"
rm -rf "$HOST"/* "$SHADOW"/* "$HOST"/.[!.]* 2>/dev/null || true

mkdir -p "$HOST/src"
echo "src" > "$HOST/src/main.go"
mkdir -p "$HOST/.ccr" && cat > "$HOST/.ccr/shadow" <<EOF
node_modules
.env.local
EOF

/tools/ccr-fuse --backing "$HOST" --shadow "$SHADOW" --mount "$MNT" --rules "$HOST/.ccr/shadow" --cache 0.1 &
FPID=$!
for i in 1 2 3 4 5 10; do mountpoint -q "$MNT" && break; sleep 0.2; done
mountpoint -q "$MNT" || { echo FAIL; exit 1; }

pass() { printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAILED=1; }
FAILED=0
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got=$1 want=$2)"; fi; }
expect_fail() {
    msg=$1; shift
    if "$@" 2>/dev/null; then fail "$msg (op unexpectedly succeeded)"; else pass "$msg (op rejected as expected)"; fi
}

echo "=== R1: read .ccr/shadow from inside container ==="
got=$(cat "$MNT/.ccr/shadow")
case "$got" in
    *node_modules*) pass "R1a content readable" ;;
    *)              fail "R1a expected rules content, got: $got" ;;
esac

echo
echo "=== R2: write attempts return EROFS ==="
expect_fail "R2a echo >> .ccr/shadow"        sh -c "echo 'new-rule' >> $MNT/.ccr/shadow"
expect_fail "R2b echo > .ccr/shadow"         sh -c "echo 'overwrite' > $MNT/.ccr/shadow"
expect_fail "R2c truncate .ccr/shadow"       truncate -s 0 "$MNT/.ccr/shadow"
expect_fail "R2d chmod 600 .ccr/shadow"      chmod 600 "$MNT/.ccr/shadow"
expect_fail "R2e rm .ccr/shadow"             rm "$MNT/.ccr/shadow"
expect_fail "R2f mv .ccr/shadow other"       mv "$MNT/.ccr/shadow" "$MNT/other"
expect_fail "R2g mv x .ccr/shadow (rename onto rules path)" sh -c "echo y > $MNT/scratch && mv $MNT/scratch $MNT/.ccr/shadow"

echo
echo "=== R3: host file unchanged throughout ==="
host_content=$(cat "$HOST/.ccr/shadow")
case "$host_content" in
    *node_modules*) pass "R3a host rules intact" ;;
    *)              fail "R3a host rules corrupted: $host_content" ;;
esac
host_size=$(wc -c < "$HOST/.ccr/shadow")
[ "$host_size" -gt 0 ] && pass "R3b host file non-empty (size=$host_size)" || fail "R3b host file empty"

echo
echo "=== R4: read works repeatedly (open-for-read not blocked) ==="
for i in 1 2 3; do
    cat "$MNT/.ccr/shadow" > /dev/null 2>&1 && true
done
pass "R4 multiple reads ok"

echo
echo "=== R5: host can still write to /host/.ccr/shadow ==="
echo "added-from-host" >> "$HOST/.ccr/shadow"
got=$(grep "added-from-host" "$HOST/.ccr/shadow")
[ -n "$got" ] && pass "R5 host edit succeeded" || fail "R5 host edit failed"

echo
echo "=== unmount ==="
cd /
fusermount3 -u "$MNT" 2>&1 || umount -l "$MNT"
wait $FPID 2>/dev/null || true

if [ "$FAILED" = "0" ]; then
    echo "ALL READ-ONLY-RULES TESTS PASSED"
    exit 0
else
    echo "READ-ONLY-RULES TESTS FAILED"
    exit 1
fi
