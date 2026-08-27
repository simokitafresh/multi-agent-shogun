#!/usr/bin/env bash
# semantic-links: [[cmd_4408_ext4移設]], [[旧絶対パス再配置]], [[可逆切替]]
# Rewrite old WSL-root references in the copied ext4 tree.
set -euo pipefail

OLD_ROOT="${OLD_ROOT:-/mnt/c/tools/multi-agent-shogun}"
NEW_ROOT="${NEW_ROOT:-/home/simokitafresh/multi-agent-shogun}"
DRY_RUN=false

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      printf '%s\n' "Usage: $0 [--dry-run]"
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

blocked() {
  printf 'RELOCATE_BLOCKED: %s\n' "$1" >&2
  exit 2
}

[[ "$OLD_ROOT" != "$NEW_ROOT" ]] || blocked "old and new roots must differ"
[[ -d "$NEW_ROOT" ]] || blocked "new root missing: $NEW_ROOT"

# The migration helpers retain their OLD_ROOT defaults so rollback and a
# repeated migration remain possible.  They are control-plane code, not
# copied-tree runtime references to rewrite.
mapfile -d '' relative_candidates < <(
  cd "$NEW_ROOT"
  rg -l -0 -I --no-messages --fixed-strings "$OLD_ROOT" . \
    -g '!logs/**' \
    -g '!queue/archive/**' \
    -g '!docs/research/**' \
    -g '!memory/**' \
    -g '!scripts/migrate_to_ext4_cutover.sh' \
    -g '!scripts/migrate_to_ext4_rollback.sh' \
    -g '!scripts/migrate_to_ext4_relocate.sh' || true
)
candidates=()
for relative_path in "${relative_candidates[@]}"; do
  candidates+=("$NEW_ROOT/${relative_path#./}")
done

if (( ${#candidates[@]} == 0 )); then
  printf '%s\n' 'RELOCATE_PASS: changed_files=0 changed_occurrences=0 remaining=0'
  exit 0
fi

export OLD_ROOT NEW_ROOT
if "$DRY_RUN"; then
  python3 - "${candidates[@]}" <<'PY'
import os
import sys

old = os.environ["OLD_ROOT"]
total = 0
for name in sys.argv[1:]:
    try:
        total += open(name, encoding="utf-8", errors="ignore").read().count(old)
    except OSError:
        pass
print(f"DRY_RUN_RELOCATE: would replace {len(sys.argv) - 1} file(s) and {total} occurrence(s); no files changed")
PY
  exit 0
fi

python3 - "${candidates[@]}" <<'PY'
import os
import stat
import sys
import tempfile

old = os.environ["OLD_ROOT"].encode()
new = os.environ["NEW_ROOT"].encode()
changed_files = 0
changed_occurrences = 0

for name in sys.argv[1:]:
    with open(name, "rb") as source:
        data = source.read()
    occurrences = data.count(old)
    if not occurrences:
        continue
    replacement = data.replace(old, new)
    mode = stat.S_IMODE(os.stat(name).st_mode)
    directory = os.path.dirname(name) or "."
    fd, temporary = tempfile.mkstemp(prefix=".ext4-relocate.", dir=directory)
    try:
        with os.fdopen(fd, "wb") as target:
            target.write(replacement)
            target.flush()
            os.fchmod(target.fileno(), mode)
        os.replace(temporary, name)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    changed_files += 1
    changed_occurrences += occurrences

remaining = 0
for name in sys.argv[1:]:
    with open(name, "rb") as source:
        remaining += source.read().count(old)
if remaining:
    raise SystemExit(f"RELOCATE_BLOCKED: {remaining} old-root occurrence(s) remain in target files")
print(f"RELOCATE_PASS: changed_files={changed_files} changed_occurrences={changed_occurrences} remaining=0")
PY
