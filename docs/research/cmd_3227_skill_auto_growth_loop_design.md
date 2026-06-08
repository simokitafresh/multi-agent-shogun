# 全スキル自動成長ループ共通基盤設計
<!-- cmd: cmd_3227 -->
<!-- date: 2026-06-08 -->
<!-- author: hayate -->

## §1 目的

殿指摘: 各論パッチではなく全スキル・今後作るスキルにも適用される自動成長の仕組みが必要。

全ステップ（実行→検知→修行→再現性確認→スキル更新）を共通基盤で自動化する。

## §2 自動成長ループの全体像

```
スキル実行
  → 結果記録(PASS/FAIL)     ← skill_execution_log.sh / skill_gate_feedback.sh
  → 失敗パターン分析          ← skill_auto_improve.sh --apply
  → SKILL.md防止ステップ注入  ← skill_auto_improve.sh apply_prevention_steps()
  → 改善効果なし検知           ← skill_auto_improve.sh escalation(unchanged_streak)
  → 修行課題生成               ← ★穴(1): 手動
  → 修行実行                   ← deploy_task.sh + training cycle
  → 再現性確認                 ← ★穴(2): 手動(3+忍者一発PASS)
  → SKILL.md成長反映           ← ★穴(3): 手動
```

## §3 現状の穴一覧

### 穴(1): 実行結果記録が各スキル個別実装→未接続スキルは失敗が見えない

**現状**: 実行結果がskill_execution_log.yamlに記録されるスキルは以下の経路のみ:

| 記録経路 | 対象スキル | 接続状況 |
|---------|-----------|---------|
| gate_report_format.sh → skill_gate_feedback.sh | report-write, verdict-check | **接続済み** |
| cmd_complete_gate.sh → skill_gate_feedback.sh | cmd-complete | **接続済み** |
| dashboard_update.sh → skill_execution_log.sh | dashboard-update | **接続済み** |
| 手動呼び出し | 残り36スキル | **未接続** |

**定量**: 40スキル中4スキルのみが自動記録(10%)。36スキルは失敗しても記録されない。

skill_metrics.shの出力で確認: 36スキルがN/A(0件記録)。

**原因**: 各スキルの実行結果をログに書く処理が、各ゲート・スクリプト個別に組み込まれている。共通のhookやフレームワークがない。

**修正設計**:

Claude Code Skill toolはSettings hook(`PostToolUse`)でフック可能。Skill toolの`PostToolUse`イベントで以下を自動記録:

```
トリガー: PostToolUse hook (tool_name == "Skill")
処理:
  1. hook input JSONからスキル名を取得
  2. 実行後のエージェント応答(tool_result)からPASS/FAILを判定
     - gate実行があればgate結果を優先
     - なければ「成功/失敗」キーワードヒューリスティクス
  3. skill_execution_log.sh <skill> <executor> <result> <stumbling_points> を呼出
```

**具体的変更箇所**:

| ファイル | 変更内容 |
|---------|---------|
| `.claude/hooks/post-skill-execution.sh` (新規) | PostToolUse hook: Skill tool実行後にskill_execution_log.shを呼出 |
| `settings.json` | PostToolUseにpost-skill-execution.shを追加 |

**制約・注意点**:
- PostToolUseはtool_resultにアクセスできるが、permissionDecision:denyは効かない(L282)
- 結果判定のヒューリスティクスは初期は粗くてよい。gate連携済みスキル(report-write等)はgate結果が正確なため、未接続スキルの大枠把握が目的
- Skill toolの入力JSONフォーマト: `{"tool_name": "Skill", "tool_input": {"skill": "name", "args": "..."}}`

### 穴(2): 失敗→修行課題生成が手動

**現状**: 修行サイクル(context/training-cycle.md)のLevel配備は全て家老が手動で設計・配備。

- 修行対象スキルの選定: 家老が手動
- 修行レベルの判定: 家老が手動
- 修行タスクYAML生成: 家老が手動(deploy_task.sh経由)
- 修行完了後の分析: 家老が手動

**原因**: skill_auto_improve.shのescalation機構(unchanged_streakで掲示板通知)は存在するが、通知後の修行配備は将軍→家老→忍者の手動フロー。

