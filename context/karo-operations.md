# 家老運用操作詳細手順 — 参照元: instructions/karo.md | cmd_383/subtask_383_impl_a | cmd_406/subtask_406_impl_b

## ダッシュボードAUTO/KARO分離（cmd_406）
- **AUTO域** (`DASHBOARD_AUTO_START`〜`END`): `dashboard_auto_section.sh`が自動生成（忍者配備/パイプライン/メトリクス）。家老は触れるな
- **KARO域** (`KARO_SECTION_START`〜`END`): 家老のみ更新（進行中/最新更新/調査結果/要対応/戦果）
- 戦況メトリクス・モデル別スコアボード・知識サイクル健全度・稼働忍者はAUTO側で自動。手動転記不要
- `dashboard_update.sh`の主機能（最新更新エントリ追加）は従来通りKARO域内に挿入

## §1 配備（Deployment Checklist）
> タスク配備前の必須チェックリスト。STEP 1-6を毎回実行せよ。

```
STEP 1: idle忍者の棚卸し
  → tmux capture-pane で全忍者ペインを確認（❯あり=idle）
  → idle忍者の名前とCTXをリスト化
STEP 2: タスク分割の最大化
  → pending cmdの数を確認
  → 各cmdのSTEP/ACを独立単位に分解
  → 分解した単位数 = 必要忍者数
STEP 3: 配備計画（idle忍者数 ≥ タスク単位数になるまで統合）
  → idle忍者 6名、タスク単位 4個 → 4名配備（2名は次cmd待ち）
  → idle忍者 3名、タスク単位 6個 → 3名配備（依存あるものはblocked_by）
  → idle忍者 6名、タスク単位 1個 → 分割が本当に不可能か再検討
STEP 4: 知識自動注入(deploy_task.shが自動処理)
  → deploy_task.shが配備時にtask YAMLのproject/title/descriptionからキーワード抽出し、
    projects/{id}/lessons.yamlとスコアリング照合して上位5件をrelated_lessonsに自動注入。
    家老がrelated_lessonsを手動記載する必要はない。
    ただしdescriptionへの関連教訓ポインタは引き続き推奨（冗長な安全網）。
  → 忍者の「読み忘れ」を構造的に排除
STEP 5: 配備実行
  → 5a: Read queue/tasks/{ninja_name}.yaml
  → 5b: Write/Edit queue/tasks/{ninja_name}.yaml
  → 5c: inbox_write → stop
STEP 5.5: 偵察ゲート(deploy_task.shが自動強制 — implタスク時のみ)
  → deploy_task.shがtask_type=implementの配備時に自動チェック:
    a. shogun_to_karo.yamlに scout_exempt: true → PASS（偵察免除）
    b. 同一parent_cmdのscout/reconタスクがdone 2件以上 → PASS（偵察済み）
    c. どちらもなし → BLOCK(exit 1) + エラーメッセージ表示
  → BLOCK時: 将軍にscout_exempt申請するか、先に偵察を配備せよ
  → 家老にscout_exempt免除の判断権はない（将軍のみ）
  → scout/recon/reviewタスク自体の配備はゲート対象外（無条件PASS）
STEP 6: 配備後チェック(スクリプト強制 — 偵察タスク時のみ)
  → bash scripts/task_deploy.sh cmd_XXX recon
  → exit 0以外 → 2名体制に修正するまで配備やり直し
  → 偵察以外のtask_type(implement/review/other)はスキップ
```

## §2 分解パターン（Task Decomposition Patterns）
> cmd受領時の5パターン即時分解手順。毎回ゼロから考えるな。

### cmdフラグ3分岐（将軍がcmd YAMLに明示）

| フラグ | 意味 | 家老の対応 |
|--------|------|-----------|
| `scout_exempt: true` | 偵察省略。仕様が明確で直接実装可 | implサブタスクのみ作成・配備 |
| `scout_only: true` | 偵察のみ。情報収集が目的 | scoutサブタスクのみ作成・配備。impl不要 |
| どちらもなし | フルフロー | 全フェーズ(scout+impl+review)のサブタスクを事前一括作成 |

