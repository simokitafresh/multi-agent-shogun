#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/case"
  mkdir -p "$TEST_ROOT/bin"
  export GH_CMD="$TEST_ROOT/bin/gh"
  export GIST_INDEX_ID="self-index"
}

make_stub() {
  sed 's/^  //' > "$GH_CMD" <<'STUB'
  #!/usr/bin/env bash
  set -euo pipefail
  [ "${GH_STUB_FAIL:-0}" != 1 ] || exit 42
  [ "${1:-}" = api ] && [ "${2:-}" = --paginate ] && [ "${3:-}" = gists ]
  for number in $(seq 1 100); do
    printf 'id-%03d\tDesign %03d AsIs/ToBe 【📋設計済】\ta.md\tfalse\t2026-08-04T00:00:00Z\n' "$number" "$number"
  done
  printf '%s\n' \
    $'active-middle\tprefix 【🔨実装進行中】 suffix\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'unknown\tAsIs/ToBe without tag\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'closed\tprefix 【✅CLOSED】 監査レポート\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'report\t品質監査レポート\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'catalog\tMECE 正本カタログ\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'article\tnote記事 週報\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'fallback\tmisc dashboard\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'self-index\tindex itself\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'notebook-title\tanalysis.ipynb\ta.md\tfalse\t2026-08-04T00:00:00Z' \
    $'notebook-files\tnotebook\tmodel.ipynb\tfalse\t2026-08-04T00:00:00Z' \
    $'duplicate\tmisc dashboard\ta.md\tfalse\t2026-08-04T00:00:00Z'
STUB
  chmod +x "$GH_CMD"
}

# test_necessity: pagination must preserve every gist beyond the former 100-item ceiling.
@test "pagination normalizes more than 100 gists without loss" {
  make_stub; run bash scripts/gist_index_update.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"completeness: fetched=111 classified=107 excluded=4 sum=111 match=true"* ]]
}

# test_necessity: classification precedence and quality counters must remain mechanically observable.
@test "status tags, title keys, exclusions, duplicate, and fallback follow precedence" {
  make_stub; run bash scripts/gist_index_update.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"設計書・稼働中=101"* && "$output" == *"設計書・状態未確認=1"* && "$output" == *"設計書・CLOSED=1"* ]]
  [[ "$output" == *"## 設計書・状態未確認"* ]]
  [[ "$output" == *"調査書・監査・レポート=1"* && "$output" == *"正本・カタログ・パターン=1"* ]]
  [[ "$output" == *"記事・対外発信=1"* && "$output" == *"その他・運用=1"* ]]
  [[ "$output" == *"unknown_status=1 fallback=1"* ]]
  [[ "$output" == *"self_index=1 duplicate_title=1 ipynb=2"* ]]
}

# test_necessity: an API failure must fail closed and never publish a partial index.
@test "API failure is nonzero" {
  make_stub; export GH_STUB_FAIL=1
  run bash scripts/gist_index_update.sh --dry-run
  [ "$status" -ne 0 ]
}
