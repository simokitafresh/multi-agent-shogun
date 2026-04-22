# 英語化ロールバック設計書
<!-- session: 2026-04-22, author: shogun -->

## 目的

殿裁定: 英語化により全エージェントの日本語理解が著しく低下。全て日本語に戻す。

## 現物確認結果

### 英語化コミット一覧（ロールバック対象）

| # | commit | 内容 | 変更ファイル |
|---|--------|------|-------------|
| 1 | `c65492ee` | CLAUDE.md + AGENTS.md 英語化 | CLAUDE.md, AGENTS.md |
| 2 | `48822b8a` | inbox_write/deploy_task/gate出力英語化 | scripts 4本 + tests 6本 |
| 3 | `1082b211` | 小infra script英語化 + .bak作成 | scripts 3本 + .bak 3本 + tests 1本 |
| 4 | `d7fcabde` | deploy_task.sh .bak作成のみ | .bak 1本 |
| 5 | `ea9b0154` | deploy_task警告テスト英語化追随 | tests 2本 |
| 6 | `fbdc4a04` | report template gateテスト英語化追随 | tests 1本 |

### 英語化後の非英語化改善（保存必須）

| commit | 内容 | 保存方法 |
|--------|------|---------|
| auto-commit群 | CLAUDE.md File Reading Rule例外拡充（7項目追加） | Phase 1で手動再適用 |
| `02104f6b` | instructions/gunshi.md BULLETIN_NOTIFY targeting rule | 英語化未影響。そのまま保存 |
| `511e5e1c` | pane_lookup.sh agent_id修正 | 英語化未影響。そのまま保存 |
| `3cd0ce8d` | dm-signal context索引鮮度更新 | 英語化未影響。そのまま保存 |
| `fbcc9228` | 英語化検証記録 | 英語化未影響。そのまま保存 |
| `41c7df17` | 軍師レビューログ追加 | 英語化未影響。そのまま保存 |

### 重要な発見