**判断権**: 家老にscout_exempt/scout_onlyの判断権はない。将軍が発令時に明示する。

### Pattern Selection Flow
```
cmd受領 → まずcmdフラグを確認:
  ├─ scout_exempt: true → 偵察省略。直接実装へ
  ├─ scout_only: true  → 偵察のみ。implフェーズなし（偵察完了=cmd完了）
  └─ どちらもなし     → フルフロー（偵察→実装→レビュー）
フルフロー時 → 「このcmdはどのパターンの組合せか？」
  ├─ 調査が必要か？ → YES → recon(2名) + 後続パターン
  ├─ 複数ファイルに分割可能か？ → YES → impl_parallel(N名)
  ├─ 単一ファイル/密結合か？ → YES → impl(1名)
  ├─ コード変更あり？ → YES → review(1名)追加
  └─ 複数成果物の統合必要？ → YES → integrate(1名)追加
例: recon(2名) → impl_parallel(2名) → review(偵察者1名)
```

### 5 Patterns Summary

| # | Pattern | 人数 | 特徴 | 使用例 |
|---|---------|------|------|--------|
| 1 | recon (偵察) | 2名 | 独立並行、同じ対象 | 未知領域の調査、仮説検証 |
| 2 | impl (実装_単独) | 1名 | 単一ファイルor密結合 | バグ修正、小規模機能追加 |
| 3 | impl_parallel (実装_並列) | N名 | 各自が別ファイル | 大規模改修、複数機能並行 |
| 4 | review (レビュー) | 1名 | 実装者以外が検証 | コード品質、push前確認 |
| 5 | integrate (統合) | 1名 | blocked_by複数タスク | 偵察統合、成果物マージ |

### Subtask Naming Convention（4分類）

| 分類 | 命名パターン | 内容 |
|------|-------------|------|
| scout | subtask_XXX_scout_* | コード調査・構造分析 |
| impl | subtask_XXX_impl_* | 実装・コード変更 |
| review | subtask_XXX_review_* | コードレビュー |
| design | subtask_XXX_design_* | 合議・設計 |

### Pattern Details（5パターン詳細）

**1. recon (偵察)** — `task_type: recon`
- 2名独立並行。同じ対象を異なる観点で調査
- 完了後 `report_merge.sh` で統合判定
- 仮説A/B寄りの観点で独立調査、両方に全仮説を網羅させる
- 例外: 事前知識十分 or idle genin忍者1名のみ → スキップ可

**2. impl (実装_単独)** — `task_type: implement`
- 1名、単一ファイルまたは密結合な複数ファイル
- commitまで（pushはしない）→ review配備

**3. impl_parallel (実装_並列)** — `task_type: implement`
- N名、各自が別ファイル。**同一ファイルを複数忍者が触ること禁止**（RACE-001）
- 各忍者に明確な担当ファイル/領域を指定
- 全員完了後にreview or integrateで品質確認

**4. review (レビュー)** — `task_type: review`
- 1名、diff確認 + PASS判定 + push
- **実装者≠レビュー者（必須）**。修正者≠レビュー者も同様
- レビュータスクは忍者に配備せよ。家老の役割は配備とGATE判定のみ

**5. integrate (統合)** — `task_type: integrate`
- 1名、`blocked_by: [subtask_A, subtask_B, ...]`
- 偵察統合は `report_merge.sh` → 統合分析の2段階
- `templates/integ_*.md` 参照

### Review Assignment Rules

| 条件 | 担当 | 理由 |
|------|------|------|
| 偵察済み + 別忍者が実装 | **偵察者**がレビュー | コード知識が最も深い |
| 偵察者 = 実装者 | **別忍者** | 独立性確保 |
| bloom_level L4以上（思考型） | **jonin必須** | 推論・評価が必要 |
| bloom_level L3以下（照合型） | **genin可** | 手順照合のみ |
| 偵察報告あり | reports_to_readで自動注入 | 知識の引き継ぎ保証 |

### Common Combinations

