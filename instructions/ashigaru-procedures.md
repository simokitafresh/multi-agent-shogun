# Ninja Detailed Procedures

> 詳細手順・テンプレート。中核ルールは `instructions/ashigaru.md` を参照。

## Task YAML更新手順

task YAMLのフィールド更新（status変更等）は `yaml_field_set.sh` 経由で行うこと。
yqは環境に存在しない。Edit toolでの直接編集もYAML構造破壊のリスクがある。

### コマンド書式

```bash
# 直接実行
bash scripts/lib/yaml_field_set.sh <yaml_file> <block_id> <field> <new_value>

# source方式（スクリプト内で使う場合）
source scripts/lib/yaml_field_set.sh
yaml_field_set <yaml_file> <block_id> <field> <new_value>
```

- `block_id`: task YAMLでは `task`（トップレベルキー）
- flock排他制御+post-write verification付き

### 例

```bash
# status更新
bash scripts/lib/yaml_field_set.sh queue/tasks/hayate.yaml task status acknowledged
bash scripts/lib/yaml_field_set.sh queue/tasks/hayate.yaml task status in_progress
bash scripts/lib/yaml_field_set.sh queue/tasks/hayate.yaml task status done

# progress追記（単一行）
bash scripts/lib/yaml_field_set.sh queue/tasks/hayate.yaml task progress "AC1: 完了"
```

### 注意

- Edit toolでのtask YAML直接編集は、progress欄の追記等でやむを得ない場合のみ許容
- status遷移は assigned → acknowledged → in_progress → done の順
- done通知は `bash scripts/ninja_done.sh {ninja_name} {parent_cmd}` で行う（Step 7参照）

## 報告YAML作成・編集手順

報告YAMLの作成・編集は全て `report_field_set.sh` 経由で行うこと。
Write/Edit toolによる `queue/reports/*.yaml` への直接書き込みはhookでブロックされる。

### コマンド書式

```bash
# 単一値
bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>

# 複数行値（stdinから読み込み）
cat <<'EOF' | bash scripts/report_field_set.sh <report_path> <dot.notation.key> -
- item1
- item2
EOF
```

### 例

```bash
# ステータス設定
bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml status done

# ネストフィールド
bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml result.summary "WBS 2.3節 完了"

# 複数行値
cat <<'EOF' | bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml result.files_modified -
- /path/to/file1
- /path/to/file2
EOF

# 真偽値・null（自動型変換）
bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml lesson_candidate.found true
bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml decision_candidate.found false
```

### 仕様

- ファイル未存在時は自動新規作成される
- ドット記法でネストフィールドに対応（例: `result.self_gate_check.lesson_ref`）
- 中間dictも自動作成される
- flock排他制御+atomic write（安全な並行アクセス）
- 値の型は自動判定: true/false→bool、null/none→None、整数→int、小数→float、その他→string

## Report Notification Protocol

After writing report YAML, notify Karo:

```bash
bash scripts/inbox_write.sh karo "{your_ninja_name}、任務完了。報告YAML確認されたし。" report_received {your_ninja_name}
```

Example (if you are hayate):
```bash
bash scripts/inbox_write.sh karo "疾風、任務完了。報告YAML確認されたし。" report_received hayate
```

That's it. No state checking, no retry, no delivery verification.
The inbox_write guarantees persistence. inbox_watcher handles delivery.

## Report Format

### 発見即記録

偵察・レビューでissueを見つけたら、その瞬間に報告YAMLの `result.findings` へ追記せよ。最後にまとめて書くな。記憶劣化と脚色を防ぐため、発見時点の事実・条件・影響をその場で固定する。

