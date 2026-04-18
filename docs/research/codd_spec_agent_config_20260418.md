# CoDD Spec + After: agent_config.sh 高速化

- cmd: `cmd_2046` (kagemaru実装)
- 実施者: `kagemaru`
- 対象: `scripts/lib/agent_config.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `source scripts/lib/agent_config.sh && get_ninja_names` (get_ninja_names初回呼び出し)
- 実測:
  - `37ms`
  - `35ms`
  - `36ms`
- 平均: `36ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `_AGENT_CONFIG_SCRIPT_DIR="${_AGENT_CONFIG_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"` — SCRIPT_DIR 解決で `$(dirname)` + `$(cd ... && pwd)` のサブシェル2つ。毎回払う起動コスト。
2. `get_agent_role` / `get_japanese_name` が `echo "$_AGENT_CONFIG_RAW" | awk '{...}'` パターンを使用 — 各呼び出しで awk プロセスを起動していた。多重呼び出し時に累積。

## 最適化候補

1. SCRIPT_DIR 解決を文字列演算化 + `if [[ -z "${_AGENT_CONFIG_SCRIPT_DIR:-}" ]]` ガードで多重計算防止。
2. ロール・日本語名のルックアップを `declare -A` 連想配列に変更。awk 起動ゼロ、O(1) アクセス。

## 実装 (cmd_2046)

1. SCRIPT_DIR を文字列演算 + 初回のみ計算:
   ```bash
   if [[ -z "${_AGENT_CONFIG_SCRIPT_DIR:-}" ]]; then
       _ac_self="${BASH_SOURCE[0]}"
       [[ "$_ac_self" != /* ]] && _ac_self="$PWD/$_ac_self"
       _AGENT_CONFIG_SCRIPT_DIR="${_ac_self%/scripts/lib/agent_config.sh}"
   fi
   ```
2. `declare -A _AGENT_CONFIG_ROLE_MAP=()` と `declare -A _AGENT_CONFIG_JP_MAP=()` を追加。
3. `_agent_config_load` 内で連想配列にデータを格納:
   ```bash
   _AGENT_CONFIG_ROLE_MAP["$_ac_name"]="$_ac_role"
   _AGENT_CONFIG_JP_MAP["$_ac_name"]="${_ac_jp:-$_ac_name}"
   ```
4. `get_agent_role` / `get_japanese_name` で `echo "${_AGENT_CONFIG_ROLE_MAP[$name]:-ninja}"` に変更。

## after 計測 (cmd_2059)

- 条件:
  - before と同一 (get_ninja_names初回呼び出し, source後の状態)
- 実測:
  - `5ms`
  - `6ms`
  - `6ms`
- 平均: `~6ms`

## 結果

- `36ms → ~6ms`
- 改善率: `-83%`
- 改善倍率: `6x`
- 台帳記録値(実装時計測): `36ms → 14ms (-61%)`

## 検証

- `bash -n scripts/lib/agent_config.sh`
- `source scripts/lib/agent_config.sh && get_ninja_names` → エージェント名リスト出力
- `get_agent_role kotaro` → `ninja`

## 再利用パターン

- 設定ファイルを繰り返し読む lib スクリプトは「初回load + キャッシュ」パターンで後続呼び出しを O(1) にできる。
- ロール/属性ルックアップで `echo|awk` を使っていた箇所は `declare -A` 連想配列で完全置き換え可能。bash ビルトインのハッシュアクセスはプロセス起動ゼロ。
- SCRIPT_DIR の `if [[ -z ]]` ガードを付けると、source した場合に毎回の計算を防げる（同一プロセス内での二重 source 対策）。
