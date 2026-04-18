# CoDD Spec + After: test_result_guard.sh 高速化

- cmd: `cmd_2050`
- 実施者: `kotaro`
- 対象: `scripts/hooks/test_result_guard.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash scripts/hooks/test_result_guard.sh` (non-test fast-exit path)
- 実測:
  - `32ms`
  - `31ms`
  - `33ms`
- 平均: `32ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `payload="$(cat 2>/dev/null || true)"` — サブシェル fork + `cat` 起動。non-test fast-exit path でも毎回発生。
2. ただし fast-exit path (`[[ "$payload" != *'"Bash"'* ]]` 等の string match) は既に bash ビルトインを使用しており、Python呼び出しまで到達しない場合のコストは stdin 読込みのサブシェルのみ。

## 最適化候補

1. `payload="$(cat 2>/dev/null || true)"` → `IFS='' read -r -d '' payload || true` — ビルトイン read に変更。non-test fast-exit path での ~3-5ms を削減。
2. fast-path の string match ロジックは既に最適化済み（bash ビルトイン使用）のため変更不要。

## 実装 (cmd_2050)

1. stdin 読込みを `IFS='' read -r -d '' payload || true` に変更。
   - `cat` → ビルトイン read でサブシェルゼロ。

## after 計測 (cmd_2057)

- 条件:
  - before と同一 (non-test fast-exit path)
- 実測:
  - `6ms`
  - `5ms`
  - `5ms`
- 平均: `~5ms`

## 結果

- `32ms → ~5ms`
- 改善率: `-84%`
- 改善倍率: `6.4x`

## 検証

- `bash -n scripts/hooks/test_result_guard.sh`
- `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash scripts/hooks/test_result_guard.sh` → 出力なし + exit 0
- `bats tests/unit/test_test_result_guard.bats`

## 再利用パターン

- `payload="$(cat)"` パターンは hook script の定番アンチパターン。hook は全ツール呼び出し時に毎回起動されるため、このコストが積み重なる。
- 単純な stdin バッファリング（サブプロセスへの渡し以外）は `IFS='' read -r -d '' var || true` で代替可能。
- fast-exit の多い script では stdin 読込みの最適化が最大の効果を持つ（Python/jq に到達しない場合はその後のコストはゼロ）。