```yaml
worker_id: sasuke
task_id: subtask_001
parent_cmd: cmd_035
timestamp: "2026-01-25T10:15:00"  # from date command
status: done  # done | failed | blocked
ac_version_read: 6  # task YAMLを読んだ時点のac_versionを転記
result:
  summary: "WBS 2.3節 完了"
  files_modified:
    - "/path/to/file"
  notes: "Additional details"
  lessons:  # 次に同種の作業をする人が知るべき教訓（任意だが推奨）
    - "MomentumCacheを渡さないとsimulate_strategy_vectorized()は黙って空を返す"
    - "experiments.dbのmonthly_returnsが価格のground truth。dm_signal.dbには価格なし"
how_it_works: |
  task_type: implement / impl の報告では必須。
  変更したロジックがなぜその挙動になるかを1-3行で説明する。
  recon / scout / review タスクでは不要。
purpose_validation:
  cmd_purpose: "(task YAMLのdescription冒頭1行を転記)"
  fit: true
  purpose_gap: ""  # fit: false の場合のみ記述
failure_analysis:    # 失敗時のみ記入（status: failed の場合）
  root_cause: "失敗の根本原因"
  what_would_prevent: "再発を防ぐために何をすべきか"
  # auto_failure_lesson.shがこのセクションを読み取りdraft教訓を自動生成する
  # 未記入でもresult.summaryから自動生成されるが、記入すれば教訓の品質が向上する
skill_candidate:
  found: false  # MANDATORY — true/false
  # If true, also include:
  name: null        # e.g., "readme-improver"
  description: null # e.g., "Improve README for beginners"
  reason: null      # e.g., "Same pattern executed 3 times"
lesson_candidate:
  found: false  # MANDATORY — true/false
  # If found: false, MUST include:
  no_lesson_reason: ""  # found:false時に必須。理由を1文で書け
  #   例: "既知のL084と同じパターン" / "単純な設定変更で新知見なし" / "定型的なファイル修正のみ"
  #   空のまま提出するとfound:false+no_lesson_reason空=家老差し戻し対象
  # If found: true, include:
  #   推奨: 「次回このタスクをやる忍者が知っていれば速くなること」を1つ書け
  project: null     # e.g., "dm-signal" — auto_draft_lesson.shがプロジェクト判定に使用
  title: null       # e.g., "dm_signal.dbは本番DBではない"
  detail: null      # e.g., "本番はPostgreSQL on Render。SQLiteへのINSERTは無意味"
  if_then:          # 任意 — IF-THEN形式で教訓を構造化する場合に記載
    if: null        # いつ適用するか（トリガー条件）e.g., "((PASS++))でカウンタをインクリメントする時"
    then: null      # 何をするか（推奨アクション）e.g., "PASS=$((PASS+1))に変換する"
    because: null   # なぜそうするか（根拠）e.g., "PASS=0の時に((0))がexit code 1→set -eで即終了"
  # NOTE: 忍者はlessons.yamlに直接書き込まない。
  #        found:trueの報告はauto_draft_lesson.shがdraft教訓として自動登録する。
  #        家老がconfirm/edit/deleteで査読し正式化する。
decision_candidate:
  found: false  # MANDATORY — true/false
  # If true, also include:
  cmd_id: null        # e.g., "cmd_087"
  title: null         # e.g., "決定のタイトル"
  decision: null      # e.g., "何を決めたか"
  rationale: null     # e.g., "なぜそう決めたか"
  alternatives: null  # e.g., "検討した他の案"
  pd_duplicate_check: null  # MANDATORY when found:true — pending_decisions.yamlを確認し、既存裁定と重複がないか記載。重複あればDC起票せず「PD-XXXで裁定済み」と記載
  # NOTE: 忍者はdecisions.mdに直接書き込まない。
  #        家老が報告のdecision_candidateを精査し、decision_write.shで正式登録する。
  # ★ DC起票前にpending_decisions.yamlを必ず読め。既に殿が裁定済みの件を再質問するのは禁止。
lessons_useful: [L025, L030]  # related_lessonsから実際に役立った教訓IDリスト
  # 参照なしなら lessons_useful: []
  # 後方互換: lessons_useful: [] は旧 lesson_referenced: false と同等扱い
  # related_lessonsが空 or なしでも lessons_useful: [] を必ず記載
  # ★ タスクYAMLにrelated_lessonsが1件以上ある場合、lessons_usefulに
  #   最低1件は記載必須。空のまま報告するとcmd完了ゲート(cmd_complete_gate.sh)で
  #   BLOCKされる。実際に役立った教訓のIDを記載せよ(例: [L121, L122])
  # ★ deploy_task.shが報告テンプレートにlessons_useful雛形を自動生成する（cmd_1131）。
  #   テンプレートに以下の形式でIDが列挙されるので、usefulとreasonを埋めるだけでよい:
  #   - id: L074
  #     useful: true
  #     reason: shadow_paths確認の手順が直接役立った

# パリティ検証報告の追加フィールド（パリティ検証タスク時に必須）
# data_sourceはパリティ検証の信頼性を担保する必須情報。省略はFAIL扱い。
# ★ FoF BBパリティ検証時のM-1オフセット（L423）:
#   FoFパイプラインは月初にBB選択を実行し、利用可能なcumulative_returnは前月(M-1)まで。
#   GS側でFoF BBのパリティ検証を行う際は、必ずM-1オフセットを適用してcumulative_returnを参照せよ。
#   全BB種別共通（追い風・抜き身・変わり身・加速R・加速D・分身・四つ目）。
#   詳細: docs/rule/db-operations-runbook.md §3
parity_data_source:
  gs_side: "experiments.db"                    # GS側データソースを明記
  prod_side: "PostgreSQL(DATABASE_URL)"        # 本番側データソースを明記
```

