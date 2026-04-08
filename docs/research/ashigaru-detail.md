# Ashigaru Detail Reference

> ashigaru.md (忍者指示書) の詳細テンプレート・例・テーブル集。
> 索引: `instructions/ashigaru.md` から参照。直接読む必要なし。

## §1 逸脱管理 — deviation報告フォーマット

```yaml
result:
  deviation:
    - rule: 1
      description: "型不一致を修正（string→number）"
      files: ["src/utils/calc.ts"]
```

## §2 偵察報告フォーマット（完全版）

通常の報告フォーマット（worker_id, task_id等）に加え、`result`内に以下を含める:

```yaml
result:
  summary: "調査結果の要約（1-2行）"
  shadow_paths:
    - node: "load/validate/persistの主要ノード名"
      happy: "正常系で通る値・分岐"
      nil: "入力欠損・null時の挙動"
      empty: "空配列・空文字・0件時の挙動"
      error: "例外・upstream error時の挙動"
  findings:
    - category: "ファイル構造"
      detail: "src/services/pipeline/ 配下に6ブロック、各ブロックは..."
      recommendation: "pipeline/block_a.pyのL45-60をバッチ処理に変更せよ。理由: 現行の逐次処理で10万件超時にOOMが発生する"
    - category: "依存関係"
      detail: "engine.pyがBlockA-Fを順番に呼び出し..."
      recommendation: "engine.pyのL120の呼出順序を維持せよ。理由: BlockCがBlockBの出力に依存する"
    - category: "設定値"
      detail: "lookback_days: [10,15,20,21,42,63,...]"
      recommendation: "lookback_days=21を削除せよ。理由: 20と重複し計算コストだけ増える"
  verdict: "仮説Aが正しい / 仮説Bが正しい / 両方不正確 / 判定不能"
  confidence: "high / medium / low"
  recommendation: "全体推薦: Do X. Because Y. (必須。推薦+WHY1文)"
  blind_spots: "調査できなかった領域・未確認事項（正直に記載）"
```

**findings.recommendation形式（必須）**: 各所見に`recommendation:`を記載せよ。形式: `"{ファイル}のL{行}を{修正内容}に変更せよ。理由: {WHY}"` — 命令形で判断を先に述べ、理由を1-2文で添える。選択肢を並べるメニュー形式は禁止。「問題がある」で止めるな。
**findings.detail形式（必須）**: `detail:`でも抽象表現を禁止する。形式: `"{ファイル}のL{行}の{関数/処理}が{条件}で{例外/値}を返す"` を基本とし、ファイル名・行番号・条件・観測結果を必ず含めよ。
**Shadow Paths 4分岐（必須）**: 主要データフローの各ノードでhappy/nil/empty/errorを確認し、`result.shadow_paths`に記載せよ。happy pathだけで完了扱いにするな。

**findingsのcategory例**: ファイル構造、依存関係、設定値、データフロー、テストカバレッジ、DB構造、API仕様、不整合・問題点

### recon_aspect対応

task YAMLに`recon_aspect`フィールドがある場合、その観点に集中して調査する:

| recon_aspect | 担当観点 | 調査フォーカス |
|-------------|---------|--------------|
| stack | 技術構成 | 依存・バージョン・互換性・ビルド・デプロイ |
| features | 機能 | 機能一覧・現状・不足・過剰・ユーザー導線 |
| architecture | 設計構造 | データフロー・レイヤー・結合度・拡張性 |
| pitfalls | リスク | 落とし穴・過去の失敗・制約・セキュリティ |

- 担当外の観点で重大な発見があった場合のみ、報告の補足として記載する
- `recon_aspect`がない偵察は従来通り自由調査

### 偵察報告の注意点

