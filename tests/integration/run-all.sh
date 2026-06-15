#!/usr/bin/env bash
# Run every tests/integration/test-*.sh. Each test self-cleans via trap. We
# don't run in parallel — Apple Container's builder VM serialises image
# builds anyway.
set -euo pipefail

THIS=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$THIS/../.." && pwd)

if [ ! -x "$REPO/rp-fuse/rp-fuse-darwin-arm64" ]; then
    echo "FAIL: host rp-fuse binary missing; run 'rp build-host' first" >&2
    exit 1
fi
if ! container system status 2>/dev/null | grep -qi "running"; then
    echo "FAIL: Apple Container system not running; run 'rp service-start'" >&2
    exit 1
fi

failed=0
passed=0
for t in "$THIS"/test-*.sh; do
    name=$(basename "$t" .sh)
    echo "--- $name ---"
    if bash "$t"; then
        passed=$((passed+1))
    else
        echo "FAIL: $name"
        failed=$((failed+1))
    fi
    echo ""
done

echo "================================"
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
    exit 1
fi