**Required fields**: worker_id, task_id, parent_cmd, status, timestamp, ac_version_read, result, skill_candidate, lesson_candidate, decision_candidate, lessons_useful. `how_it_works` is additionally required for implement / impl tasks only.
Missing fields = incomplete report.

### 報告具体性ルール（「名前をつけろ」）

**偵察報告・実装報告の両方で、抽象表現を禁止する。**

- 禁止: 「問題がある」「エラーが出る」「パフォーマンスが悪い」「修正した」だけで終える表現
- 必須（問題報告）: `"{ファイル}のL{行}の{関数/処理}が{条件}で{例外/値}を返す"`
- 必須（実装報告）: `"{ファイル}のL{行}を{旧}→{新}に変更"` または `"{ファイル}に{関数/テスト}を追加"`

例:
- 悪い例: `"API周りに問題がある"`
- 良い例: `"src/api/auth.pyのL52のrefresh_token()が期限切れJWTでTokenExpiredErrorを送出し、呼び出し側で救済していない"`
- 悪い例: `"バグを修正した"`
- 良い例: `"src/api/auth.pyのL52-L60をtry/except追加へ変更し、TokenExpiredError時は401 JSONを返すようにした"`

## Step 5.5: 提出前自己ゲート (MANDATORY)

**positive_rule**: report作成後、statusをdoneにする前に以下の4項目を全て確認し、report.result.self_gate_checkに記載せよ。全PASSでなければstatusをdoneにするな。FAILを修正してから再確認。

| 項目 | 確認内容 | FAILの対処 |
|------|---------|------------|
| (a) lesson_ref | related_lessonsが1件以上 → lessons_usefulに1件以上記載 | lessons_usefulに役立った教訓IDを追記 |
| (b) lesson_candidate | found: true/falseが明記されていること | lesson_candidateにfound:true or falseを記載 |
| (c) status_valid | status = done \| failed \| blocked のいずれか | 適切なstatusに修正 |
| (d) purpose_fit | purpose_validation.fit = true | 目的に沿う成果へ修正、不可ならpurpose_gap記載 |

確認結果をreport.result.self_gate_checkに記載:
```yaml
self_gate_check:
  lesson_ref: PASS    # or FAIL
  lesson_candidate: PASS  # or FAIL
  status_valid: PASS  # or FAIL
  purpose_fit: PASS   # or FAIL
```

