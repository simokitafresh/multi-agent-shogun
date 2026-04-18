# CoDD Spec + After: gate_cmd_state.sh 高速化

- cmd: `cmd_2043`
- 実施者: `hayate`
- 対象: `scripts/gates/gate_cmd_state.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `bash scripts/gates/gate_cmd_state.sh` (no-pending-cmds path: shogun_to_karo.yaml 存在 + pending cmd なし)
- 実測:
  - `20ms`
  - `21ms`
  - `19ms`
- 平均: `~20ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"` — 起動ごとにサブシェル2つ(`$()` x2)と `cd` コマンドを生成。no-pending-cmds path でも毎回実行される。
2. `source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"` — pending cmds が存在しない場合でも常時 source。yaml_field_set.sh 内の関数定義コストを無条件に払う。

## 最適化候補

1. SCRIPT_DIR 解決を文字列演算化。`${_self%/*}` で親ディレクトリを抽出し、絶対パスの場合のみ `cd` にフォールバック。サブシェルゼロ or 1回で解決。
2. `yaml_field_set.sh` の source を pending cmds が存在するブロック内へ移動（lazy load）。no-pending-cmds path でのコストをゼロに。

## 実装 (cmd_2043)

1. SCRIPT_DIR 解決を文字列演算に変更:
   ```bash
   _self="$0"
   SCRIPT_DIR="${_self%/*}"
   [[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
   SCRIPT_DIR="${SCRIPT_DIR%/scripts/gates}"
   ```
2. `source yaml_field_set.sh` を `if [ ${#CMD_IDS[@]} -eq 0 ]` の後ろへ移動し、pending cmds がある場合のみロード。

## after 計測 (cmd_2057)

- 条件:
  - before と同一 (no-pending-cmds path)
- 実測:
  - `15ms`
  - `15ms`
  - `17ms`
- 平均: `~16ms`

## 結果

- `~20ms → ~16ms`
- 改善率: `-20%`

## 検証

- `bash -n scripts/gates/gate_cmd_state.sh`
- `bash scripts/gates/gate_cmd_state.sh` (no-pending-cmds path)
- テスト: `bats tests/unit/test_cmd_delegate.bats tests/unit/test_gate_shogun_startup.bats`

## 再利用パターン

- WSL2 では `$(dirname "$0")` + `$(cd ... && pwd)` の二重サブシェルが ~3ms 消費する。パスが `/` 始まりの場合は文字列演算だけで完結でき、フォールバックの `cd` も最大1回で済む。
- source/import コストが気になる場合は lazy load（使う直前に source）が有効。特に早期 exit が多い script では no-lazy の無条件 source が hot path になりやすい。
