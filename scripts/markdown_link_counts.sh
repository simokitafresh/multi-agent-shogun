#!/usr/bin/env bash
# markdown_link_counts.sh — Count Obsidian [[wiki links]] in tracked Markdown files.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/markdown_link_counts.sh [--top N] [--select-file]

Ranks tracked Markdown files by ascending [[wiki link]] count. --select-file
prints the first candidate path, prioritizing isolated files.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
top_n=20
select_file=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --top)
            top_n="${2:?--top requires a value}"
            shift 2
            ;;
        --select-file)
            select_file=true
            shift
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! [[ "$top_n" =~ ^[0-9]+$ ]] || [ "$top_n" -lt 1 ]; then
    echo "ERROR: --top must be a positive integer: $top_n" >&2
    exit 2
fi

python3 - "$script_dir" "$top_n" "$select_file" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
top_n = int(sys.argv[2])
select_file = sys.argv[3].lower() == "true"

try:
    proc = subprocess.run(
        ["git", "-C", str(root), "ls-files", "*.md"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    paths = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
except Exception:
    paths = [str(p.relative_to(root)) for p in root.rglob("*.md") if ".git" not in p.parts]

excluded_prefixes = (
    ".",
    "node_modules/",
    "vendor/",
    "queue/archive/",
    "archive/",
)
excluded_names = {
    "CONTRIBUTING.md",
    "README.md",
    "README_ja.md",
    "SECURITY.md",
}

rows = []
for rel in paths:
    if rel.startswith(excluded_prefixes) or "/." in rel or Path(rel).name in excluded_names:
        continue
    path = root / rel
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    link_count = len(re.findall(r"\[\[[^\]\n]+?\]\]", text))
    rows.append((link_count, rel))

rows.sort(key=lambda item: (item[0], item[1]))

if select_file:
    if rows:
        print(rows[0][1])
        sys.exit(0)
    sys.exit(1)

print("markdownリンク数Top")
print("rank\tlinks\tpath")
for idx, (link_count, rel) in enumerate(rows[:top_n], 1):
    print(f"{idx}\t{link_count}\t{rel}")
PY