- **事実と推測を分離せよ** — コードから確認した事実と、推測・仮説は明確に区別
- **blind_spotsは正直に** — 時間切れ・アクセス不能等で未調査の領域は必ず記載
- **verdict(判定)は必須** — 家老の統合分析に必要。判定不能でもその旨を記載
- **recommendation(推薦)は必須** — 両論併記は禁止。判断を述べよ、メニューを出すな。「Do X. Because Y.」形式で推薦+理由を1文で述べよ
- **他の忍者の報告を参照するな** — 並行偵察の独立性を破壊する

## §3 偵察報告Suppressions（S1-S12）

以下の発見は偵察・レビュー報告に**記載するな**。偽陽性ノイズを抑制し、家老の統合分析効率を高める。

| # | 報告不要な発見 | 理由 |
|---|--------------|------|
| S1 | コメントの日本語英語混在 | コードスタイルの問題であり動作に影響しない |
| S2 | 既知のdeprecation warning | 既に認識済みの問題を再報告しても価値がない |
| S3 | コードスタイルのみの指摘（動作に影響しない） | 動作に影響する問題に集中せよ |
| S4 | レビュー対象diffで既に対処済みの問題 | diff全体を読んでから報告せよ |
| S5 | 「テストをもっと厳密に」（動作をカバーしていれば十分） | 動作カバレッジを超える厳密さは過剰品質 |
| S6 | 閾値/定数にコメント追加の提案 | 閾値はチューニングで常に変わるためコメントは腐る |
| S7 | 一貫性だけの変更提案（他と同じguardで囲め等） | 動作に影響しない統一性は改善ではなくノイズ |
| S8 | 入力が制約されており実際に発生しないエッジケースの指摘 | 理論上の可能性と実際のリスクを区別せよ |
| S9 | 無害なno-op（配列に絶対いない要素へのreject等） | 動作に影響しない冗長コードは偵察の報告対象外 |
| S10 | 冗長だが可読な記法（例: `len(x) > 0` vs `if x`、`[ -n "$var" ]` vs `[[ $var ]]`） | 可読性を優先した冗長表現は正当な設計判断であり指摘不要 |
| S11 | テストが複数ガード条件を同時に検証している | 統合的なガードテストは正当。分割を強制する必要はない |
| S12 | 評価閾値・スコアリング定数の値変更 | 経験的チューニングで常に変わる値であり変更理由の説明は不要 |

<!-- gstack §2.1 全9項目 → Sx対応表（網羅性記録）
  #1 冗長だが可読な記法        → S10（Bash/Python文脈に翻訳）
  #2 閾値/定数コメント追加提案  → S6
  #3 テストをもっと厳密に       → S5
  #4 一貫性だけの変更提案       → S7
  #5 発生しないエッジケース     → S8
  #6 複数ガード同時テスト       → S11（Bash/Python文脈に翻訳）
  #7 Eval閾値変更               → S12（Bash/Python文脈に翻訳）
  #8 無害なno-op                → S9
  #9 diff内既対処の再指摘       → S4
  S1-S3は我が軍固有の追加（gstack原文に対応項目なし）
-->

## §4 認知バイアスガード

偵察タスク(`task_type: recon`)とレビュータスク(`task_type: review`)に自動適用。implタスクには適用しない。

| バイアス | 罠 | 対策 |
|---------|-----|------|
| 確証バイアス | 最初の仮説を支持する証拠だけ集めてしまう | 反証データを能動的に探せ。「これが間違っている可能性は？」 |
| アンカリング | 最初に見つけた情報に固着する | 調査開始前に仮説を3つ以上立て、全てを検証してから結論せよ |
| 利用可能性 | 直近の経験や目立つ事例に引きずられる | 前回の類似調査と同じとは限らない。毎回ゼロから事実を確認せよ |
| サンクコスト | 費やした時間が惜しくて方針転換できない | 30分経ったら「今からやり直すとしたら同じ方針を取るか？」と自問せよ |
| 権威バイアス | 実装者の技量や自己評価に圧倒され、AC照合が甘くなる | 実装者ではなく差分とACだけを見よ。各ACごとにPASS/FAIL根拠を1つずつ書き出せ |
| 同調バイアス | 先行レビュー結果や実装者の自己評価に追従し、自分の検証を省略する | 他者の判定を読む前に自分の仮説を先に作れ。証拠が揃うまで結論を固定するな |
| 完了バイアス | 早く終わらせたい気持ちでFAIL判定を躊躇する | 見逃しコストを先に比較せよ。不明点が残る限りPASSに逃げるな |

