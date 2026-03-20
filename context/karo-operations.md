# 家老運用索引
<!-- last_updated: 2026-03-09 cmd_707 4観点並行偵察パターン追加 -->

> 索引層。詳細手順・テンプレート・判断材料は `docs/research/karo-operations-detail.md` を参照。
> 原則: 普段は本ファイルの結論だけで判断し、深掘りが必要な時だけ詳細へ進め。

## §0 使い分け

| 作業フェーズ | まず見る結論 | 詳細参照 |
|------|------|------|
| cmd受領〜配備 | 五問チェック→Pattern Selection Flow→deploy | `docs/research/karo-operations-detail.md` §1-2 |
| 報告受領〜レビュー | review/pass-fail/WAIVE/再配備 | `docs/research/karo-operations-detail.md` §3 |
| 難問・失敗対応 | 1名失敗後は2名独立配備 | `docs/research/karo-operations-detail.md` §4 |
| cmd完了後の知識処理 | draft教訓査読→GATE | `docs/research/karo-operations-detail.md` §5 |
| context圧縮・配備前確認 | gate_vercel_phase + pre-deploy ping | `docs/research/karo-operations-detail.md` §8 |
| 通知・Frog・連勝管理 | ntfy_cmd / ntfy / streaks | `docs/research/karo-operations-detail.md` §9 |
| DB-heavy配備 | 本番DB操作は直列 | `docs/research/karo-operations-detail.md` §10 |
| CLI切替 | `switch_cli_mode.sh` を使う | `docs/research/karo-operations-detail.md` §16 |

## §1 配備

- 配備前は毎回「五問チェック」を通す。Purpose / Decomposition / Headcount / Difficulty / Risk を1行で言えなければ配備するな。
- implタスク配備前の偵察要否は `deploy_task.sh` が強制する。家老は `scout_exempt` を勝手に決めない。
- 偵察配備後の2名体制検証は `task_deploy.sh` の役割。`deploy_task.sh` と混同するな。
- BE系タスク配備ルール: `backend/` 配下のファイルが変更対象の場合、タスクYAMLの `context_files` に `docs/rule/trade-rule.md` パスを含めよ。理由: RULE09/10/11 と 14 の誤解パターンを忍者が自動参照するため。
- **成果のcontext還流**: cmd成果に数値・事実（ベンチマーク、設計決定等）を含む場合、cmd設計時にcontext更新を最終ACに含めることを推奨。ただし判定は§3 Context還流判定に統合。
- **担当者指名禁止（殿厳命）**: 忍者配備で「偵察担当をそのまま実装に回す」等の担当者指名をするな。忍者は/clearで全記憶消去される。誰がやっても報告YAMLを読めば同じ結果を出せる。配備判断は**負荷分散・idle順**で行え。知識の引継ぎは報告YAMLパスをタスクYAMLの`context_files`に注入することで担保せよ。
- **軍師レビューと忍者配備の並行実行**: cmd受領後、忍者配備と軍師レビュー依頼を同時に行う。軍師の承認を待たずに配備する。
  1. cmdを受領しタスク分解
  2. 忍者にタスク配備（待たない）
  3. 同時に軍師にレビュー依頼（`inbox_write gunshi "draft cmd_XXXX レビュー依頼" review_draft karo`）
  4. 軍師からの報告受信時:
     - APPROVE: 何もしない（忍者は既に作業中/完了）
     - REQUEST_CHANGES: 指摘内容を補足cmdとして忍者に配備
→ `docs/research/karo-operations-detail.md` §1

## §2 分解

- cmdは `scout_exempt` / `scout_only` / フルフロー の3分岐で読む。
- パターンは `recon / impl / impl_parallel / review / integrate` の5種。毎回ゼロから考えるな。
- 追加と修正が混在したcmdは分離してから配備する。
- 後続サブタスクは `blocked_by` + `auto_deploy: true` 付きで事前一括作成する。
- 「4観点偵察」指定時は4忍者にstack/features/architecture/pitfallsを1観点ずつ配備。従来の2名並行偵察と併用可。task YAMLに `recon_aspect` フィールドで観点を伝達。

### スコープ適正基準(Scope Sanity)

GSD知見: サブタスク数が増えるほどコンテキスト品質が劣化する。

