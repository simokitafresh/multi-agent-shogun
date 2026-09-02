#!/usr/bin/env bats
# test_necessity: failure detail must not break UTF-8 character boundaries.
# test_necessity: a pre-commit failure must persist the full stderr as a
# logs/hook_artifacts/*.log artifact (atomically) with an artifact_sha256
# plus a staged_diff_sha256, so a historical failure generation can be
# reconstructed after the 200-byte bounded summary and the temp stderr file
# are both gone (GA-551/GA-552, cmd_karo_hotfix_ga552_hook_artifact_20260902135701).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
}

load_bounded_helper() {
  eval "$(sed -n '/^_bounded_utf8_summary()/,/^}/p' "$HOOK")"
}

record_function_file() {
  local out="$1"
  sed -n '/^_bounded_utf8_summary()/,/^}/p; /^_record_hook_failure()/,/^}/p' "$HOOK" > "$out"
}

empty_sha256() {
  printf '' | sha256sum | awk '{print $1}'
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
  echo "MULTILINGUAL_BOUNDARY cases=$cases false_positive=$false_positive false_negative=$false_negative"
}

@test "failure record remains UTF-8 and YAML after multilingual boundary inputs" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
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

@test "failure artifact persists full stderr past the 200-byte summary with a matching sha256" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
  stderr_file="$REPO/stderr"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  python3 - "$stderr_file" <<'PY'
from pathlib import Path
import sys

content = ("L" * 200) + "MARKER_BEYOND_200_BYTES" + ("x" * 130)
Path(sys.argv[1]).write_text(content, encoding="utf-8")
PY
  # _record_hook_failure removes $_STDERR_FILE unconditionally at the end, so
  # keep an independent copy to compare the persisted artifact against.
  stderr_copy="$REPO/stderr.orig"
  cp "$stderr_file" "$stderr_copy"
  expected_sha256="$(sha256sum "$stderr_file" | awk '{print $1}')"

  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]

  # no leftover temp artifact from a partial/non-atomic write
  run bash -c "find '$REPO/logs/hook_artifacts' -name '*.tmp' 2>/dev/null"
  [ -z "$output" ]

  ARTIFACT_ABS="$(python3 - "$log_file" "$REPO" <<'PY'
from pathlib import Path
import sys
import yaml

log_file, repo = sys.argv[1:]
rows = yaml.safe_load(Path(log_file).read_bytes().decode("utf-8"))
row = rows[-1]
assert "artifact" in row, row
assert "artifact_sha256" in row, row
assert "staged_diff_sha256" in row, row
assert "MARKER_BEYOND_200_BYTES" not in row["detail"], "detail must stay bounded"
print(str(Path(repo) / row["artifact"]))
print(row["artifact_sha256"])
PY
)"
  artifact_abs="$(echo "$ARTIFACT_ABS" | sed -n 1p)"
  logged_sha256="$(echo "$ARTIFACT_ABS" | sed -n 2p)"

  [ -f "$artifact_abs" ]
  cmp -s "$artifact_abs" "$stderr_copy"
  [ "$logged_sha256" = "$expected_sha256" ]
  actual_artifact_sha256="$(sha256sum "$artifact_abs" | awk '{print $1}')"
  [ "$logged_sha256" = "$actual_artifact_sha256" ]
  grep -q "MARKER_BEYOND_200_BYTES" "$artifact_abs"
}

@test "failure record with empty stderr omits artifact fields but still hashes the staged diff" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
  stderr_file="$REPO/stderr"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  : > "$stderr_file"
  empty_hash="$(empty_sha256)"

  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]

  run bash -c "test -d '$REPO/logs/hook_artifacts'"
  [ "$status" -ne 0 ]

  python3 - "$log_file" "$empty_hash" <<'PY'
from pathlib import Path
import sys
import yaml

log_file, empty_hash = sys.argv[1:]
rows = yaml.safe_load(Path(log_file).read_bytes().decode("utf-8"))
row = rows[-1]
assert "artifact" not in row, row
assert "artifact_sha256" not in row, row
assert row["staged_diff_sha256"] == empty_hash, row
assert row["detail"] == "", row
PY
}

