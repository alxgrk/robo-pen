#!/bin/sh
# Permission-gated run mode — Claude prompts before each tool action.
exec claude "$@"