**reason**: cmd完了ゲート(cmd_complete_gate.sh)のBLOCK主因はlessons_useful空。提出前の自己ゲートで事前排除できる。FAILを提出後に修正するより提出前の確認コストは格段に低い。

### 報告フィールド漏れ防止

報告時は以下のフィールドを省略しがちです。
**必ず全フィールドを含めてください:**

- `lesson_candidate:` — found: true/false は**必須**。省略禁止。
  found: true の場合は title: と detail: も必須。
- `lessons_useful:` — related_lessonsのうち実際に役立ったIDリストを記載。
  参照なしでも `lessons_useful: []` を必ず記載。
  **★ タスクYAMLにrelated_lessonsが1件以上ある場合、lessons_usefulに最低1件は記載必須。**
  空のまま報告するとcmd完了ゲート(cmd_complete_gate.sh)でBLOCKされる。
- `decision_candidate:` — found: true/false は**必須**。
- `ac_version_read:` — task YAMLの`ac_version`を転記。未記載は後方互換WARNになるが、最新版運用では必須。

### Lessons Field Guidelines

`lessons:` は「次に同種の作業をする人が知るべきこと」を書く。

**良い教訓** — 具体的・行動可能:
- "recalculate_fofはローカルSQLiteで動かない。experiments.db+dm_signal.dbで直接計算する"
- "WF判定基準は>1.0に設定すべき。>0では差が出ない"

**悪い教訓** — 曖昧・一般論:
- "テストは重要" ← 当たり前
- "気をつける" ← 何を？

書くべきタイミング:
- ハマった問題とその解決策
- 前提が想定と違った（例: DBにデータがなかった）
- 検証手法の選択理由（例: CPCVが乗り換え戦略にフィットしない理由）
- 他の忍者への引継ぎ情報

### lesson_candidateの重要性と書き方ガイドライン

**lesson_candidate.found:trueの報告はauto_draft_lesson.shがdraft教訓として自動登録する。**
質の高いlesson_candidateを書くことが教訓システム全体の品質を決める。

**found: false の場合**: `no_lesson_reason` に理由を1文で書け。全タスクに学びがある。found:falseはラルフループの燃料切れを意味する。理由なきfound:falseは家老が差し戻す。
- 良い例: `"既知のL084と同じパターン"` / `"単純な設定変更で新知見なし"` / `"定型的なファイル修正のみ"`
- 悪い例: (空欄) ← 差し戻し対象

**found: true の場合(推奨)**: 「次回このタスクをやる忍者が知っていれば速くなること」を1つ書け。

**title** — 問題と解決策を1行で。「〜した→〜で解決」形式:
- 良い例: `"experiments.dbのUUIDが本番と不一致→GFS CSVを直接読込で解決"`
- 悪い例: `"DBの問題"` ← 何が問題か不明

**detail** — 具体的な技術詳細（ファイル名、行番号、コマンド）:
- 良い例: `"register_shijin_portfolios.pyがuuid4()で新規生成するため、experiments.dbのUUIDと本番PostgreSQLのUUIDが一致しない。scripts/analysis/grid_search/配下の7本をCSV直接読込に移行して解決"`
- 悪い例: `"UUIDが違っていた"` ← 原因も対策も不明

**project** — lesson_candidateにproject:フィールドを必ず含めよ。auto_draft_lesson.shが登録先を判定する。

### skill_candidateの判定基準

**3回以上同じ手順を実行していると感じたら `skill_candidate.found: true` で報告せよ。**

判定トリガー:
- 同じ手順を3回以上繰り返し実行した（異なるタスク・cmd間で）
- 手順が定型化されており、毎回同じ手順書を参照している
- 他の忍者も同じ手順を実行する可能性がある

具体例:
- CDP計測手順（PowerShell経由のChrome起動→DOM操作→スクリーンショット取得）
- context索引更新手順（docs/research/へ詳細移動→context圧縮→リンク確認）
- Render deploy検証手順（デプロイ→ヘルスチェック→ログ確認→パリティ検証）

**ただし実装するな。報告のみ。** スキル設計と実装は家老が判断し、将軍承認後に別cmdで行う。

