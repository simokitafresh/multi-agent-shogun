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
- Two-pass Review: CRITICALはblocking(PASS/FAIL直結)、INFORMATIONALは記録のみ(non-blocking)。→ `docs/research/karo-operations-detail.md` §3 Two-pass Review
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
