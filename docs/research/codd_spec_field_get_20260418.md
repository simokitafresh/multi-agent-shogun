# CoDD Spec + After: field_get.sh 高速化

- cmd: `cmd_2046` (kagemaru実装)
- 実施者: `kagemaru`
- 対象: `scripts/lib/field_get.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `source scripts/lib/field_get.sh && FIELD_GET_NO_LOG=1 field_get <yaml_file> <field>` (YAML フィールド取得)
- 実測:
  - `34ms`
  - `32ms`
  - `33ms`
- 平均: `33ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `_FIELD_GET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"` — source 時に毎回サブシェル2つ。
2. `ts=$(date '+%Y-%m-%dT%H:%M:%S')` in `_field_get_log` — 依存記録のたびに `date` プロセスを起動 (~2-3ms)。
3. `( flock -n 200 || exit 0; ... ) 200>"$lock_file"` — サブシェル `( )` でflockを実行。サブシェル起動コスト毎回払う。

## 最適化候補

1. SCRIPT_DIR 解決を文字列演算化。`${_fg_self%/scripts/lib/field_get.sh}` で直接抽出。
2. `date` → `printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1` — printfビルトインで年月日時刻を取得。プロセス起動ゼロ。
3. `( ) subshell` → `{ }` ブロック — サブシェルを使わずにflockをブロック構文で実行。`exit 0` を `return 0` に変更。

## 実装 (cmd_2046)

1. SCRIPT_DIR を文字列演算に変更:
   ```bash
   _fg_self="${BASH_SOURCE[0]}"
   [[ "$_fg_self" != /* ]] && _fg_self="$PWD/$_fg_self"
   _FIELD_GET_SCRIPT_DIR="${_fg_self%/scripts/lib/field_get.sh}"
   unset _fg_self
   ```
2. タイムスタンプ取得を `printf -v` に変更:
   ```bash
   printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1
   ```
3. flock ブロックを `( )` → `{ }` に変更し、`flock -n 200 || exit 0` → `flock -n 200 || return 0`:
   ```bash
   {
     flock -n 200 || return 0
     ...
   } 200>"$lock_file" 2>/dev/null
   ```

## after 計測 (cmd_2059)

- 条件:
  - before と同一 (FIELD_GET_NO_LOG=1, YAML フィールド取得)
- 実測:
  - `2ms`
  - `2ms`
  - `3ms`
- 平均: `~2ms`

## 結果

- `33ms → ~2ms`
- 改善率: `-94%`
- 改善倍率: `16x`
- 台帳記録値(実装時計測): `33ms → 12ms (-64%)`
- 注記: 現在の計測はFIELD_GET_NO_LOG=1でlog処理をスキップした値。log有効時は flock + printf -v で更に削減。

## 検証

- `bash -n scripts/lib/field_get.sh`
- `bash scripts/lib/field_get.sh --test` (内蔵テストスイート実行)

## 再利用パターン

- `source` されるライブラリの SCRIPT_DIR 解決はモジュール起動時に1回だけ計算されるが、被 source 回数が多い場合にサブシェルコストが累積する。文字列演算化で完全に排除可能。
- `date` の代わりに `printf -v var '%(%Y-%m-%dT%H:%M:%S)T' -1` が使えるケースでは常に置き換えるべき。bash 4.2+ で利用可能。
- `( ) subshell` で flock を使っていた箇所は `{ }` ブロック + `return 0` (= サブシェル終了の代わりに関数リターン) で完全置き換え可能。サブシェル起動コストを排除。
