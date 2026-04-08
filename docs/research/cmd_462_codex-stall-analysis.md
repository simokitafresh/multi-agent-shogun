# cmd_462 Codex STALL Analysis

Date: 2026-03-01  
Author: hayate  
Scope: `logs/ninja_monitor.log`, `logs/deploy_task.log`, `scripts/ninja_monitor.sh`, `config/cli_profiles.yaml`

## §1 自己分析結果

### 1.1 観測された実挙動（Codex視点）
- `2026-03-01 00:08:26` 以降、`hayate` は `status=acknowledged` のまま `STALE-TASK` 判定され、`AUTO-CLEAR: ... sending /new` が反復。
- 同じ現象が `kirimaru/saizo` にも発生（`status=in_progress` でも `STALE-TASK` 扱い）。
- 代表ログ:
  - `2026-03-01 00:08:26 STALE-TASK: hayate has YAML status=acknowledged ... treating as not deployed`
  - `2026-03-01 00:08:27 AUTO-CLEAR: hayate idle+no_task CTX=7%, sending /new`
  - `2026-03-01 00:27:04 STALE-TASK: kirimaru has YAML status=in_progress ...`
  - `2026-03-01 00:27:05 AUTO-CLEAR: kirimaru idle+no_task CTX=30%, sending /new`

### 1.2 acknowledge後に作業に入れない時の停止点
- 実停止点は `/clear Recovery` 手順そのものではなく、`ninja_monitor.sh` の「配備済み判定 → stale判定 → auto-clear」の監視ループ。
- `is_task_deployed()` は `pane_idle && @current_task empty` で `STALE-TASK` とみなし未配備扱いにする（`scripts/ninja_monitor.sh:589-595`）。
- Codexタスク側が `acknowledged/in_progress` のままでも `/new` が再送されるため、作業開始前後でセッションが切断される。

### 1.3 タスク複雑さ・説明量・教訓注入量の影響
- 本タスク (`subtask_462_recon_a`) は本文が長く、`related_lessons` が8件。  
- ただし一次因は「監視側の stale 判定と auto-clear ループ」。複雑さは二次要因（初動遅延を増幅）と判断。

## §2 環境・設定調査結果

### 2.1 Codex/Claude プロファイル差分（`config/cli_profiles.yaml`）
- Codex:
  - `clear_cmd: /new`
  - `confirm_wait: 20`
  - `debounce: 180`
  - `clear_debounce: 600`
  - `stall_debounce: 180`
  - `busy_patterns`: `esc to interrupt|Running|Streaming|background terminal running`
- Claude:
  - `clear_cmd: /clear`
  - `confirm_wait: 5`
  - `debounce: 60`
  - `clear_debounce: 300`

### 2.2 実装上の重要点
- `check_stall()` が `task_id` フィールドを参照（`scripts/ninja_monitor.sh:833-835`）。
- 現在の task YAML は `task_id` を持たず `subtask_id` のみ（例: `queue/tasks/hayate.yaml`）。
- その結果:
  - `STALL-WATCH` が `task` 空欄ログ化（例: `2026-02-27 20:01:43` 以降）
  - `stall_key=name:` 固定化で通知抑止が恒常化するリスク
  - `2026-02-26` 以降 `STALL-DETECTED` が0件

### 2.3 WSL2/Codex固有の制約
- 監視はポーリング型で、誤判定時の `/new` 再送が実作業を中断しやすい。
- `AUTO-RESTART`（スクリプト変更検知）も発生しており、監視内部状態（追跡配列）リセットが断続的に起きる。

## §3 過去事例パターン分析

### 3.1 集計方法
- `ninja_monitor.log` の `STALL-WATCH/STALL-DETECTED` から、`agent+subtask` のユニーク件数で集計。
- `subtask` を含まない空欄ログ（`task  and is idle`）は率計算から除外。
- モデル分類:
  - Codex: `sasuke,kirimaru,hayate,saizo`
  - Opus: `kagemaru,hanzo,kotaro,tobisaru`

### 3.2 モデル別 STALL 発生率（ユニーク subtask）

| model | watch | detected | rate |
|---|---:|---:|---:|
| Codex | 313 | 16 | 5.1% |
| Opus | 254 | 27 | 10.6% |

補足: この値は「空欄task_id問題が顕在化する前の期間寄り」。後述の盲点を含む。

### 3.3 タスク種別別 STALL 発生率

分類規則: `subtask_id` の文字列から `recon/review/impl/other` に分類。