| 組合せ | パイプライン | 適用場面 |
|--------|------------|---------|
| 偵察→実装→レビュー | recon(2) → impl(1) → review(1) | 未知バグ調査→修正→検証 |
| 並列実装→レビュー | impl_parallel(N) → review(1) | 複数ファイル同時改修 |
| 実装→レビュー | impl(1) → review(1) | 単純機能追加 |
| 偵察→並列実装→統合 | recon(2) → impl_parallel(N) → integrate(1) | 大規模機能開発 |
| 実装のみ | impl(1) | 機械的変更（レビュー省略可） |

### サブタスクYAML事前一括作成ルール（cmd_367追加）
> cmd受領時に全フェーズのサブタスクYAMLを一括事前作成。auto_deploy_next.shの前提条件。

```
1. cmd受領 → Pattern Selection Flowでパイプライン決定
   例: recon(2) → impl(1) → review(1)
2. 全フェーズのサブタスクYAMLを同時に作成
   - subtask_XXX_scout_a.yaml  → status: pending（即時deploy_task.sh）
   - subtask_XXX_scout_b.yaml  → status: pending（即時deploy_task.sh）
   - subtask_XXX_impl_a.yaml   → status: pending, blocked_by: [scout_a, scout_b], auto_deploy: true
   - subtask_XXX_review_a.yaml → status: pending, blocked_by: [impl_a], auto_deploy: true
3. 偵察サブタスクのみ即座にdeploy_task.shで配備
   後続フェーズはauto_deploy_next.shが自動配備する
```

#### 後続フェーズの必須フィールド

| フィールド | 値 | 理由 |
|-----------|-----|------|
| blocked_by | [前フェーズのサブタスクID一覧] | 依存関係をauto_deploy_next.shが参照 |
| auto_deploy | true | 前フェーズ完了時の自動配備トリガー |
| status | pending | 配備待ち状態 |
| assigned_to | （空または未指定） | auto_deploy時にidle忍者に割当 |

`scout_only: true` の場合はimplサブタスクの事前作成不要。
**なぜ事前作成が必要か**: auto_deploy_next.shは既存YAMLのblocked_byを解決する仕組み。YAMLが存在しなければ「後続タスクなし」と判断し停止する。家老の/clearやidle化で偵察→実装の接続が途切れる問題の根本対策。

## §3 レビューサイクル
> 実装完了後のレビュー→修正→再レビューループ。家老の役割はレビュー配備+GATE判定のみ。

```
実装完了(忍者A) → 家老がレビュー配備(忍者B) → 忍者Bレビュー
  ├─ LGTM(指摘なし) → GATE判定に進む
  └─ 指摘あり → 家老が修正配備(忍者C) → 忍者C修正
       → 家老が再レビュー配備(忍者D) → 忍者Dレビュー → (ループ)
```

| ルール | 内容 | reason |
|--------|------|--------|
| 実装者≠レビュー者 | 忍者Aが実装 → 忍者B(≠A)がレビュー | 自分のコードは自分で見落とす |
| 修正者≠再レビュー者 | 忍者Cが修正 → 忍者D(≠C)が再レビュー | 確証バイアス防止 |
| 家老のレビュー配備義務 | 品質判定は忍者レビューに委ねよ | 家老がレビューすると教訓が生まれない |
| ループ終了条件 | レビュー者がLGTM(指摘なし)を報告YAMLに記載 | 明示的LGTMなしだとGATEが機能しない |
| 修正者の選択 | 元の実装者(忍者A)の再起用可。ただしレビューは必ず別忍者 | 実装者は最も文脈を持つ修正者 |

#### レビュータスクYAML必須フィールド
- `task_type: review` / `description`: レビュー観点（AC充足+コード品質） / `target_path`: 対象ファイル
- 報告形式: `review_result: PASS or FAIL` + 各ACのPASS/FAIL判定

#### 修正タスクYAML必須フィールド
- `task_type: implement` / `description`: レビュー指摘事項（行番号+修正内容）
- `blocked_by`不要（レビュー報告を家老がdescriptionに転記）