報告フォーマット（報告YAMLのskill_candidate欄）:
```yaml
skill_candidate:
  found: true
  name: "cdp-page-measure"
  description: "CDP経由でページ計測を自動実行するスキル"
  reason: "CDP計測手順を5回以上手動実行した"
  project: "dm-signal"
```

## Progress Reporting (Step 4.5)

**ACが2個以上あるタスクでは、各AC完了時にtask YAMLのprogress欄を更新せよ。**
**ACが3個以上あるタスクでは、各AC完了直後に AC完了チェックポイント を必ず実施せよ。**

家老が中間進捗を確認し、方向転換やアドバイスを送れるようにするための仕組み。

### 手順

1. AC完了時にtask YAMLを読む
2. 次ACの前提条件が満たされているか確認する
3. scope drift（残りACに不要な作業の混入）が起きていないか確認する
4. `progress:`欄に完了ACを追記
5. 問題があればnotesに記載

```yaml
# task YAML内に追記する形式
progress:
  - "AC1: コード修正完了"
  - "AC2: ミニパリティ 6/8 PASS"
  - "AC3: 実行中 — N4_0500でFAIL、原因調査中"
```

### ルール

| ルール | 理由 |
|--------|------|
| AC完了ごとに即座に更新 | 家老が進捗を把握できる |
| 問題発生時も記載 | 早期に方向転換できる |
| AC1個のタスクはスキップ可 | 最終報告で十分 |
| 完了報告(Step 5)とは別 | progressは中間、reportは最終 |

### AC完了チェックポイント（3AC以上で必須）

task YAMLに`ac_checkpoint:`がある場合、その指示を各AC完了後にそのまま実施せよ。未記載でも、ACが3個以上なら以下を必ず確認する。

1. **次ACの前提条件確認**: 直前の変更で必要なファイル・テスト・データが揃っているか確認する
2. **scope drift検出**: 次AC達成に不要な改善案・横道作業が混入していないか確認する。見つけた案は実装せず `lesson_candidate` または `decision_candidate` に逃がす
3. **progress更新**: `progress:` に完了ACを具体的な文で追記する。例: `"AC2: scripts/deploy_task.shのac_checkpoint自動注入を追加"`

## Checklist運用手順（段取りリスト対応）

### (a) task YAMLにchecklist:がある場合の処理手順

task YAMLに`checklist:`フィールドがある場合、以下の手順で段取りリストに沿って作業せよ。

1. `checklist:`のファイルパスからchecklistファイルをReadで読む
2. `chunk:`フィールドで自分の担当範囲を確認（例: `"1-8"` → 項目1〜8が担当）
3. chunk範囲の項目を1件ずつ順番に処理する
4. 1件完了ごとに`checklist_update.sh`で結果を追記する:
   ```bash
   bash scripts/checklist_update.sh <checklist_file> <item_number> done "<result>" "<ninja_name>"
   ```
   - `<checklist_file>`: task YAMLの`checklist:`の値（例: `queue/checklists/cmd_0200.md`）
   - `<item_number>`: 完了した項目の番号
   - `<status>`: `done` / `fail` / `skip`
   - `<result>`: 結果の1行サマリ（例: `"L45-60修正完了"` / `"型不一致でFAIL"`)
   - `<ninja_name>`: 自分の名前
5. 全項目完了後、通常通り報告YAMLを作成しdone報告

**ルール**:
- 項目の順番を飛ばさず順番に処理せよ（依存関係がある可能性があるため）
- fail/skipした項目は報告YAMLの`result.notes`に理由を記載せよ
- checklistファイルの構造（テーブル形式）を手動で編集するな。`checklist_update.sh`経由のみ

### (b) /clear後のチェックリスト再開手順

/clear後にtask YAMLに`checklist:`がある場合、以下の手順で作業を再開せよ。

