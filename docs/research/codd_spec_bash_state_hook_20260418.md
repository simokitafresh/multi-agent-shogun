# CoDD Spec + After: bash_state_hook.sh 高速化

- cmd: `cmd_2050`
- 実施者: `kotaro`
- 対象: `scripts/hooks/bash_state_hook.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `echo '{}' | bash scripts/hooks/bash_state_hook.sh` (empty payload exit path)
- 実測:
  - `36ms`
  - `35ms`
  - `37ms`
- 平均: `36ms`
- 出典: `docs/research/codd_infra_script_profiling.md` Phase 3測定値

## ボトルネック

1. `payload="$(cat)"` — サブシェル fork + `/usr/bin/cat` 起動。stdin バッファを読み込むだけで ~3-5ms 消費。
2. `printf '%s' "$payload" | jq -r '.hook_event_name // .hookEventName // empty'` — `jq` プロセス起動 + パイプ。JSON フィールド1個を取得するためだけに ~20ms 消費。
3. `$(date +%s)` — PreToolUse 時にタイムスタンプ取得で `date` プロセスを起動。~3ms 追加。

## 最適化候補

1. `cat` → `IFS='' read -r -d '' payload || true` — ビルトイン read で stdin をサブシェルなしに読込み。
2. `jq` → `[[ "$payload" =~ \"hook_event_name\"... ]]` — bash 正規表現でフィールドを抽出。プロセス起動ゼロ。
3. `$(date +%s)` → `printf -v _ts '%(%s)T' -1` — printf ビルトインで現在エポック秒を取得。プロセス起動ゼロ。

## 実装 (cmd_2050)

1. stdin 読込みを `IFS='' read -r -d '' payload || true` に変更。
2. hook_event 抽出をbash正規表現に変更:
   ```bash
   if [[ "$payload" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
       hook_event="${BASH_REMATCH[1]}"
   elif [[ "$payload" =~ \"hookEventName\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
       hook_event="${BASH_REMATCH[1]}"
   fi
   ```
3. タイムスタンプ取得を `printf -v _ts '%(%s)T' -1` に変更。

## after 計測 (cmd_2057)

- 条件:
  - before と同一 (empty payload exit path)
- 実測:
  - `6ms`
  - `6ms`
  - `5ms`
- 平均: `~6ms`

## 結果

- `36ms → ~6ms`
- 改善率: `-83%`
- 改善倍率: `6x`

## 検証

- `bash -n scripts/hooks/bash_state_hook.sh`
- `echo '{}' | bash scripts/hooks/bash_state_hook.sh` → exit 0
- `echo '{"hook_event_name":"PreToolUse"}' | bash scripts/hooks/bash_state_hook.sh` → tmux set-option 実行（TMUX_PANE未設定時は exit 0）

## 再利用パターン

- hook は全ツール呼び出し時に毎回起動される hot path。`cat` / `jq` / `date` の各プロセス起動コストが積み重なる。
- bash ビルトイン (`read`, `[[ =~ ]]`, `printf -v ... '%(%s)T'`) で同等の処理が実現可能な場合は積極的に置き換える。
- JSON の単一フィールド取得程度なら `jq` 不要。bash 正規表現で十分。`jq` が必要なのは複雑な変換や配列操作のとき。
