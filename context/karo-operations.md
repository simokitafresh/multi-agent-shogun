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

→ `docs/research/karo-operations-detail.md` §2

## §3 レビュー

- 家老の役割はレビュー配備とGATE判定のみ。品質判定そのものは忍者レビューに委ねる。
- verdict は PASS / FAIL の二値厳守。条件付きPASSは禁止。
- failed を放置するな。修正配備 / WAIVE→done / 殿裁定のいずれかへ必ず進める。
- Two-pass Review: CRITICALはblocking(PASS/FAIL直結)、INFORMATIONALは記録のみ(non-blocking)。→ detail §3 Two-pass Review
- A/B/C Triage: レビュー指摘を3分類。A:Fix(修正必須→impl再配備)、B:Acknowledge(認識するが今回対応不要→理由記録)、C:False Positive(偽陽性→以後抑制)。PASS/FAIL/WAIVEとの対応表あり。→ detail §3 A/B/C Triage
- Re-review Loop: blocking fix→修正task配備→再レビュー配備の明示フロー。曖昧に続行するな。→ detail §3 Re-review Loop
→ `docs/research/karo-operations-detail.md` §3

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
→ `docs/research/karo-operations-detail.md` §6-7

## §7 配備前確認

- context圧縮前は `bash scripts/gates/gate_vercel_phase.sh {context_file}` を実行する。
- 初回配備や再配備失敗後は pre-deploy ping を必須にする。
→ `docs/research/karo-operations-detail.md` §8

## §8 通知・Frog・連勝

- cmd関連通知は `ntfy_cmd.sh`、それ以外は `ntfy.sh` を使い分ける。
- Frog は1日1件。cmd と VF task で競合する。
- cmd完了時は lesson review → cmd_complete_gate → GATE CLEAR → archive の順を崩すな。
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

## §13 失敗ループ学習（retry_loop）

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