1. task YAMLの`checklist:`フィールドからファイルパスを取得
2. checklistファイルをReadで読み、進捗行（`# 進捗: N/M (X%)`）で全体状況を把握
3. テーブル内で状態が`-`（未完了）の項目を確認
4. `chunk:`の担当範囲と照合し、自分の担当で未完了の最初の項目から再開
5. 通常の処理手順（上記(a)）に従い、残りの項目を処理する

**注意**: /clear前の記憶はない。checklistファイルが唯一の進捗記録であり、これを信頼して再開せよ。

## Compaction Recovery

Recover from primary data:

1. Confirm ID: `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'`
2. Read `queue/tasks/{your_ninja_name}.yaml`
   - `assigned` → Edit status to `acknowledged`, then resume work
   - `acknowledged` / `in_progress` → resume work
   - `done` → await next instruction
3. Read Memory MCP (read_graph) if available
4. If task YAML has `project:` field, read these 3 files **before starting work (MANDATORY)**:
   - `projects/{project}.yaml` — core knowledge (trade rules, DB rules, pipeline, UUIDs)
   - `projects/{project}/lessons.yaml` — project-specific lessons (past mistakes, discoveries)
   - `context/{project}.md` — detailed context (system architecture, analysis tools, data management)
   All 3 files serve different purposes. Read all before starting work.
   If task YAML has `related_lessons:`, 各エントリのdetailを読んでから作業開始せよ（push型: 詳細はタスクYAMLに埋込済み）。
   If task YAML has `reports_to_read:`, read ALL listed report YAMLs before starting work.
   Information omitted from task YAML is expected to exist in these files. Do not treat omission as missing requirements.
5. dashboard.md is secondary info only — trust YAML as authoritative

## /clear Recovery

/clear recovery follows **CLAUDE.md procedure**. This section is supplementary.

**Key points:**
- After /clear, instructions/ashigaru.md (now ninja instructions) is NOT needed (cost saving: ~3,600 tokens)
- CLAUDE.md /clear flow (~5,000 tokens) is sufficient for first task
- Read instructions only if needed for 2nd+ tasks
- If task YAML status is `assigned` → Edit to `acknowledged` immediately (ghost deployment prevention)

**Before /clear** (ensure these are done):
1. If task complete → report YAML written + inbox_write sent
2. If task in progress → save progress to task YAML:
   ```yaml
   progress:
     completed: ["file1.ts", "file2.ts"]
     remaining: ["file3.ts"]
     approach: "Extract common interface then refactor"
   ```

## Autonomous Judgment Rules

Act without waiting for Karo's instruction:

**On task completion** (in this order):
1. Self-review deliverables (re-read your output)
2. **Purpose validation**: Read `parent_cmd` in `queue/shogun_to_karo.yaml` and verify your deliverable actually achieves the cmd's stated purpose. If there's a gap between the cmd purpose and your output, note it in the report under `purpose_gap:`.
3. Update report YAML (`bash scripts/lib/report_field_set.sh` — Edit/Write直接禁止)
4. Notify Karo via inbox_write
5. (No delivery verification needed — inbox_write guarantees persistence)

**Quality assurance:**
- After modifying files → verify with Read
- If project has tests → run related tests
- If modifying instructions → check for contradictions

**Anomaly handling:**
- Context below 30% → update progress via `report_field_set.sh`, tell Karo "context running low"
- Task larger than expected → include split proposal in report

## Shout Mode (echo_message)

After task completion, check whether to shout a battle cry:

1. **Check DISPLAY_MODE**: `tmux show-environment -t shogun DISPLAY_MODE`
2. **When DISPLAY_MODE=shout**:
   - Execute `bash scripts/shout.sh {ninja_name}` as the **FINAL tool call** after task completion
   - shout.sh reads your report YAML and generates a battle cry automatically
   - If task YAML has an `echo_message` field → `report_field_set.sh` で report に書き込んでから shout.sh を呼べ
   - Do NOT output any text after the shout — it must remain directly above the ❯ prompt
3. **When DISPLAY_MODE=silent or not set**: Do NOT shout. Skip silently.
