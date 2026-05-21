semantic-links: [[インフラ設計意図カタログ]]
# インフラ設計意図カタログ — 「バグに見えるが正しい」パターン集

- 作成日: 2026-05-20
- 作成者: 軍師(idle自走なぜなぜ7回)
- 目的: 浅い分析で「バグだ」と誤報告されやすい設計パターンの因果を記録。次の調査者が同じ穴に落ちない

## 使い方

インフラバグ調査時、「異常パターン」を発見したらこのカタログで照合せよ。
該当パターンがあれば設計意図を確認し、**誤報告を防ぐ**。
該当しなければ本当のバグの可能性が高い。

---

## パターン1: codex delivery remained unverified

### 現象
`[inbox_write] WARN: codex delivery remained unverified for {ninja} after 2 retries`
Codex忍者への配備後、inbox nudge到達確認が失敗。

### 発生頻度
14件/3日(2026-05-17〜20)。kagemaru6/hayate5/saizo3。

### 一見バグに見える理由
「配信未確認=メッセージ不達=忍者がタスクを受け取っていない」と推論しがち。

### 設計意図と因果
```
inbox_write.shのメッセージ書込み(flock保証) → 確実に書込まれる
  → nudge送信(tmux send-keys) → Codex CLIが受け取る
  → 確認(verify_codex_task_delivery): inbox既読 OR task status変化 → 3秒以内に確認
  → Codex CLIの応答が3秒で間に合わない → WARN出力
```
**メッセージ自体はflock保証で書込済み**。WARNはベストエフォート確認の失敗であり、配信失敗ではない。
ninja_monitorのnudge/inotifywatcherが後から拾うため、最終的に到達する。

### 検証方法
unverified後に対応cmdがkaro_workaroundsでclean(完了)になっているか確認。14件中14件=clean。

### なぜ修正しないのか
- retry回数/wait時間を増やす→deploy_task.shの配備時間が増加(全配備に影響)
- 現状はWARN(情報提供)であってBLOCK(停止)ではない
- 改善コスト > 影響(全件最終到達)

---

## パターン1.5: Codex idle時のrespawn-pane -k (10分間隔)

### 現象
`CODEX-RESPAWN: {ninja} respawn-pane (codex reset)` がidle時に10分間隔で発生。

### 一見バグに見える理由
「idle時にプロセスを殺して再起動する必要はない。/newで十分」と推論しがち。
実際cmd_2904/2906で/new経路に変更→CTX滞留で失敗(殿裁定2026-05-20)。

### 設計意図と因果
```
Codex CLI: /newコマンドはCLI内部の「task in progress」状態で拒否される
  → ninja_monitorのtask YAML statusとCodex CLI内部状態は別物
  → task YAML=idle でもCLI内部=task in progress の場合がある
  → /new送信→CLI内部で拒否→CTXリセットされない
  → respawn-pane -k: プロセスごと確実にリセット。CLI内部状態に依存しない
```
**respawn-pane -kが唯一確実なCodex CLIリセット手段**(殿裁定2026-05-20)。
cmd_2904(/newをブロック)→cmd_2906(/new経路復旧)→cmd_2907(respawn統一復旧)の3cmd連鎖で実証。

### 検証方法
CTX蓄積の有無。respawn後CTX=0%でリセット確認。/newでは3忍者のCTX蓄積が継続(36%/57%/44%)。

### なぜ修正しないのか
- `/new`はCodex CLI内部状態で拒否されうる(非決定的)
- `respawn-pane -k`はプロセスレベルのリセットで確実
- 10分間隔(clear_debounce=600s)はリソース消費として許容範囲
- Claude CLIの`/clear`に相当する確実なリセットがCodex CLIでは`/new`ではなくrespawn

---

## パターン2: STALL-GHOST (status=assigned but empty task_id)

### 現象
`STALL-GHOST: {ninja} has status=assigned but empty task_id — skipping stall detection`
task YAMLのstatusがassigned/acknowledged/in_progressなのにtask_idが空。

### 発生頻度
170件/日(2026-05-20)。全忍者で発生。tobisaru/kotaro最多。

### 一見バグに見える理由
「status=assignedなのにtask_idがない=配備が壊れている」と推論しがち。

### 設計意図と因果
```
resolve_cmd_to_task(yaml_field_set_batch) → status=assigned + task_id=xxx を原子的に書込み
  → 書込み完了前にninja_monitorのポーリングが読む(WSL2 NTFS遅延)
  → status=assignedは書かれたがtask_idは未到達
  → STALL-GHOSTフィルタ(cmd_1150)が安全に除外
```
**STALL-GHOSTは安全弁**。task_id空でSTALL検知→誤って/clearすると忍者の作業が中断される。
cmd_1150で設計された意図的なフィルタ。