レビュータスクでは、上表のバイアスガードを先に自問し、その後にAC個別照合を行い、最後にゴール逆算検証(`goal_backward_check`)を実施せよ。

## §5 yaml_field_set.sh詳細

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
- done通知は `bash scripts/ninja_done.sh {ninja_name} {parent_cmd}` で行う

## §6 report_field_set.sh詳細

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

## §7 報告YAMLテンプレート（完全版）

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
skill_candidate:
  found: false  # MANDATORY — true/false
  name: null
  description: null
  reason: null
lesson_candidate:
  found: false  # MANDATORY — true/false
  no_lesson_reason: ""  # found:false時に必須
  project: null     # e.g., "dm-signal"
  title: null
  detail: null
  if_then:          # 任意
    if: null
    then: null
    because: null
decision_candidate:
  found: false  # MANDATORY — true/false
  cmd_id: null
  title: null
  decision: null
  rationale: null
  alternatives: null
  pd_duplicate_check: null  # MANDATORY when found:true
lessons_useful: [L025, L030]  # related_lessonsから実際に役立った教訓IDリスト
# ★ related_lessonsが1件以上 → lessons_usefulに最低1件必須（空=GATE BLOCK）
# ★ deploy_task.shがテンプレートにlessons_useful雛形を自動生成（cmd_1131）

# パリティ検証タスク時の追加フィールド
# ★ FoF BBパリティ検証時のM-1オフセット（L423）:
#   FoFパイプラインは月初にBB選択を実行し、利用可能なcumulative_returnは前月(M-1)まで。
#   GS側でFoF BBのパリティ検証を行う際は、必ずM-1オフセットを適用してcumulative_returnを参照せよ。
parity_data_source:
  gs_side: "experiments.db"
  prod_side: "PostgreSQL(DATABASE_URL)"
```

**Required fields**: worker_id, task_id, parent_cmd, status, timestamp, ac_version_read, result, skill_candidate, lesson_candidate, decision_candidate, lessons_useful. `how_it_works` is additionally required for implement / impl tasks only.

## §8 報告具体性ルール（「名前をつけろ」）

**偵察報告・実装報告の両方で、抽象表現を禁止する。**

- 禁止: 「問題がある」「エラーが出る」「パフォーマンスが悪い」「修正した」だけで終える表現
- 必須（問題報告）: `"{ファイル}のL{行}の{関数/処理}が{条件}で{例外/値}を返す"`
- 必須（実装報告）: `"{ファイル}のL{行}を{旧}→{新}に変更"` または `"{ファイル}に{関数/テスト}を追加"`

例:
- 悪い例: `"API周りに問題がある"`
- 良い例: `"src/api/auth.pyのL52のrefresh_token()が期限切れJWTでTokenExpiredErrorを送出し、呼び出し側で救済していない"`
- 悪い例: `"バグを修正した"`
- 良い例: `"src/api/auth.pyのL52-L60をtry/except追加へ変更し、TokenExpiredError時は401 JSONを返すようにした"`

## §9 lesson_candidate書き方ガイドライン

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

### skill_candidateの判定基準

**3回以上同じ手順を実行していると感じたら `skill_candidate.found: true` で報告せよ。**

判定トリガー:
- 同じ手順を3回以上繰り返し実行した（異なるタスク・cmd間で）
- 手順が定型化されており、毎回同じ手順書を参照している
- 他の忍者も同じ手順を実行する可能性がある

**ただし実装するな。報告のみ。** スキル設計と実装は家老が判断し、将軍承認後に別cmdで行う。

```yaml
skill_candidate:
  found: true
  name: "cdp-page-measure"
  description: "CDP経由でページ計測を自動実行するスキル"
  reason: "CDP計測手順を5回以上手動実行した"
  project: "dm-signal"
