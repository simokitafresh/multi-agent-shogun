#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[eventsテーブル]], [[セマンティック辞書構想]]
# memory_db_init.sh — Initialize the local multi-agent memory DB.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 "$script_dir/scripts/memory_db_import.py" "$@"