### コードレビュー自動配備（AC3対応 — push報告受理時に毎回確認）
忍者の報告にgit commit(push前)が含まれる場合:
1. 報告にcommitハッシュがあるか確認
2. push済み → レビュー省略済みでないか確認。省略理由なき場合は🚨報告
3. commit済み+push未 → 別忍者にレビュータスクを自動配備（diff確認+構文チェック+push）
4. レビューPASS → push完了 → 次ステップに進む
5. 機械的変更(typo/import追加等)は家老判断でレビュー省略可
6. レビューFAIL → 修正タスク配備 → 再レビュー → LGTMまでループ
7. 品質判定は忍者レビューに委ねよ。家老の役割はレビュータスクの配備とGATE判定のみ

## §4 難問エスカレーション
> 失敗した時の増員原則。偵察2名並行（予防措置）とは別原則（失敗からの学習増幅）。

### 基本の型
```
1名で着手 → 成功なら次へ
1名で失敗 → 同一タスクを2名に丸ごと独立で振る → 知見統合 → 再挑戦
```

| # | 原則 | 理由 |
|---|------|------|
| 1 | 2名には**同じタスク説明**を渡す | 偵察と同じ「独立並行」原則 |
| 2 | 失敗も知見。事前の知見共有は不要 | 1名目の報告を2名目に見せない（独立性担保） |
| 3 | 無駄とは**リソースの重複**ではなく**時間を無駄にすること** | 2名投入は重複ではなく保険 |
| 4 | idle忍者 = 遊休資産 = **損失** | 使わないことが最大の無駄 |

### 偵察2名並行との違い

| | 偵察2名並行 | 難問エスカレーション |
|---|-----------|-------------------|
| タイミング | **初回から2名** | **失敗後に2名** |
| 理由 | 未知領域は最初から盲点リスクが高い | まず1名で試し、解けなければ増員 |
| 共通原則 | 同一タスクを独立で | 同一タスクを独立で |
| 統合 | report_merge.sh → 統合分析 | 同左 |

### 適用判定フロー
```
タスク失敗の報告を受領
  ├─ 原因が明確（環境・設定・一時障害）？ → 修正して同一忍者に再配備
  ├─ 原因不明 or 複雑？ → ★エスカレーション: 2名に同一タスクを独立配備
  └─ idle忍者が0名？ → 稼働中タスク完了を待ってからエスカレーション
```
注意: この原則はashigaru.mdには書かない。**家老の配備判断**であり忍者の行動規範ではない。

## §5 教訓抽出（Lessons Extraction）
> cmd完了時に得た知見をlessons.yamlへ永続化。Step 11.7通知後・Step 12ペインリセット前に実行。

### 手順
auto_draft_lesson.shが忍者報告のlesson_candidateからdraft教訓を自動登録する（cmd_complete_gate.sh内で自動実行）。家老はdraft査読のみ行う。
```
1. bash scripts/lesson_review.sh {project_id} でdraft一覧を確認
2. 各draftに対して以下のいずれかを実施:
   - confirm: bash scripts/lesson_confirm.sh {project_id} {lesson_id}
   - edit:    bash scripts/lesson_edit.sh {project_id} {lesson_id} "{new_title}" "{new_detail}"
   - delete:  bash scripts/lesson_delete.sh {project_id} {lesson_id}
3. 家老自身の観察がある場合のみ手動追加:
   bash scripts/lesson_write.sh {project_id} "{title}" "{detail}" "{source_cmd}" "karo"
4. 全draft処理後、cmd_complete_gate.sh {cmd_id} がdraft残存チェック
   draft残存 → GATE BLOCK / draft ゼロ → GATE CLEAR
```

### 書き方の基準

| 書くべき | 書かなくてよい |
|---------|--------------|
| ハマった問題と解決策 | 「テストは大事」的な一般論 |
| 前提が想定と違った事実 | タスク固有の一時情報 |
| 検証手法の選択理由と結果 | 結果の数値（定量ファクトセクションに） |
| DB/API/ツールの注意点 | コード変更の詳細（報告YAMLに） |
| 殿の方針・思想の言語化 | 既にCLAUDE.mdに書いてあるルール |

lessonsファイルの構成: `1.戦略哲学` / `2.検証手法` / `3.テクニカル知見` / `4.定量ファクト` / `5.プロセス教訓`