- **instructions/*.md は英語化されていない**（`c65492ee`はCLAUDE.md+AGENTS.mdのみ）
  → 軍師Phase 2は不要
- .bakが存在しないスクリプト: `cmd_complete_gate.sh`（コメント1行）, `gate_report_format_main.py`（WARN文言3行）
  → 手動で日本語に戻す

## ロールバック手順（3 Phase）

### Phase 1: CLAUDE.md + AGENTS.md復元（最優先）

全エージェントが毎セッション読むため最優先。

```bash
# AGENTS.md: 英語化後の変更なし。安全に丸ごと復元
git show 8af962ca:AGENTS.md > AGENTS.md

# CLAUDE.md: 英語化後に改善あり。丸ごと復元後、改善を手動再適用
git show 8af962ca:CLAUDE.md > CLAUDE.md
```

**CLAUDE.md手動再適用（必須）**: 以下のFile Reading Rule例外拡充を再適用する。

復元後のCLAUDE.mdの該当箇所:
```
80行読込ルールの例外: deepdive（phase逐次読込）、context/*.md（§指定読込）
```
↓ これを以下に差し替え:
```
Exceptions:
- `memory/deepdive_*.md` (phase-by-phase sequential read, enumerated: `deepdive_why_chain_20260321.md`, `deepdive_causal_tracing_20260415.md`, `deepdive_karo_verification_20260405.md`, `deepdive_backward_validation_20260327.md`)
- `memory/dialogue_*.md` (research journals — tail-only read by default, full read when Lord directs)
- `context/*.md` (section-targeted read by `§`)
- `instructions/*.md` (role rules, read in full)
- `projects/infra/lessons_{role}.yaml` (startup gate requires full read)
- `projects/{id}.yaml` (core knowledge incl. PI/DB rules/UUIDs, read in full)
- `queue/bulletin_board.yaml` (prepend-ordered; startup gate reads latest entries automatically)
Reason: 80行で日本語YAML ≈ 2,400トークン、英語YAML ≈ 960トークン。Lost-in-the-Middle劣化閾値(~2,600トークン)以内。80行制限は英語には保守的だが日英混在移行期の安全マージン。
```

### Phase 2: スクリプト復元

#### 2a: .bakファイルで復元（4本）
```bash
cp scripts/deploy_task.sh.bak.20260422 scripts/deploy_task.sh
cp scripts/inbox_write.sh.bak.20260422 scripts/inbox_write.sh
cp scripts/karo_workaround_log.sh.bak.20260422 scripts/karo_workaround_log.sh
cp scripts/gunshi_review_stats.sh.bak.20260422 scripts/gunshi_review_stats.sh
```

#### 2b: .bakなしスクリプトの手動復元（2本）

**cmd_complete_gate.sh** L2657 コメント1行:
```
現在: # ─── reviewed:false leftover check (retired: moved to push-style flow in cmd_533) ───
復元: # ─── reviewed:false残存チェック（廃止: cmd_533でpush型に移行） ───
```

**gate_report_format_main.py** WARN文言3行:
```
現在: "GP-199 WARN: before_metrics is missing — GP/improvement cmds must record the measurement before implementation"
復元: "GP-199 WARN: before_metrics未記入 — GP/改善cmdは実装前の計測値を記録せよ"

現在: "GP-199 WARN: after_metrics is missing — GP/improvement cmds must record the measurement after implementation"
復元: "GP-199 WARN: after_metrics未記入 — GP/改善cmdは実装後の計測値を記録せよ"

現在: "GP-199 WARN: regression is missing — GP/improvement cmds must record regression as yes/no"
復元: "GP-199 WARN: regression未記入 — GP/改善cmdは退化有無を yes/no で記録せよ"
```

#### 2c: .bakファイル削除
```bash
rm scripts/deploy_task.sh.bak.20260422
rm scripts/inbox_write.sh.bak.20260422
rm scripts/karo_workaround_log.sh.bak.20260422
rm scripts/gunshi_review_stats.sh.bak.20260422
```

### Phase 3: テスト復元

英語出力を期待するように変更されたテストを日本語出力に戻す。

```bash
# ea9b0154の変更を戻す（deploy_task警告テスト）
git show ea9b0154~1:tests/unit/test_deploy_task_clarity_warnings.bats > tests/unit/test_deploy_task_clarity_warnings.bats
git show ea9b0154~1:tests/unit/test_deploy_task_same_ninja_redeploy.bats > tests/unit/test_deploy_task_same_ninja_redeploy.bats

# fbdc4a04の変更を戻す（report template gateテスト）
git show fbdc4a04~1:tests/unit/test_report_template_gate_compat.bats > tests/unit/test_report_template_gate_compat.bats

# 48822b8aで変更されたテスト6本を戻す
git show 48822b8a~1:tests/unit/test_deploy_task_ac_handling.bats > tests/unit/test_deploy_task_ac_handling.bats
git show 48822b8a~1:tests/unit/test_deploy_task_ac_version.bats > tests/unit/test_deploy_task_ac_version.bats
git show 48822b8a~1:tests/unit/test_deploy_task_draft_review.bats > tests/unit/test_deploy_task_draft_review.bats
git show 48822b8a~1:tests/unit/test_deploy_task_lifecycle.bats > tests/unit/test_deploy_task_lifecycle.bats
git show 48822b8a~1:tests/unit/test_deploy_task_template_generation.bats > tests/unit/test_deploy_task_template_generation.bats
git show 48822b8a~1:tests/unit/test_inbox_write.bats > tests/unit/test_inbox_write.bats

# 1082b211で変更されたテスト1本を戻す
git show 1082b211~1:tests/unit/test_karo_workaround_validation.bats > tests/unit/test_karo_workaround_validation.bats
```

### 検証（全Phase完了後）

1. `bats tests/unit/` — テスト全PASS確認
2. CLAUDE.md先頭40行が日本語であることを目視確認
3. `git diff --stat` で意図しない変更がないことを確認

## NOT in scope

- instructions/*.md の変更（英語化されていないため不要）
- context/*.md / projects/*.yaml の変更（英語化されていないため不要）
- DM-Signalリポジトリの変更（cmd_2229のend_date追加は別件）

## リスク

| リスク | 深刻度 | 緩和策 |
|--------|--------|--------|
| Phase 1 CLAUDE.md手動再適用の漏れ | HIGH | ACで差分確認を必須化 |
| テスト復元後にスクリプト復元とのアサーション不一致 | MEDIUM | Phase 2→3の順序厳守+bats全実行 |
| .bak削除後に再度必要になる | LOW | git historyに残っている |

## cmd分割

1 cmdで全Phase実行可。ファイル数は多いが全て機械的な復元操作で、判断が必要なのはCLAUDE.md手動再適用のみ。
