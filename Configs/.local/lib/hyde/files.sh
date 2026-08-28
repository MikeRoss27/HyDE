#!/usr/bin/env bash
# @name: files
# @short: Modern local file manager

set -euo pipefail
exec /usr/bin/python3 "$(dirname "$0")/files.py" "$@"
