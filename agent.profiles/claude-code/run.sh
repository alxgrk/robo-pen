#!/bin/sh
# Default run mode — permission-bypass. The container is the safety boundary.
exec claude --dangerously-skip-permissions "$@"
