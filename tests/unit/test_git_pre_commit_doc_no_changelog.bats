#!/usr/bin/env bats
# test_necessity: doc_no_changelog must block explicit history markers with an
# actionable correction while allowing ordinary design headings that merely
# contain the Japanese word for change.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/docs/research"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
}

run_check() {
  local content="$1"
  printf '%s\n' "$content" > "$REPO/docs/research/sample.md"
  git -C "$REPO" add docs/research/sample.md
  REPO_ROOT="$REPO" HOOK="$HOOK" bash -c '
    eval "$(sed -n "/^check_doc_no_changelog()/,/^}/p" "$HOOK")"
    list_staged_files() { git diff --cached --name-only --diff-filter=AM; }
    cd "$REPO_ROOT"
    check_doc_no_changelog
  '
}

@test "explicit history marker is blocked with a concrete correction" {
  run run_check "### v2.3変更点（2026-08-30）"

  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(doc_no_changelog)"* ]]
  [[ "$output" == *"修正文: 該当行を削除し"* ]]
  [[ "$output" == *"## vX.Y (YYYY-MM-DD)"* ]]
}

@test "ordinary change-content heading is not a false positive" {
  run run_check "## 変更内容"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "similar design headings remain allowed" {
  run run_check $'## 変更境界\n\n### 変更なし\n\n### 変更対象ファイル'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "line-form history marker remains blocked" {
  run run_check $'# Design\n\n変更: 実装を更新'

  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(doc_no_changelog)"* ]]
  [[ "$output" == *"修正文:"* ]]
}
