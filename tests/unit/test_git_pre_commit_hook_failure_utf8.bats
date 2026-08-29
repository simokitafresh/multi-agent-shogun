#!/usr/bin/env bats
# test_necessity: failure detail must not break UTF-8 character boundaries.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
}

load_bounded_helper() {
  eval "$(sed -n '/^_bounded_utf8_summary()/,/^}/p' "$HOOK")"
}

@test "bounded summary drops only an incomplete multibyte tail" {
  load_bounded_helper
  fixture="$REPO/stderr"
  actual="$REPO/actual"
  expected="$REPO/expected"
  false_positive=0
  false_negative=0
  cases=0
  for token in "日本語" "é" "🚀" "日本語é🚀"; do
    for prefix in 197 198 199; do
      python3 - "$fixture" "$expected" "$token" "$prefix" <<'PY'
from pathlib import Path
import sys

fixture, expected, token, prefix_text = sys.argv[1:]
prefix = int(prefix_text)
source = ("x" * prefix + token + "\n").encode("utf-8")
Path(fixture).write_bytes(source)
bounded = source[:200]
while bounded:
    try:
        safe = bounded.decode("utf-8")
        break
    except UnicodeDecodeError:
        bounded = bounded[:-1]
else:
    safe = ""
Path(expected).write_bytes(safe.replace("\n", " ").encode("utf-8"))
PY
      _bounded_utf8_summary "$fixture" 200 > "$actual"
      if ! cmp -s "$actual" "$expected"; then
        if cmp -s <(head -c "$(wc -c < "$expected")" "$actual") "$expected"; then
          false_positive=$((false_positive + 1))
        elif cmp -s <(head -c "$(wc -c < "$actual")" "$expected") "$actual"; then
          false_negative=$((false_negative + 1))
        else
          false_positive=$((false_positive + 1))
          false_negative=$((false_negative + 1))
        fi
      fi
      cases=$((cases + 1))
    done
  done
  [ "$cases" -eq 12 ]
  [ "$false_positive" -eq 0 ]
  [ "$false_negative" -eq 0 ]
}

@test "failure record remains UTF-8 and YAML after multilingual boundary inputs" {
  record_function="$REPO/record_function"
  sed -n '/^_bounded_utf8_summary()/,/^}/p; /^_record_hook_failure()/,/^}/p' "$HOOK" > "$record_function"
  stderr_file="$REPO/stderr"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  python3 - "$stderr_file" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(("A" * 197 + "日本語\n" + "é🚀\n").encode("utf-8"))
PY

  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  python3 - "$log_file" <<'PY'
from pathlib import Path
import sys
import yaml

raw = Path(sys.argv[1]).read_bytes()
raw.decode("utf-8")
rows = yaml.safe_load(raw.decode("utf-8"))
assert len(rows) == 1
detail = rows[0]["detail"]
assert detail.startswith("A" * 197)
assert "日本語" not in detail
assert "é" not in detail
assert "🚀" not in detail
PY
}