**修正設計**:

skill_auto_improve.shのescalation判定後に、修行課題を自動生成するフローを追加:

```
escalation判定(unchanged_streak >= threshold)
  ├─ classification == "code_fix_required" → 既存: 掲示板通知でcmd起票要請
  └─ classification == "skill_doc_improvable" かつ 3回連続unchanged
      → ★新規: training_task_generator.sh を呼出
         1. FAILパターンからBLOCKパターン#を特定(training-cycle.md §2参照)
         2. 忍者のFP率をgate_fire_logから取得し、修行レベルを自動判定
         3. deploy_task.sh --direct 用のタスクYAML骨格を生成
         4. 家老inboxに「修行課題生成済み。配備確認せよ」と通知
```

**具体的変更箇所**:

| ファイル | 変更内容 |
|---------|---------|
| `scripts/training_task_generator.sh` (新規) | FAILパターン→修行レベル判定→タスクYAML骨格生成 |
| `scripts/skill_auto_improve.sh` | escalation後にtraining_task_generator.shを呼出す分岐追加(L293付近) |
| `scripts/ninja_monitor.sh` | idle忍者検知時にskill_auto_improve.sh --apply定期実行(既存のtraining auto trigger §2 L66拡張) |

**制約・注意点**:
- 完全自動配備はしない。家老確認を挟む(安全弁)。生成=提案、配備=家老判断
- 修行対象スキルは現行gate_fire_logの実績BLOCKパターン(12パターン)にマッピング
- 新スキル追加時もFAILパターンがskill_execution_logに蓄積→閾値超過→自動で修行課題生成される

### 穴(3): 修行完了→SKILL.md更新が手動

**現状**: 修行で得た知見(lesson_candidate, 環境改善)は手動でSKILL.mdに反映。

- 修行Round結果のFP率計算: 家老が手動
- テンプレート改善(inline hint, footer checklist等): 家老が手動設計
- SKILL.md更新: 家老がEdit

**原因**: skill_auto_improve.shは実行ログからSKILL.mdに「自動防止ステップ」を追記できるが、修行結果(gate_fire_log)とSKILL.mdの対応が自動化されていない。

**修正設計**:

修行完了時(3+忍者が一発PASS)に、修行中の環境改善をSKILL.mdの「### 自動防止ステップ」に自動反映:

```
修行PASS検知(gate_fire_log解析)
  → 修行cmd群のFP率計算
  → 3+忍者一発PASS (=修行完了基準)
  → 修行中のBLOCKパターンと環境改善の対応を抽出
  → skill_auto_improve.sh --apply が防止ステップを更新
  → 修行完了ステータスをtraining-cycle.mdに追記(家老確認後)
```

**具体的変更箇所**:

| ファイル | 変更内容 |
|---------|---------|
| `scripts/training_completion_check.sh` (新規) | 修行cmd群のgate_fire_log解析→FP率→完了判定→skill_auto_improve呼出 |
| `scripts/skill_auto_improve.sh` | 修行由来のFAILパターンを区別するsource=training_*フィルタ追加 |
| `scripts/ninja_monitor.sh` | 修行cmd完了検知時にtraining_completion_check.shを呼出 |

**制約・注意点**:
- training-cycle.mdの実績セクション(§4-§18)は手動追記を維持(分析の深さが機械生成では不十分)
- 自動化対象は「SKILL.md防止ステップの追記」と「完了判定」のみ

## §4 共通基盤アーキテクチャ

### 全体図: 自動成長ループの接続

