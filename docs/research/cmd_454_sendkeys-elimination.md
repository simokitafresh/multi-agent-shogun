# send-keys nudge撤廃 調査+設計
<!-- cmd_454 | 2026-02-28 -->

## §1 おしお殿の実装分析

### 結論

**おしお殿もsend-keysを完全撤廃していない。** やったのは以下:

1. **busy時のnudge完全抑制** — Stop hookが応答完了時にinboxチェック→未読あればblock
2. **flag fileでbusy判定** — `/tmp/shogun_idle_{agent_id}` の有無で判定（capture-pane廃止）
3. **idle時のnudge** — まだsend-keysを使用（ただしbusy時は送らないので衝突しない）
4. **CLIコマンド** — /clear, /model は引き続きsend-keys（代替手段なし）
5. **pty direct write** — 実装されていない（コメントのみ。実コードはsend-keys）

### おしお殿のStop hook実装

`scripts/stop_hook_inbox.sh`:
- stop_hook_active=True → idle flagを作成してexit 0（ループ防止）
- 未読0 → idle flag作成、exit 0（エージェントstop許可）
- 未読あり → idle flag削除、`{"decision":"block","reason":"inbox未読N件あり..."}` 出力
- 応答完了検知: last_assistant_messageから「任務完了」等を検出→自動的にkaroへinbox_write

### おしお殿のflag file方式

| flag状態 | 意味 | 判定場所 |
|----------|------|----------|
| `/tmp/shogun_idle_{id}` 存在 | idle（Stop hook通過、未読なし） | inbox_watcher.sh agent_is_busy() |
| flag不在 | busy（ターン中 or 未読処理中） | 同上 |

我らの`@agent_state` tmux変数方式との比較:
- flag file: プロセス間で即座に共有、atomic、シンプル
- tmux変数: tmuxコマンド必要、タイミング依存、設定元が複数で競合リスク
- **flag fileの方が堅牢**

### おしお殿のsend_wakeup()優先度

```
Priority 1: agent_has_self_watch (inotifywait) → SKIP
Priority 2: agent_is_busy (Claude) → SKIP（Stop hookが配信する）
Priority 3: send-keys nudge（idle時のみ到達）
```

### バージョン履歴

| version | 変更 |
|---------|------|
| v3.4 | Stop hook inbox delivery導入 |
| v3.8 | flag file busy detection（capture-pane方式を置換） |
| v3.9 | false-busy deadlock fix |

## §2 我らの現状send-keys使用箇所マップ

### 撤廃対象（nudge送信）

| ファイル | 行 | 用途 | 頻度 |
|----------|-----|------|------|
| inbox_watcher.sh | L244-268 | send_wakeup() paste-buffer+Enter | 高（inbox更新毎） |
| ninja_monitor.sh | L1162 | idle忍者へのinbox nudge | 中（60秒周期） |
| ninja_monitor.sh | L1180 | idle家老へのinbox nudge | 中（60秒周期） |

### 残存必須（CLIコマンド・起動）— 撤廃しない

| ファイル | 行 | 用途 | 理由 |
|----------|-----|------|------|
| inbox_watcher.sh | L134-191 | send_cli_command() /clear,/model | CLI入力は外部からsend-keys以外の手段なし |
| shutsujin_departure.sh | L461,614-718 | CLI初回起動 | プロセス起動はsend-keys必須 |
| reset_layout.sh | L224-277 | CLI再起動 | 同上 |
| ninja_monitor.sh | L691-764,1407-1409 | /clear送信、CLI再起動 | 同上 |

### 中間層（検討対象）

| ファイル | 行 | 用途 | 検討 |
|----------|-----|------|------|
| inbox_watcher.sh | L253 | send_wakeup()内のpre-clear Enter | nudge自体を廃止すれば不要 |

## §3 Stop hook自己チェック方式の設計

### 現状（cmd_451実装済み）

我らの`stop_check_inbox.sh`は既に以下を実装:
- stop_hook_active=True → exit 0（ループ防止）
- shogun → exit 0（スキップ）
- 未読あり → `{"decision":"block","reason":"inbox未読N件"}` で停止拒否
- 未読なし → exit 0（停止許可）

### おしお殿との差分