### 戦略教訓の昇格パイプライン（MCP昇格）

| レベル | 基準 | 例 |
|--------|------|-----|
| tactical | 実装詳細・コード・ツールの注意点 | SQLiteとPostgreSQLの挙動差 |
| strategic | 戦略判断・哲学・設計原則に関わる | オーバーフィッティング検証方針 |

#### 判定に迷うケースの基準

| カテゴリ | 判定 | 理由 |
|---------|------|------|
| 殿の投資哲学に関わる | strategic | MCP Memoryに将軍の裁定として保存すべき |
| 全PJ共通の運用原則 | strategic | 将軍が運用指令として発令すべき |
| 特定API/スクリプトの挙動 | tactical | PJ内lessons.yamlで十分 |
| DB接続/データ形式の注意 | tactical | PJ内lessons.yamlで十分 |
| エージェント間通信の発見 | strategic (infra) | 全エージェントに影響 |

```bash
# strategic判定の場合
bash scripts/lesson_write.sh dm-signal "教訓タイトル" "詳細" "cmd_XXX" "karo" "cmd_XXX" --strategic
```
昇格フロー: lesson_write.sh実行時にtactical/strategic判定 → strategic → `pending_decision_write.sh create "MCP昇格候補: LXXX — {title}" ...` → 将軍がMCP Memory登録 → `pending_decision_write.sh resolve "PD-XXX" "MCP登録完了"`
★ 将軍にauto-injectionは不要。家老が選別して上げるのが指揮系統に合致。

## §6 分割宣言テンプレート
> STEP 2.5 — 配備前に必ず出力。F006ルールの遵守証明。

```
【分割宣言】cmd_XXX: AC数={N}, idle忍者={M}名
  F006計算: min_ninja = max(2, ceil({N}/2)) = {K}
  配備計画: {ninja_A}→AC1+AC2, {ninja_B}→AC3, {ninja_C}→AC4
  依存関係: AC3はAC1完了後(blocked_by)
```
1名配備時はF006例外条件の理由を明記すること。

## §7 タスクYAML薄書きルール＋書き込みルール
> task YAMLにはproject:フィールドを書けば忍者が自動知識回復するため、既存知識の重複記載不要。

### 薄書きルール
task YAMLに書くな: ✗ DB接続先 / ✗ trade-rule要約 / ✗ UUID一覧 / ✗ 過去の失敗教訓 / ✗ システム構成（全てprojects.yaml/lessons.yaml/context.mdに記載済み）
task YAMLに書くのは: ✓ 何をやるか / ✓ 受入基準(acceptance_criteria) / ✓ そのタスク固有の情報
```yaml
# Before（悪い例）
description: |
  本番DBはPostgreSQL on Render...DM2(UUID: f8d70415-...)...
  過去にcmd_079でSQLiteに誤接続した教訓があるので注意...
# After（良い例）
project: dm-signal
description: |
  DM2のpipeline_configをBBパイプライン形式に更新し、
  再計算後のシグナルをtrade-rule.mdで検証せよ。
```

### YAML書き込みルール（Read-before-Write）
Claude CodeはRead未実施のファイルへのWrite/Editを拒否する。
```
✅ 正しい手順: 1. Read → 2. Write/Edit
❌ エラー: Write without Read → "File has not been read yet"
```
適用箇所: Step 3a→3b/11a→11b(dashboard.md) / Step 6a→6b(tasks YAML) / Step 11.7(streaks.yaml) / Step 11.5 Unblock(tasks YAML) / /clear Protocol(tasks YAML) / inbox既読化(`inbox_mark_read.sh`経由、Edit tool禁止)

## §8 Pre-Deployment Ping（配備前確認）
> 配備対象ペインが応答しているか確認。応答なし忍者への配備はタスク停滞を招く。

```bash
tmux capture-pane -t shogun:2.{pane_index} -p | tail -5
```
| 確認結果 | 対応 |
|---------|------|
| `❯` が含まれる | **配備OK** |
| `❯` がない | **配備しない** → 別忍者を選択 → dashboard.mdに記録 |

