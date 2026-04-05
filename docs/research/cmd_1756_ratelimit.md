# cmd_1756 ratelimit_check.sh 改善比較

## 1. 結論

- 比較対象の upstream 改善 `c87ca64` は、`scripts/ratelimit_check.sh` に対して「狭い tmux ペインで `/status` 出力が折り返されて `% left` と reset 時刻が欠落する」問題を避けるため、capture 前の一時 zoom と最新 status block 抽出を追加している。
- 我が軍には `scripts/ratelimit_check.sh` は存在しない。Codex 利用量表示の同等経路は `scripts/usage_monitor.sh` + `scripts/usage_status.sh` であり、tmux pane から `/status` を capture していない。
- したがって upstream の zoom-capture / awk block 抽出は、そのまま取込む対象が無い。**取込判定は「不要」**。
- ただし「狭ペインだと pane capture ベースの `/status` 解析は壊れやすい」という現象自体は我が軍でも成立しうる。現に忍者 pane 幅は 52-60 列で、upstream が対処した前提条件は存在する。

## 2. upstream `c87ca64` の差分要約

`gh api repos/yohey-w/multi-agent-shogun/commits/c87ca64 --jq '.files[] | select(.filename=="scripts/ratelimit_check.sh") | .patch'`
で取得した patch から、追加点は次の 3 本柱だった。

1. `capture_tmux_pane_zoomed()`
   pane が非 zoom 状態なら一時的に zoom して `tmux capture-pane -p -J` を取る。
2. `capture_codex_status_snapshot()`
   pane に `/status` を送って出力を出させた後、zoom 状態で capture する。
3. `extract_latest_codex_status_block()`
   `>_ OpenAI Codex` から box 終端 `╰` までを awk で抜き、最新 block のみを解析対象にする。

そのうえで既存の 3b フェーズを「scrollback 全体 grep」から「zoom 済み最新 block 限定 grep」に切り替え、`5h limit:` / `Weekly limit:` の account-level / model-level 行を安定抽出している。

## 3. 我が軍の同等経路

### 3.1 対象スクリプト

- `scripts/ratelimit_check.sh`: **存在しない**
- `scripts/usage_monitor.sh`: Codex 利用量の正本。`~/.codex/state_5.sqlite` を直接読む。`scripts/usage_monitor.sh:34-35`, `223-251`
- `scripts/usage_status.sh`: tmux status-right 表示。`usage_monitor.sh --status` の4フィールド出力をバー表示へ整形する。`scripts/usage_status.sh:3-6`, `164-177`

### 3.2 データ取得方式の差

upstream `c87ca64`:
- tmux pane に `/status` を送る
- pane 出力を capture する
- text box を grep/awk で解釈する

我が軍:
- Codex SQLite (`~/.codex/state_5.sqlite`) の `threads.tokens_used` を 5h / 7d で集計する
- `usage_monitor.sh --status` は `20\t09:14\t40\trolling` のような構造化4列を返す
- `usage_status.sh` はそれを `5H:█████ 100% left 09:13 7D:█████ 100% left rolling` の status-right 形式へ整形する

つまり、我が軍は **pane capture に依存していない**。この一点で upstream patch の主眼と異なる。

## 4. 狭ペイン表示切れは我が軍で起きているか

### 4.1 狭ペイン条件の有無

`tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_width} #{pane_height} #{@agent_id}'`
より、忍者 pane は次の幅だった。

- `shogun:2.3 hayate = 53 cols`
- `shogun:2.4 kagemaru = 53 cols`
- `shogun:2.5 hanzo = 53 cols`
- `shogun:2.6 saizo = 52 cols`
- `shogun:2.7 kotaro = 52 cols`
- `shogun:2.8 tobisaru = 52 cols`

したがって、**狭ペイン自体は存在する**。

### 4.2 しかし同一障害は未使用経路

- 我が軍の Codex usage 表示は `usage_monitor.sh` の SQLite 集計であり、tmux pane から `/status` を取っていない。
- `rg -n "window_zoomed_flag|capture-pane -p -J|/status|5h limit|Weekly limit|Codex|quota" scripts -g '*.sh'`
  でも、quota 取得用途で `capture-pane` している現行スクリプトは見当たらなかった。
- したがって、upstream が直した「narrow tiled pane による `/status` text box 切れ」が、**我が軍の現行 usage 経路で実際に発火している証拠は確認できなかった**。

## 5. 取込判定

### 判定: 不要

理由:

1. 対象ファイル `scripts/ratelimit_check.sh` が我が軍に存在しない
2. 同等機能は pane capture ではなく SQLite 直接読取で実装済み
3. 現行 `usage_status.sh codex` / `usage_monitor.sh --status` は正常に値を返した
4. upstream patch の zoom / capture / awk block 抽出は、我が軍の現在経路では dead code になる

## 6. 参考出力

### `usage_monitor.sh --status`

```text
20    09:14    40    rolling
```

### `usage_status.sh codex`

```text
5H:█████ 100% left 09:13 7D:█████ 100% left rolling
```

## 7. 将来の含意

- 将来、我が軍で tmux pane の `/status` を直接 scrape する新スクリプトを導入するなら、`c87ca64` の「zoom capture + 最新 block 限定抽出」は再利用価値が高い。
- ただし現時点で取込むなら、`scripts/ratelimit_check.sh` 新設ではなく、**pane capture 経路を本当に採る場面が出た時に最小限で移植**するのが妥当。