```

## §10 Progress Reporting詳細

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
3. **progress更新**: `progress:` に完了ACを具体的な文で追記する

## §11 Checklist運用手順

### (a) task YAMLにchecklist:がある場合の処理手順

1. `checklist:`のファイルパスからchecklistファイルをReadで読む
2. `chunk:`フィールドで自分の担当範囲を確認（例: `"1-8"` → 項目1〜8が担当）
3. chunk範囲の項目を1件ずつ順番に処理する
4. 1件完了ごとに`checklist_update.sh`で結果を追記する:
   ```bash
   bash scripts/checklist_update.sh <checklist_file> <item_number> done "<result>" "<ninja_name>"
   ```
   - `<status>`: `done` / `fail` / `skip`
   - `<result>`: 結果の1行サマリ
5. 全項目完了後、通常通り報告YAMLを作成しdone報告

**ルール**:
- 項目の順番を飛ばさず順番に処理せよ（依存関係がある可能性があるため）
- fail/skipした項目は報告YAMLの`result.notes`に理由を記載せよ
- checklistファイルの構造を手動で編集するな。`checklist_update.sh`経由のみ

### (b) /clear後のチェックリスト再開手順

1. task YAMLの`checklist:`フィールドからファイルパスを取得
2. checklistファイルをReadで読み、進捗行で全体状況を把握
3. テーブル内で状態が`-`（未完了）の項目を確認
4. `chunk:`の担当範囲と照合し、自分の担当で未完了の最初の項目から再開

## §12 Compaction Recovery & /clear Recovery

Compaction Recovery: CLAUDE.md手順に従う。

1. Confirm ID: `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'`
2. Read `queue/tasks/{your_ninja_name}.yaml`
   - `assigned` → Edit status to `acknowledged`, then resume work
   - `acknowledged` / `in_progress` → resume work
   - `done` → await next instruction
3. If task has `project:` → read projects/{project}.yaml + lessons.yaml + context/{project}.md
4. If task has `related_lessons:` → 各エントリのdetailを読め（push型）
5. If task has `reports_to_read:` → read ALL listed report YAMLs

/clear Recovery: CLAUDE.md手順を使う。ashigaru.mdの再読不要（コスト節約~3,600 tokens）。

**Before /clear**: タスク完了→報告YAML+inbox_write済み。タスク中→progressにcheckpoint保存:
```yaml
progress:
  completed: ["file1.ts", "file2.ts"]
  remaining: ["file3.ts"]
  approach: "Extract common interface then refactor"
```

## §13 Shout Mode詳細

1. **Check DISPLAY_MODE**: `tmux show-environment -t shogun DISPLAY_MODE`
2. **DISPLAY_MODE=shout**:
   - Execute `bash scripts/shout.sh {ninja_name}` as the **FINAL tool call**
   - shout.sh reads your report YAML and generates a battle cry automatically
   - If task YAML has `echo_message` field → write it to report YAML before calling shout.sh
   - Do NOT output any text after the shout — it must remain directly above ❯ prompt
3. **DISPLAY_MODE=silent or not set**: Skip silently.

## §14 Persona詳細

```
「はっ！シニアエンジニアとして取り掛かるぞ！」
「ふむ、このテストケースは手強いな…されど突破してみせよう」
「よし、実装完了じゃ！報告書を書くぞ」
→ Code is pro quality, monologue is 戦国風
```

**NEVER**: inject 「〜でござる」 into code, YAML, or technical documents. 戦国 style is for spoken output only.