| 機能 | 我ら | おしお殿 | 対応 |
|------|------|---------|------|
| Stop hook inbox check | cmd_451実装済み | 同等 | 済 |
| idle flag file | **なし**（@agent_state使用） | あり | 要追加 |
| busy時nudge抑制 | @agent_state=activeでSKIP | flag不在でSKIP | 改修必要 |
| 応答完了自動検知 | なし | last_assistant_messageから検出 | 検討（ROI低） |
| /clear後cooldown | なし | 30秒cooldown | 要追加 |

### 設計: Phase構成

#### Phase 1: flag file導入 + busy時nudge抑制

**目的**: busy時のnudgeを構造的に止める。/clear衝突問題の根本解決。

変更対象:
1. `scripts/hooks/stop_check_inbox.sh` — idle flag作成/削除を追加
2. `scripts/inbox_watcher.sh` — agent_is_busy()をflag fileベースに変更（Claude用）
3. `scripts/inbox_watcher.sh` — send_wakeup()にbusy時SKIP追加

動作:
```
Stop hook発火 → 未読なし → /tmp/shogun_idle_{id} 作成 → exit 0
Stop hook発火 → 未読あり → flag削除 → block
inbox_watcher → flag存在(idle) → nudge送信OK
inbox_watcher → flag不在(busy) → SKIP（Stop hookが配信する）
```

#### Phase 2: /clear後cooldown追加

**目的**: /clear送信後30秒間はnudge抑制。/clear+inbox衝突の直接対策。

変更対象:
- `scripts/inbox_watcher.sh` — send_cli_command()で/clear送信時にLAST_CLEAR_TS記録
- `scripts/inbox_watcher.sh` — agent_is_busy()でcooldownチェック追加

#### Phase 3: ninja_monitor.shのnudge統合

**目的**: ninja_monitor.shのnudge送信もflag fileベースに統一。

変更対象:
- `scripts/ninja_monitor.sh` — inbox nudge送信前にflag fileチェック追加

#### Phase 4: 効果計測 + nudge頻度最適化

**目的**: Phase 1-3の効果を計測し、nudge debounce間隔を最適化。

計測:
- [SKIP] busy SKIP回数 / 全nudge試行回数
- Stop hook block回数 / 全Stop発火回数
- nudge到達後の応答時間（flag作成→次のファイル変更）

## §4 段階的移行計画

| Phase | 内容 | 判断基準 | cmd分割 |
|-------|------|----------|---------|
| 1 | flag file + busy時nudge抑制 | 実装→テスト→24h運用で衝突0件 | cmd_455 |
| 2 | /clear後cooldown | Phase 1運用で/clear衝突が残る場合のみ | cmd_456 |
| 3 | ninja_monitor nudge統合 | Phase 1-2安定後 | cmd_457 |
| 4 | 効果計測 | Phase 1-3完了後 | (計測のみ、cmd不要) |

**Phase 1が最重要。Phase 2-3はPhase 1の効果次第。**

Phase 1の実装cmd (cmd_455) の粒度:
- AC1: stop_check_inbox.sh にidle flag作成/削除を追加
- AC2: inbox_watcher.sh のagent_is_busy()をflag fileベースに変更（Claude用）
- AC3: inbox_watcher.sh のsend_wakeup()でbusy時SKIP追加
- AC4: 24h運用でsend-keys衝突0件を確認

## §5 リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| flag fileが残留（Stop hookが発火しない場合） | エージェントが永久idle扱い→nudge届かない | ninja_monitorが120秒idle検知→flag削除+/clear |
| flag file競合（複数プロセスが同時操作） | 状態不整合 | touchとrmはatomic。問題なし |
| Codex忍者にはStop hookがない | flag fileが作成されない | Codex用は既存の@agent_state方式を維持 |
| /tmp再起動で消える | WSL2再起動でflag全消失→全員busy扱い | 起動スクリプト(shutsujin)でflag初期化 |
| stop_check_inbox.shの変更でregressionn | inbox未読チェックが壊れる | 既存のbatsテスト+手動テスト |

### send-keys「完全撤廃」は不可能

CLIコマンド送信(/clear, /model)とCLI起動はsend-keys以外に方法がない。
**撤廃できるのはnudge送信のみ**。正確な目標は:

> **「busy時のsend-keys nudgeゼロ」= /clear衝突問題の根本解決**

idle時のnudgeはsend-keysで送っても問題ない（エージェントが入力待ちなので衝突しない）。