| 指標 | 適正 | 注意 | 分割検討 |
|------|------|------|---------|
| サブタスク数/cmd | 2-3 | 4 | 5以上 |
| 変更ファイル数/サブタスク | 5-8 | 10 | 10以上 |

これは推奨値であり強制(BLOCK)ではない。家老の判断で超過を許容できる（タスク粒度は内容に依存するため）。ただし超過時は理由をダッシュボードに記載する。

### フリクション記録

タスク分解中に以下のフリクションがあった場合、記録する:
```bash
bash scripts/cmd_friction_log.sh "{cmd_id}" "{friction_type}" "{detail}"
```
friction_type: `ambiguous_scope` | `missing_context` | `too_many_acs` | `unclear_dependency` | `other`
記録先: `logs/cmd_friction.yaml`
※ フリクションがなければ記録不要

→ `docs/research/karo-operations-detail.md` §2

## §3 レビュー

### 忍者報告レビューフロー（軍師一次→家老スタンプ方式）[cmd_1162]

忍者報告受領時のデフォルトフロー。軍師が一次レビュー → 家老はスタンプ+教訓抽出に専念。

| ステップ | 実行者 | アクション |
|---------|--------|-----------|
| 1. 報告受領 | 家老 | 軍師にreport_review依頼（`inbox_write gunshi ... report_review karo`） |
| 2a. LGTM | 家老 | レビュー省略→スタンプ(PASS)+教訓抽出+context還流判定+GATE進行 |
| 2b. FAIL | 家老 | fail_reasonsを確認→Re-review Loop or 修正task配備を判断 |
| 2c. 未完了 | 家老 | フォールバック: 家老フルレビュー（旧フロー） |

**旧フローとの差分**:
- 旧: 忍者報告受領 → **家老がフルレビュー** → PASS/FAIL判定 → 教訓抽出 → GATE
- 新: 忍者報告受領 → **軍師に一次レビュー委任** → LGTM時は家老スタンプのみ → 教訓抽出 → GATE
- 家老フルレビューはフォールバック（軍師未完了時）のみ発動
- **切替条件**: 軍師(gunshi)が稼働中 = 新フロー。軍師未応答/未配備 = 旧フロー自動適用

→ 手順詳細: `instructions/karo.md`「忍者報告レビューフロー」セクション

### レビュー原則（新旧共通）

- 家老の役割はレビュー配備とGATE判定のみ。品質判定そのものは軍師または忍者レビューに委ねる。
- verdict は PASS / FAIL の二値厳守。条件付きPASSは禁止。
- failed を放置するな。修正配備 / WAIVE→done / 殿裁定のいずれかへ必ず進める。
- Two-pass Review: CRITICALはblocking(PASS/FAIL直結)、INFORMATIONALは記録のみ(non-blocking)。→ detail §3 Two-pass Review
- A/B/C Triage: レビュー指摘を3分類。A:Fix(修正必須→impl再配備)、B:Acknowledge(認識するが今回対応不要→理由記録)、C:False Positive(偽陽性→以後抑制)。PASS/FAIL/WAIVEとの対応表あり。→ detail §3 A/B/C Triage
- Re-review Loop: blocking fix→修正task配備→再レビュー配備の明示フロー。曖昧に続行するな。→ detail §3 Re-review Loop
- **Context還流判定**: GATE CLEAR前に「この報告にcontext索引を更新すべき数値・事実があるか？」を判定せよ。あればGATE CLEAR処理の一部としてcontext更新を実行。対象: 性能テーブル、設計決定、新API仕様、パイプライン状態等。**Why**: 報告YAMLに閉じた情報はアーカイブ後に将軍から見えなくなり、古いcontextで誤判断する（cmd_1048-1052後のgs-speedup§6未更新が契機）。
- **Workaroundログ記録（必須）**: 忍者報告の手動修正（報告YAML修正・コード手直し等）を行った場合、修正のたびに `karo_workaround_log.sh` を呼んで記録せよ。任意ではなく必須。修正パターンの蓄積により再発防止策（テンプレート改善・教訓追加）を導出する。
  ```
  修正実施後: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
  ```
### Workaround Pattern対処フロー