```
[スキル実行]
     │
     ▼
[PostToolUse hook: post-skill-execution.sh]──────────┐
     │                                               │
     ▼                                               ▼
[skill_execution_log.yaml]              [skill_gate_feedback.sh]
     │                                         │
     ▼                                         ▼
[skill_auto_improve.sh --apply]         [SKILL.md 注意ポイント追記]
     │
     ├─ 防止ステップ追記 → [SKILL.md 自動防止ステップ]
     │
     ├─ unchanged_streak >= 3
     │   └─ code_fix_required → 掲示板通知
     │   └─ skill_doc_improvable → [training_task_generator.sh] ★新規
     │                                      │
     │                                      ▼
     │                              [タスクYAML骨格生成]
     │                                      │
     │                                      ▼
     │                              [家老inbox通知]
     │                                      │
     │                                      ▼
     │                              [家老がdeploy_task.sh配備]
     │                                      │
     │                                      ▼
     │                              [忍者が修行実行]
     │                                      │
     │                                      ▼
     │                              [gate_fire_log記録]
     │                                      │
     │                                      ▼
     │                        [training_completion_check.sh] ★新規
     │                                      │
     │                           3+忍者一発PASS?
     │                           YES ▼         NO → 次Round
     │                    [skill_auto_improve.sh]
     │                              │
     └──────────────────────────────┘ (ループ閉じ)
```

### 新規スキル追加時の自動接続

今後作るスキルに自動適用される理由:

1. **PostToolUse hook**: Skill tool全体をフックするため、新スキルも自動的に実行記録される
2. **skill_auto_improve.sh**: skill_execution_log.yamlの全スキルを対象に動作するため、新スキルのFAILも自動検出
3. **training_task_generator.sh**: FAILパターンからの修行課題生成は汎用ロジック(BLOCKパターン12種にマッピング)
4. **skill_gate_feedback.sh**: GATE_SKILL_MAPに新しいgate→skill対応を追加するだけで接続完了

### 既存インフラとの接続点

| 既存コンポーネント | 接続方法 | 追加作業 |
|------------------|---------|---------|
| ninja_monitor.sh | idle検知→skill_auto_improve定期実行(既存拡張) | shug修行auto trigger拡張 |
| deploy_task.sh | 修行タスクYAML配備(既存) | 変更なし |
| gate_fire_log.yaml | 修行結果記録(既存) | 変更なし |
| gate_report_format.sh | 報告YAML検証(既存) | 変更なし |
| bulletin_write.sh | escalation通知(既存) | 変更なし |
| skill_metrics.sh | スキル品質スコア計算(既存) | N/Aスキル減少で自動改善 |

## §5 新規ファイル一覧と責務

| ファイル | 責務 | 行数見積 | テスト |
|---------|------|---------|--------|
| `.claude/hooks/post-skill-execution.sh` | Skill tool PostToolUse → 実行結果記録 | ~60行 | tests/unit/test_post_skill_execution.bats |
| `scripts/training_task_generator.sh` | FAILパターン→修行タスクYAML骨格生成 | ~120行 | tests/unit/test_training_task_generator.bats |
| `scripts/training_completion_check.sh` | 修行完了判定(FP率計算+3忍者基準) | ~80行 | tests/unit/test_training_completion_check.bats |

## §6 段階的実装計画

### Phase 1: 全スキル実行結果の自動記録（穴1解消）

- post-skill-execution.sh新規作成
- settings.json PostToolUse追加
- テスト作成・実行
- **効果**: 40スキル中36スキルのN/A解消。全スキルのPASS/FAIL率が可視化

### Phase 2: 修行課題自動生成（穴2解消）

- training_task_generator.sh新規作成
- skill_auto_improve.shにトリガー追加
- テスト作成・実行
- **効果**: 家老の修行設計工数削減。FAILパターン蓄積→自動で修行課題が生まれる

### Phase 3: 修行完了→SKILL.md自動更新（穴3解消）

- training_completion_check.sh新規作成
- ninja_monitor.shに完了検知トリガー追加
- テスト作成・実行
- **効果**: 修行完了→SKILL.md成長のループが閉じる。手動介入なしで自動成長が回る

## §7 全スキル自動成長の実現条件

Phase 1-3が完了すると:

```
新スキル作成
  → 忍者がスキル使用
  → PostToolUse hookが自動記録           ← Phase 1
  → FAILパターン蓄積
  → skill_auto_improve.shが防止ステップ追記
  → 改善が効かない
  → training_task_generator.shが修行課題生成 ← Phase 2
  → 忍者が修行実行
  → 完了判定→SKILL.md自動更新            ← Phase 3
  → 次のFAILサイクルへ
```

**新スキル作成者が意識することはゼロ**。共通基盤が全自動で成長ループを回す。
