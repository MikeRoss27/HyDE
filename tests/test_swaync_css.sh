#!/usr/bin/env sh
# Configs/.config/swaync/style.css must be syntactically valid GTK CSS:
# every @import statement must end in a semicolon. A missing one produced
# "Theme parser warning: style.css:8:1-9:1: Unterminated block at end of
# document" and "Could not acquire notification name" from swaync at
# runtime (see docs/personal-fork/ARCHITECTURE.md). Regression test for
# that exact bug - fix at the source template, not the deployed copy.

. "$(dirname -- "$0")/lib/common.sh"

css="$REPO_ROOT/Configs/.config/swaync/style.css"

if [ ! -f "$css" ]; then
    fail "missing: $css"
    finish
fi

count=0
while IFS= read -r line; do
    case "$line" in
        @import*)
            count=$((count + 1))
            case "$line" in
                *\;) ;;
                *) fail "unterminated @import (missing trailing ';'): $line" ;;
            esac
            ;;
    esac
done <"$css"

[ "$count" -gt 0 ] || fail "no @import lines found in $css - test itself may be stale"
printf '    %d @import line(s) checked\n' "$count"
finish