@test "staged_diff_sha256 distinguishes an empty stage from a staged change in a real repo" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
  stderr_file="$REPO/stderr"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  echo "boom" > "$stderr_file"
  empty_hash="$(empty_sha256)"

  git -C "$REPO" init -q
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "test"
  echo "one" > "$REPO/tracked.txt"
  git -C "$REPO" add tracked.txt
  git -C "$REPO" commit -q -m init

  # Case 1: nothing staged -> hash equals the empty-diff hash.
  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  unstaged_hash="$(python3 - "$log_file" <<'PY'
from pathlib import Path
import sys
import yaml

rows = yaml.safe_load(Path(sys.argv[1]).read_bytes().decode("utf-8"))
print(rows[-1]["staged_diff_sha256"])
PY
)"
  [ "$unstaged_hash" = "$empty_hash" ]

  # Case 2: a staged change -> hash differs from the empty-diff hash.
  echo "two" > "$REPO/tracked.txt"
  git -C "$REPO" add tracked.txt
  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  staged_hash="$(python3 - "$log_file" <<'PY'
from pathlib import Path
import sys
import yaml

rows = yaml.safe_load(Path(sys.argv[1]).read_bytes().decode("utf-8"))
print(rows[-1]["staged_diff_sha256"])
PY
)"
  [ "$staged_hash" != "$empty_hash" ]
  [ "$staged_hash" != "$unstaged_hash" ]
}

@test "concurrent failures in the same second do not collide on artifact filenames" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  stderr_a="$REPO/stderr_a"
  stderr_b="$REPO/stderr_b"
  python3 -c "from pathlib import Path; Path('$stderr_a').write_text('A'*250 + 'MARK_A', encoding='utf-8')"
  python3 -c "from pathlib import Path; Path('$stderr_b').write_text('B'*250 + 'MARK_B', encoding='utf-8')"

  # Two genuinely separate processes (distinct $$) racing to append the same
  # log and, absent PID-qualified artifact filenames, the same artifact_id.
  env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_a" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1" &
  pid_a=$!
  env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_b" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"

  [ -f "$log_file" ]
  python3 - "$log_file" "$REPO" <<'PY'
from pathlib import Path
import sys
import yaml

log_file, repo = sys.argv[1:]
rows = yaml.safe_load(Path(log_file).read_bytes().decode("utf-8"))
assert len(rows) == 2, rows
artifacts = [row["artifact"] for row in rows]
assert len(set(artifacts)) == 2, ("artifact filename collision", artifacts)
contents = {row["artifact"]: (Path(repo) / row["artifact"]).read_text(encoding="utf-8") for row in rows}
marks = sorted("".join(v[-6:]) for v in contents.values())
assert marks == ["MARK_A", "MARK_B"], marks
for row in rows:
    on_disk_sha256 = __import__("hashlib").sha256((Path(repo) / row["artifact"]).read_bytes()).hexdigest()
    assert on_disk_sha256 == row["artifact_sha256"], (row["artifact"], on_disk_sha256, row["artifact_sha256"])
PY
}

@test "artifact write failure degrades to summary-only recording instead of aborting" {
  record_function="$REPO/record_function"
  record_function_file "$record_function"
  stderr_file="$REPO/stderr"
  log_file="$REPO/logs/hook_failures.yaml"
  mkdir -p "$REPO/logs"
  echo "boom, cannot persist this one" > "$stderr_file"

  # Force the artifact mkdir/cp/mv path to fail by pre-occupying the target
  # directory name with a plain file, so _record_hook_failure must degrade
  # gracefully (fail-closed: no crash, no partial artifact, log still written).
  : > "$REPO/logs/hook_artifacts"

  run env REPO_ROOT="$REPO" _STDERR_FILE="$stderr_file" TMUX_PANE="" bash -c "$(cat "$record_function"); _record_hook_failure 1"
  [ "$status" -eq 0 ]
  [ -f "$log_file" ]

  python3 - "$log_file" <<'PY'
from pathlib import Path
import sys
import yaml

rows = yaml.safe_load(Path(sys.argv[1]).read_bytes().decode("utf-8"))
row = rows[-1]
assert "artifact" not in row, row
assert "artifact_sha256" not in row, row
assert "staged_diff_sha256" in row, row
assert row["detail"].startswith("boom, cannot persist this one"), row
PY

  # the pre-existing plain file must remain untouched, not silently replaced
  [ -f "$REPO/logs/hook_artifacts" ]
  [ ! -d "$REPO/logs/hook_artifacts" ]
}