`karo_workaround_log.sh` でworkaround_patternが通知された場合の対処手順:

1. **推定根本原因を確認**: 修正ログの `fix_description` と `fix_method` から、原因がテンプレート / スクリプト / 手順書のいずれにあるかを特定
2. **根本原因に対する修正cmdを起案**: 教訓登録（忍者に教える）より、テンプレ・スクリプトの直接修正を優先。構造で問題を防げ
   - テンプレート起因 → テンプレートファイル修正cmd
   - スクリプト起因 → スクリプト修正cmd
   - 手順書起因 → instructions/*.md or karo-operations.md 修正cmd
3. **修正cmd配備後、workaround_pattern通知を「対処済み」に更新**: `karo_workaround_log.sh` の該当エントリに対処cmdを記録

**原則**: 「教訓で忍者に教える」より「テンプレを直して問題が発生しない構造にする」を優先。同じworkaroundを2回やったら構造が間違っている。

### Workaround Pattern → 軍師レビューヒント共有

`workaround_pattern_check.sh` がパターン検出した際、そのパターンを軍師にも `review_hint` として共有する。軍師がレビュー時にこのヒントを参照し、該当パターンを重点チェックすることで、同じ間違いの再発を水際で防ぐ。

**トリガー**: `karo_workaround_log.sh` 実行後に `workaround_pattern_check.sh` がパターンを検出した場合

**手順**: パターン検出時、以下のinbox_writeを実行して軍師にヒントを送信:
```bash
bash scripts/inbox_write.sh gunshi "レビューヒント: {パターン名}。忍者が頻繁に間違えるパターン。重点確認せよ" review_hint karo
```

- `{パターン名}` は `workaround_pattern_check.sh` が出力したパターン名に置換
- 軍師は受信した `review_hint` を次回以降のレビュー時に該当パターンを重点チェックする
- 複数パターンが同時検出された場合は、パターンごとに1通ずつ送信

→ `docs/research/karo-operations-detail.md` §3

## §3.5 DCエスカレーション（裁定重複チェック必須）

- 忍者報告のdecision_candidateを将軍にエスカレーションする前に、**必ず`pending_decisions.yaml`の全resolved裁定と照合**せよ。
- 既存裁定と重複するDCは起票せず「PD-XXXで裁定済み」として忍者に差し戻す。
- **Why**: 殿に同じ裁定を二度求めることは禁止（2026-03-16殿厳命）。PD-007朱雀全滅許容を再質問した失敗が契機。
- **How to apply**: DC受領→pending_decisions.yaml全件スキャン→重複なし→将軍へエスカレーション。重複あり→差し戻し+既存裁定を引用。

## §4 難問エスカレーション

- 1名で失敗し、原因不明または複雑なら同一タスクを2名へ独立配備する。
- これは初回から2名投入する偵察とは別原則。失敗後の増員である。
→ `docs/research/karo-operations-detail.md` §4

## §5 教訓抽出

- cmd完了後は `lesson_review.sh` でdraftを確認し、confirm/edit/delete を完了してから GATE に進む。
- 一般論ではなく、再利用可能な具体知見だけを正式化する。
- strategic 教訓は MCP 昇格候補として扱う。
→ `docs/research/karo-operations-detail.md` §5

## §6 宣言・薄書き・書込み

- 分割宣言は配備前の遵守証跡。1名配備なら例外理由を必ず書く。
- task YAML は薄書きが原則。既知知識を重複転記するな。
- すべて Read-before-Write。inbox既読化は `inbox_mark_read.sh` を使う。
- **task YAML作成はBash tool(`cat`/`echo`)で書け**（Write/Edit直接はhookブロック）。配備は `deploy_task.sh` 経由。
- **報告YAML操作は `report_field_set.sh` 経由**（Edit tool直接禁止=Lost Updateリスク）。
- **yqは環境に存在しない**。YAML操作ツール: `deploy_task.sh` / `report_field_set.sh` / `field_get.sh` / `yaml_field_set.sh`
→ `docs/research/karo-operations-detail.md` §6-7（YAML操作ツール詳細・コマンド書式あり）

## §7 配備前確認

- context圧縮前は `bash scripts/gates/gate_vercel_phase.sh {context_file}` を実行する。
- 初回配備や再配備失敗後は pre-deploy ping を必須にする。
→ `docs/research/karo-operations-detail.md` §8

## §8 通知・Frog・連勝

- cmd関連通知は `ntfy_cmd.sh`、それ以外は `ntfy.sh` を使い分ける。
- Frog は1日1件。cmd と VF task で競合する。
- cmd完了時は lesson review → cmd_complete_gate → GATE CLEAR → **cmd品質記録** → **status→completed** → archive の順を崩すな。
- **status→completed遷移**: GATE CLEAR確認後（全subtask done + gate CLEAR）、以下を実行してcmdのstatusをcompletedに遷移:
  ```
  bash scripts/lib/yaml_field_set.sh queue/shogun_to_karo.yaml "{cmd_id}" status completed
  ```
  これにより次回の `archive_completed.sh` 実行でアーカイブ対象になる。
- **workaroundログ記録（cmd完了時）**: cmd処理中にworkaround（忍者報告の手動修正・コード手直し等）を行った場合、cmd完了前に以下を実行:
  ```
  bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
  ```
  ※ workaroundを行った場合のみ。行わなかった場合は不要。詳細は§3 Workaroundログ記録を参照。
- **cmd品質記録**: GATE CLEAR/FAIL後、以下を実行:
  ```
  bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>
  ```
  自動取得: gunshi_verdict(karo inbox), ninja_blockers(報告YAML), ac_count(shogun_to_karo.yaml)
→ `docs/research/karo-operations-detail.md` §9

## §9 配備制約

- 本番DB操作は直列配備。コード修正や文書編集だけを並列化する。
- idle忍者が2名以上いて独立タスクがあるなら並列化は義務。
- レポート走査は起動時ごとに全 `queue/reports/*_report_cmd_*.yaml` を見る。
→ `docs/research/karo-operations-detail.md` §10-12

## §10 偵察完了後の家老起案

- `scout_only` 完了後は、家老が偵察報告を分析して次cmdを直接起案できる。
- その際は `scout_exempt: true` と `based_on: cmd_XXX` を明記する。
→ `docs/research/karo-operations-detail.md` §13

## §11 モデル運用

- 現行方針はランダム配備。名前や旧階級制で割り振らない。
- 設計判断や複雑レビューは Opus 優位、定型実装と偵察は Codex 優位。ただし配備順序の恣意性は避ける。
- CLI切替は `/clear` ではなく `switch_cli_mode.sh` を使う。
→ `docs/research/karo-operations-detail.md` §14-16

## §12 skill_candidate受領時の処理フロー

忍者の報告YAMLに `skill_candidate.found: true` がある場合の処理手順:

1. **収集**: 報告YAMLからskill_candidateの内容（name/description/reason/project）を確認
2. **dashboard記載**: dashboardの将軍宛報告セクション(🚨要対応)にスキル提案として記載
3. **将軍承認**: 将軍がスキル化の要否を判断。承認/却下/保留を裁定
4. **設計doc作成**: 承認後、家老がスキル設計（SKILL.md骨子・トリガー条件・入出力）をcmdとして起案
5. **実装cmd**: 設計完了後、スキル実装cmdを忍者に配備

- 忍者はスキルを実装しない。報告のみ。実装判断は家老→将軍承認の鎖に従う
- 複数の忍者から同一パターンのskill_candidateが上がった場合は優先度を上げる

## §13 gunshi_lesson_candidate受信時の処理フロー

軍師レビュー報告に `lesson_candidate` が含まれる場合の処理手順:

1. **重複チェック**: 既存教訓と重複していないか確認
   ```bash
   grep -i "<教訓キーワード>" projects/infra/lessons.yaml
   ```
   対象PJが infra 以外の場合は `projects/{project}/lessons.yaml` を検索。

2. **重複なし → 正式登録**: `lesson_write.sh` で教訓を登録（source: gunshi）
   ```bash
   bash scripts/lesson_write.sh infra "{title}" "{detail}" cmd_XXXX gunshi
   ```
   - `{title}`: 教訓タイトル（軍師報告から抽出）
   - `{detail}`: 具体的な知見（再利用可能な形に家老が要約）
   - `cmd_XXXX`: 元のcmd番号
   - 最後の引数 `gunshi` がsourceとして記録される

3. **重複あり → retagまたは補強**:
   - 既存教訓の `effectiveness` を確認
   - 軍師の指摘が既存教訓を強化する内容であれば、detail を補強
   - 同一内容であれば登録せず、既存教訓IDを軍師報告に紐付けるのみ

- **Why**: 軍師レビューで発見された知見を教訓基盤に還流し、忍者の品質を継続的に向上させるため
- **How to apply**: 軍師からの報告受信時（inbox type: gunshi_review等）にlesson_candidateフィールドの有無を確認。あれば本手順を実行

## §14 失敗ループ学習（retry_loop）

cmdに `retry_policy: retry_loop` がある場合、家老は以下のループ運用を行う。

### トリガー
将軍がcmdの `retry_policy` フィールドに `retry_loop` を含めた場合のみ発動。デフォルトではない。

### ループ手順（並列学習方式）
複数忍者を**異なるアプローチで同時配備**し、それぞれが独立にループする。
タイミングのズレにより、先に失敗した者の知見が後続全員に流れ、知見蓄積速度が並列数に比例して上がる。

1. 忍者N名を異なるアプローチで同時配備（`parallel_count` 指定、省略時1）
2. いずれかの忍者がFAIL → 報告YAMLを受領
3. 家老がFAIL報告を分析し、以下を判定:
   - **再試行可能**: 前回の失敗原因+**他忍者のFAIL知見も統合**してタスクYAMLに追記し、再配備
   - **人間必要**: reCAPTCHA突破不能、2FA要求、TOS制約等 → 該当忍者は停止。全員が人間必要なら**全ループ停止** → 殿にntfy報告
4. いずれかの忍者が**成功** → 他の忍者を全停止 → 通常のレビューフローへ

```
例: 3名並列ループ（タイミングズレが知見を加速）
T+0:  A1開始  B1開始  C1開始（異なるアプローチ）
T+5:  A1 FAIL → 知見α抽出
T+6:  A2開始（知見α反映）
T+7:  B1 FAIL → 知見β抽出
T+8:  B2開始（知見α+β反映）  ← Aの知見も吸収
T+9:  A2 FAIL → 知見γ抽出
T+10: C1 FAIL → 知見δ抽出
T+11: A3開始（α+β+γ+δ全統合） ← 全員の知見が集約
T+12: C2開始（α+β+γ+δ全統合）
...どこかで1名成功 → 全停止
```

### 知見の引き継ぎルール
- 各FAILの教訓を再配備時の `command` 欄に「■ 過去の試行結果」として埋め込む
- **自分の**過去FAILだけでなく、**他忍者の**FAILも含めて全知見を統合
- 家老が知見を要約・構造化して注入（丸コピー禁止、要点のみ）

### 家老の知見抽出品質（ループ空転防止）
ループの成否は**家老の分析力**に依存する。FAIL報告を受けたら以下を必ず行え:
- **過去成功時との差分特定**: 過去に同じ操作が成功した実績がある場合、「前回と今回で何が違うか」を特定し、次の忍者に伝えよ。差分が不明なら報告から読み取れる事実を全て列挙せよ
- **表層でなく構造を伝えよ**: 「reCAPTCHAが出た」ではなく「port 9222にtemp profileが起動し、既ログインセッションに接続できなかった。過去はEdgeが9222で動いていた」のように、なぜ失敗したかの構造を伝えよ
- **知見抽出が甘ければループは空転する**。3回同じ失敗を繰り返して終わるのは家老の責任

### 制限
- **max_retries: 3**（忍者1名あたり最大3回試行。cmdで上書き可）
- 全忍者が上限到達 → 全ループ停止 → `ntfy.sh` で殿にエスカレーション
- 「人間必要」判定は回数に関わらず即停止（該当忍者のみ。他は続行可）
- いずれか1名成功 → 他の全忍者を即停止（コスト制御）

### retry_policy フィールド仕様
```yaml
retry_policy: |
  retry_loop
  max_retries: 5        # 忍者1名あたり。省略時デフォルト3
  parallel_count: 3     # 同時配備数。省略時1（直列）
  assign_to_model: opus  # 省略時は通常配備ルール
```
