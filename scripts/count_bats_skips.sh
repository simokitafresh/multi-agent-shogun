#!/usr/bin/env bash
# Count Bats TAP skip directives from already-produced test output.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "0"
  exit 0
fi

awk '
  BEGIN { count = 0 }
  /^[[:space:]]*ok[[:space:]][0-9]+/ && /#[[:space:]]*[Ss][Kk][Ii][Pp]([[:space:]]|$)/ {
    count++
  }
  END { print count + 0 }
' "$@"