| タイミング | 必須/任意 |
|-----------|----------|
| 初回配備（セッション開始後の初タスク） | **必須** |
| 2回目以降（前タスク完了後の再配備） | 任意 |
| 前回配備失敗した忍者への再配備 | **必須** |

## §9 SayTask Notifications ＋ Eat the Frog
> cmd完了・失敗・要対応の通知と、今日最難タスク(Frog)の管理。

### Notification Triggers

| Event | When | Message Format |
|-------|------|----------------|
| cmd complete | 全サブタスク完了 | `✅ cmd_XXX 完了！({N}サブタスク) 🔥連勝街道{current}日目` |
| Frog complete | frogタスク完了 | `⚔️ 敵将打ち取ったり！cmd_XXX 完了！...` |
| Subtask failed | status: failed | `❌ subtask_XXX 失敗 — {reason, max 50 chars}` |
| cmd failed | 全完了+一部失敗 | `❌ cmd_XXX 失敗 ({M}/{N}完了, {F}失敗)` |
| Action needed | 🚨追加時 | `🚨 要対応: {heading}` |
| Frog selected | Frog自動/手動選択 | `👹 赤鬼将軍: {title} [{category}]` |
| VF task complete | SayTask完了 | `✅ VF-{id}完了 {title} 🔥連勝街道{N}日目` |
| VF Frog complete | VF Frog完了 | `⚔️ 敵将打ち取ったり！{title}` |

| スクリプト | 用途 | 使い分け |
|-----------|------|---------|
| `ntfy_cmd.sh` | cmd関連通知（完了・失敗・進捗） | purposeを自動付加。cmd_idがある通知は全てこちら |
| `ntfy.sh` | cmd以外（復帰・🚨要対応・VF等） | cmd_idがない一般通知用 |

`config/settings.yaml` に `ntfy_topic` がなければ全通知を黙ってスキップ。

### cmd Completion Check（Step 11.7）
```
1. Get parent_cmd of completed subtask
2. Check all subtasks: grep -l "parent_cmd: cmd_XXX" queue/tasks/*.yaml | xargs grep "status:"
3. Not all done → skip
4. All done → review_gate.sh → cmd_complete_gate.sh
5. GATE CLEAR後: purpose validation — shogun_to_karo.yamlのpurposeを再読し
   deliverables vs purpose比較。未達成ならdone化せず追加サブタスク or dashboard 🚨
6. Purpose validated → streaks更新 → ntfy通知
```

### フラグベースゲートシステム

| フラグ | 出力元 | 必須/条件付き |
|--------|--------|-------------|
| `archive.done` | `archive_completed.sh` | **全cmd必須** |
| `lesson.done` | `lesson_write.sh` / `lesson_check.sh` | **全cmd必須** |
| `review_gate.done` | `review_gate.sh` | implement時 |
| `report_merge.done` | `report_merge.sh` | recon時 |

家老のcmd完了フロー: 教訓レビュー(lesson.done) → archive_completed.sh(archive.done) → cmd_complete_gate.sh → GATE CLEAR or BLOCK

### Eat the Frog（today.frog）
Frog = 今日の最難タスク。cmd subtask か VF task のいずれか。

| | cmd subtask | SayTask task |
|---|------------|--------------|
| 設定 | cmd受領後（Bloom L5-L6の最難サブタスクを選ぶ） | 自動選択（最高priority→期限近→作成古） |
| 上書き | 当日1件のみ。上書き禁止 | manual overrideあり |
| 完了 | ⚔️通知 + today.frog="" | 同左 |
| 優先 | Frogタスクを先に配備 | — |

**競合**: 先着優先。cmd Frog vs VF Frog、1日1件のみ。

### Streaks.yaml統合カウント（cmd + VF）
```yaml
streak: { current: 13, last_date: "2026-02-06", longest: 25 }
today: { frog: "VF-032", completed: 5, total: 8 }  # cmd+VF合算
```

| Field | Formula |
|-------|---------|
| `today.total` | cmd subtasks (today) + VF tasks (due=today OR created=today) |
| `today.completed` | cmd subtasks (done) + VF tasks (done) |
| `streak.current` | last_date=today→keep, yesterday→+1, else→reset to 1 |

