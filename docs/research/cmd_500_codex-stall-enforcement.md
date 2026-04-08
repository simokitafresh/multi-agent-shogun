# cmd_500 Codex Stall Enforcement

Date: 2026-03-03  
Author: kagemaru  
Scope: `scripts/ninja_monitor.sh`, `config/cli_profiles.yaml`, `tests/unit/test_ninja_monitor_stall.bats`

## §1 目的

- Codex運用で発生する `in_progress + idle` 停滞を「検知のみ」で終わらせず、再起動可能な通知ループと復旧導線を実装する。

## §2 実装内容

### 2.1 STALL再通知の永続抑止を廃止（AC1）
- `STALL_NOTIFIED` を bool から epoch に変更。
- 同一 `ninja:subtask_id` で `STALL_RENOTIFY_DEBOUNCE=300s` を適用し、5分後に再通知可能化。
- 追加ログ: `STALL-DEBOUNCE`.

### 2.2 in_progress停滞時の本人再送（AC2）
- `check_stall()` の `status=in_progress` で閾値超過時、本人へ `task_assigned` を自動送信。
- 追加ログ: `STALL-RECOVERY-SEND`.

### 2.3 Codexしきい値の設定化（AC3）
- `config/cli_profiles.yaml` の `profiles.codex` に `in_progress_stall_min` を追加。
- `check_stall()` は `cli_profile_get(<agent>, in_progress_stall_min)` を参照。
- 未設定・不正値は `20` 分にフォールバック。

### 2.4 複数回停滞エスカレーション（AC4）
- `STALL_COUNT["ninja:subtask_id"]` を `check_stall()` 内で加算。
- 2回目以降で `stall_escalate` を家老へ送信。
- 文言は「差し替え必須」を明記。

## §3 テスト追加（AC5）

- 新規: `tests/unit/test_ninja_monitor_stall.bats`
- 検証項目:
  - 5分デバウンス後の再通知
  - in_progress停滞時の本人再送 + `STALL-RECOVERY-SEND` ログ
  - 同一subtask複数回停滞で `stall_escalate` + 「差し替え必須」

## §4 影響範囲

- `scripts/ninja_monitor.sh`
- `config/cli_profiles.yaml`
- `tests/unit/test_ninja_monitor_stall.bats`
- `context/infrastructure.md`