### 検証方法
STALL-GHOST後にtask_idが正常に設定されるか → 次サイクル(20秒後)で正常検出される。

### なぜ修正しないのか
- resolve_cmd_to_taskは既にbatch化(L731)。原子性はflock+1回writeで最大
- WSL2 NTFSの読み書き遅延は制御不能(OS層)
- STALL-GHOSTフィルタが安全側に倒しており実害なし

---

## パターン3: HOOK-STALE-BUT-BUSY

### 現象
`HOOK-STALE-BUT-BUSY: {ninja} @agent_state=active stale, but pane still busy`
tmux変数@agent_stateが古い(active)のにpaneがbusyパターンに一致。

### 発生頻度
11連続(kagemaru 2026-05-20 18:47〜18:53)。Codex忍者で顕著。

### 一見バグに見える理由
「@agent_stateが更新されない=hookが壊れている」と推論しがち。

### 設計意図と因果
```
Codex CLIがtool実行 → hook(@agent_state=active)発火 → 処理完了
  → 完了hook(@agent_state=idle)が遅延(Codex CLI応答遅延)
  → ninja_monitorが@agent_state=active(古い)を検出
  → しかしpane busyパターン("esc to interrupt"等)がまだ表示中
  → HOOK-STALE-BUT-BUSY: 古いhook状態だがpaneはbusy → 安全側に倒す(BUSY扱い)
  → 最終的にAGENT-STATE-CORRECTION: pane idle確認 → @agent_state=idleに修正
```
**pane busyとhook staleの両方を検出し、安全側(BUSY)に倒す二重確認**。
cmd_1445事故(作業中忍者を/clearした)の対策。

### 検証方法
HOOK-STALE-BUT-BUSY後にAGENT-STATE-CORRECTIONが来ているか → 全件確認済み。

### なぜ修正しないのか
- Codex CLIのhook応答遅延はCLI側の問題(ninja_monitorで制御不能)
- 二重確認(hook+pane)で安全側に倒す設計が正しい
- 修正=hook状態を無条件信頼→cmd_1445再発リスク

---

## パターン4: LOOP-HEALTH-DEBOUNCE

### 現象
`LOOP-HEALTH-DEBOUNCE: WARNING detected but {N}s < 21600s`
gate_loop_health.shがWARNINGを検出したがデバウンス(6時間)内で通知抑止。

### 一見バグに見える理由
「WARNINGが出ているのに通知されない=監視が壊れている」と推論しがち。

### 設計意図と因果
```
gate_loop_health.sh → 忍者/家老/軍師の稼働状態を定期チェック
  → WARNING検出(例: 忍者のidle時間が閾値超過)
  → 前回通知から6時間以内 → デバウンス → 通知抑止
```
**アラート疲弊(alert fatigue)の防止**。同一WARNINGを毎サイクル(20秒)通知すると
殿のntfyが埋まる。6hデバウンスで「最初の1回は通知、以降は抑止」。

### 検証方法
デバウンス期限切れ(6h後)に再通知されるか → ログで確認可能。

---

## カタログの更新ルール

1. インフラバグ調査で「バグではなかった」パターンを発見したらここに追記
2. 各エントリに必須: 現象/発生頻度/一見バグに見える理由/設計意図と因果/検証方法/なぜ修正しないのか
3. 因果は`原因→中間状態→安全弁動作→最終結果`の連鎖で記述
4. パターンが修正されたら(設計意図が変わったら)該当エントリを更新

## 因果リンク

- → [[cmd_1150]] STALL-GHOSTフィルタの設計元
- → [[cmd_1445]] HOOK-STALE-BUT-BUSY二重確認の設計元(作業中/clear事故)
- → [[inbox_write]] codex delivery確認の実装元
- → [[gate_loop_health]] LOOP-HEALTHデバウンスの実装元
- → [[deepdive_why_chain_20260321]] Phase 4: 理解だけでは行動は変わらない→カタログで環境に埋め込む
- → [[STALL-GHOST]] task_id空のSTALL誤検知安全弁
- → [[HOOK-STALE-BUT-BUSY]] hook stale+pane busy二重確認
- → [[codex_delivery_unverified]] ベストエフォート配信確認
- → [[LOOP-HEALTH-DEBOUNCE]] アラート疲弊防止デバウンス
- → [[infra_design_intent_catalog]] 本カタログ自身(セマンティックインデックス概念)