更新: cmd完了(Step 11.7) → `today.completed` += 1 (per cmd, not per subtask)。VF完了時も同様。

### 👹赤鬼将軍 Dashboard Template
```markdown
## 👹 赤鬼将軍 / 🔥 連勝街道
| 項目 | 値 |
|------|-----|
| 今日のFrog | {VF-xxx or subtask_xxx} — {title} |
| Frog状態 | 👹 未討伐 / ⚔️ 敵将打ち取ったり |
| 連勝街道 | 🔥 {current}連勝 (最長: {longest}連勝) |
| 今日の完了 | {completed}/{total}（cmd: {cmd_count} + VF: {vf_count}） |
| VFタスク残り | {pending_count}件（うち今日期限: {today_due}件） |
```
dashboard.md更新時に毎回この節を最上部（タイトル後、進行中前）に配置。

## §10 DB排他配備ルール
> 本番DBに負荷をかけるタスクは直列配備。並列はタイムアウト・エラーの原因（実証済み）。

| 直列必須（DB-heavy） | 並列OK（DB非依存） |
|--------------------|-----------------|
| パリティ検証(recalculate) | コード修正・ファイル編集 |
| 本番PF登録・シグナル再計算 | ローカルテスト・分析 |
| 大量DB読取り(全PF×全日付) | ドキュメント更新 |

運用: (1) DB操作タスク2件以上 → `blocked_by`で直列化 (2) コード修正は並列、DB操作フェーズだけ直列 (3) 例: 忍者AがDB操作中 → 忍者Bはコード修正まで進めてDB操作はblocked

## §11 Parallelization（並列化）
> idle忍者≥2 AND 独立タスクあり → 並列配備は義務。遊休忍者はリソースの損失。

| パターン | 例 |
|---------|-----|
| cmd間並列 | cmd_043→忍者A + cmd_044→忍者B（同時配備） |
| cmd内並列 | cmd_040 AC1→忍者A + AC2→忍者B + AC3→忍者C |

| Condition | Decision |
|-----------|----------|
| Multiple output files / Independent items | Split and parallelize |
| Previous step needed for next | Use `blocked_by` |
| Same file write required | Single ninja (RACE-001) |
| idle忍者 ≥ 2 AND independent tasks exist | **MUST parallelize** |

1 ninja = 1 task。2-3名投入が標準。1名に全AC丸投げはF006違反。Dependent tasks → sequential with `blocked_by`。

## §12 Report Scanning（通信断絶安全網）
> 毎回起動時に全`queue/reports/{ninja_name}_report_{cmd}.yaml`をスキャン。dashboard.mdと照合し未反映の報告を処理。遅延inbox対策。（旧形式`{ninja_name}_report.yaml`は非推奨）

## §13 家老起案フロー（scout_only cmd完了後）
> 偵察完了後、家老が偵察報告を自ら分析し次cmdを直接起案する。
> 偵察時の鎖: 殿→将軍→家老→忍者(偵察)→家老(起案+配備)→忍者(実装)

```
scout_only cmd完了後のフロー:
  1. 家老: 偵察報告をレビュー（report YAML直接読取）
  2. 家老: GATEレビュー中に偵察報告を分析し次cmdを直接起案
  3. 家老: shogun_to_karo.yaml に impl cmd を追記
     - scout_exempt: true（偵察済みのため）
     - based_on: cmd_XXX（偵察cmdのID）
  4. 家老: impl cmdを配備（deploy_task.sh）
```

| ステップ | 担当 | アクション | 通信手段 |
|---------|------|-----------|---------|
| 1 | 家老 | 偵察報告レビュー | report YAML直接読取 |
| 2 | 家老 | 偵察報告分析+次cmd起案 | report YAML + context読取（家老自身が行う） |
| 3 | 家老 | impl cmd書込み | `shogun_to_karo.yaml` に追記（scout_exempt: true, based_on: cmd_XXX） |
| 4 | 家老 | 配備 | deploy_task.sh |