| task_type | watch | detected | rate |
|---|---:|---:|---:|
| recon | 69 | 1 | 1.4% |
| review | 57 | 5 | 8.8% |
| impl | 126 | 3 | 2.4% |
| other | 315 | 34 | 10.8% |

モデル×種別（主要）:
- `Opus|other`: 22/144 = 15.3%
- `Codex|other`: 12/171 = 7.0%
- `Codex|review`: 2/23 = 8.7%
- `Opus|review`: 3/34 = 8.8%

### 3.4 時間帯・CTX相関

時間帯（detected件数）:
- 高頻度: `02時=9件`, `18時=4件`, `20時=4件`, `22時=4件`
- 長時間停滞: `>=60分` 2件、`>=600分` 2件（夜間跨ぎ）

CTX相関:
- `ninja_monitor.log` の `STALL-DETECTED` 行は task時点CTXを持たないため、直接相関は算出不可。
- 代替指標として `deploy_task.log` の平均 `CTX` を見ると、主要エージェントは `0.1%〜3.0%` に集中し分散が小さい。  
  有意な線形相関は現状データでは確認不能。

### 3.5 盲点（重要）
- `STALL-DETECTED` 日次件数:
  - 2026-02-16: 3
  - 2026-02-17: 11
  - 2026-02-18: 16
  - 2026-02-19: 15
  - 2026-02-20: 6
  - 2026-02-23: 3
  - 2026-02-24: 2
  - 2026-02-25: 2
  - 2026-02-26以降: 0
- 一方 `STALL-WATCH` は 2026-02-26以降も継続。  
  → 検知機構が沈黙している可能性が高く、実STALL率は過小評価の恐れ。

## §4 仮説と対策提案（検証可能）

### 仮説1: `task_id` 欠落により STALL 検知が空振り
- 根拠:
  - `check_stall()` は `task_id` を読む (`scripts/ninja_monitor.sh:835`)。
  - 現行タスクYAMLは `subtask_id` のみ。
  - `2026-02-27 20:01:43` から `STALL-WATCH ... task  and is idle` が発生。
- 対策:
  - `task_id=$(task_id || subtask_id)` フォールバック実装。
  - `stall_key` も同じIDに統一。
- 検証:
  - 実装後24時間で `STALL-WATCH` 空欄件数が0になること。
  - `STALL-DETECTED` が再び出現し、`name:` 固定キーが消えること。

### 仮説2: `STALE-TASK` 判定条件が強すぎ、Codexを誤って未配備扱い
- 根拠:
  - `pane_idle && @current_task empty` で stale 扱い (`scripts/ninja_monitor.sh:589-595`)。
  - 直近（2026-02-28以降）`STALE-TASK` は Codex 420件 vs Opus 22件。
  - `in_progress` でも stale→`/new` 実行が確認できる。
- 対策:
  - stale条件を `status=done` or `report_done` と連動させる。
  - `assigned/acknowledged/in_progress` 中は `@current_task` 空欄のみで stale判定しない。
  - あるいは `N連続idle + no progress + no inbox unread` の複合条件に変更。
- 検証:
  - 直近24時間の `STALE-TASK(Codex)` を 50%以上削減。
  - `AUTO-CLEAR(/new)` 回数の対タスク比を半減。

### 仮説3: Codex busyパターン不足で idle誤判定が先行
- 根拠:
  - Codexの `busy_patterns` に `thinking|thought for` が未登録。
  - `FALSE_POSITIVE` は累計 Codex 459件。
- 対策:
  - Codex busyパターンに `thinking|thought for|analyzing` を追加。
  - `@agent_state=active` を優先し、capture-paneでの idle昇格をより保守化。
- 検証:
  - `FALSE_POSITIVE` を1週間で 30%以上削減。
  - 同期間に `STALE-TASK`/`AUTO-CLEAR` 連鎖が減少すること。

### 仮説4: 監視スクリプトの頻繁な再起動で追跡状態が失われる
- 根拠:
  - `AUTO-RESTART` 累計76回（2/18に31回）。
  - 再起動時に配列状態が初期化され、stall追跡継続性が落ちる。
- 対策:
  - 監視中の自己再起動をメンテ時間帯に限定。
  - 追跡状態を一時ファイルへ永続化（最低 `STALL_FIRST_SEEN`, `STALL_NOTIFIED`）。
- 検証:
  - 再起動回数と `STALL-WATCH` 再開始回数の相関低下を確認。
