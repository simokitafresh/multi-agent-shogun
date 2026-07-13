---
name: idle-persist
argument-hint: "[topic] [summary]"
user-invocable: false
description: |
  【軍師専用】idle自走分析結果をdocs/researchに保存→掲示板投稿→review_log記録の永続化フローを1コマンドで実行。
  ファイル命名規則(gunshi_idle_{topic}_{date}.md)を自動適用し、ブレをゼロにする。
  TRIGGER: /idle-persist、idle分析永続化、分析結果保存、自走分析記録
  DO NOT TRIGGER: レビュー完了処理（→/review-bundle）、gate同期（→/gate-sync）
quality_metric: "当該スキル利用後の軍師review精度（logs/gunshi_review_log.yamlで当該分析由来レビューのgate_prediction==gate_resultとなった割合）"
---

<!-- script_refs_checked_at: 2026-07-13T14:15:58+09:00 -->
<!-- Script refs verified 2026-07-13 shogun復帰時: checked_at以降の変更(yaml_field_set wrapped scalar保持fix de3df4b83, deploy_task parent AC contract dbcb20aa2, ninja_monitor journal+flock 93f8c898e/16f16e699, db_capability_launcher scoped credential 84231a01c)をgit logで確認。全て内部強化で呼出し契約・出口文言不変 -->

Script refs verified: 2026-07-13 将軍検分. `yaml_field_set.sh` checked_at以降の変更(692b6c8d8)をgit showで確認。post-write検証統一+安全エスケープ=内部改善。契約不変。手順書き換え不要。

Script refs verified: 2026-07-11 shogun起動時gate WARN解消。checked_at以降の変更(review two-phase race fix系/inbox gate trigger detach/report discovery偽BLOCK根治/rg grepフォールバック/memory DB cache atomic recovery)をgit logで確認。いずれも内部強化であり呼び出し契約・出口文言・本文手順に変更なし。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: bulletin_write.sh 61ad778f4で通知失敗が3回retry+failure log+exit 1のfail-closedへ変更。掲示板投稿の終了コードを確認し、失敗時はreview_log/家老通知へ進まず再処理する。inbox_write.sh e89307c7cはreport/task_done時の非重複dirty hunk除外をSSOT化した内部gate変更で、`bash scripts/inbox_write.sh <target> "<message>" <type> <from>`契約は不変 -->

Script refs verified: 2026-07-07 cmd_3743. `inbox_write.sh` checked_at以降の変更(b8285b3c9/e949b27b5/71ab22b6d)をgit logで確認。review context添付、memory references追加、model-aware injection profileの内部メタデータ追加で、`bash scripts/inbox_write.sh <target> "<message>" <type> <from>` の呼び出し契約、idle分析保存→掲示板→review_log→家老通知手順は変更なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `inbox_write.sh` 直近変更(832a032d4)はAGENT_CONFIG_LOADED gateによるtypeコマンドskip高速化で、`bash scripts/inbox_write.sh <target> "<message>" <type> <from>` の呼び出し契約、idle分析保存→掲示板→review_log→家老通知手順は変更なし。

# /idle-persist — idle分析永続化スキル

idle自走分析の結果を標準フローで永続化。命名・投稿・記録のブレをゼロに。

## 引数

`/idle-persist <topic> <summary>`
- topic: 分析トピック（英語snake_case）
- summary: 掲示板投稿用1行サマリ

## 実行フロー

### Step 1: ファイル名生成
```
docs/research/gunshi_idle_<topic>_<YYYYMMDD>.md
```
日付は当日。同名ファイルが存在する場合は末尾に`_2`を付与。

### Step 2: 分析結果をファイルに書出し
分析結果テキストをWrite toolで保存。ヘッダ:
```markdown
# <Topic Title>
<!-- generated: YYYY-MM-DDTHH:MM:SS+09:00 by gunshi idle analysis -->
```

### Step 3: 掲示板投稿
```bash
BULLETIN_NOTIFY=shogun bash scripts/bulletin_write.sh gunshi "<summary>→docs/research/gunshi_idle_<topic>_<date>.md" false info
```
`bulletin_write.sh` の現在仕様:
- 推奨形式は `bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]`。
- `requires_confirmation` は `true|false` または確認必須エージェントのCSV。`BULLETIN_NOTIFY` もCSV指定可能。
- `action_type` は `info` または `action_required`。idle分析の永続化報告は通常 `info`。
- 同一 `posted_by` + 同一 `content` は重複投稿せずDEDUPする。
- 投稿後のinbox通知は掲示板本文全文を含む。`inbox_write` 失敗やwatcher未起動はWARN表示される。
- 投稿成功後に `yaml_auto_archive.sh` を自動呼出し。bulletin_board.yaml が閾値超過時に古いエントリをアーカイブする（cmd_2856）。
- Script refs verified: 2026-06-02 cmd_3114/0ec9b1fc. `inbox_write.sh` は `from=shogun type=cmd_new` で本文に `cmd_XXXX` が含まれない場合をBLOCKする。軍師から家老への `gunshi_lesson_candidate` 送信は対象外。`report_done` は `report_received` / `task_done` / `report_completed` と同じreport format gate + task done hook対象になったが、Step 5の送信typeは変更しない。
- Script refs verified: 2026-05-29 cmd_3087/3091. `inbox_write.sh` の最新変更は忍者報告完了type `report_completed` のreport gate/auto-done対象追加であり、Step 5の `gunshi_lesson_candidate` 送信手順には影響しない。
- Script refs verified: 2026-05-24 cmd_3026. `inbox_write.sh` cmd_3022変更は `report_received` / `task_done` のFAIL報告差戻しであり、Step 5の `gunshi_lesson_candidate` 送信手順には影響しない。
- Script refs verified: 2026-05-22 cmd_2959. `inbox_write.sh` は `from=shogun type=task_new` をBLOCKする。軍師から家老への `gunshi_lesson_candidate` 送信は対象外だが、将軍の作業指示を `task_new` で直送する手順をこのスキルへ追加してはならない。`yaml_field_set.sh` はflock+post-write readback検証付き。report_format_gate修正メッセージはverdict例ではなくbinary_checks.AC1例を示す(verdictはgateが自動導出)。
- Script refs verified: 2026-05-22 cmd_2952. `bulletin_write.sh` は明示 `posted_by` 形式を推奨し、旧形式(content先頭)も互換維持する。`requires_confirmation` と `BULLETIN_NOTIFY` は `true|false` またはエージェントCSVを正規化する。idle分析の共有は `BULLETIN_NOTIFY=shogun` + `action_type=info` を使い、全員共有が必要な場合だけ通知先CSVを広げる。

### Step 4: review_log記録
```bash
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" type "idle_analysis"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "idle_<topic>_<date>" output "docs/research/gunshi_idle_<topic>_<date>.md"
```

### Step 5: 利他還流判断（LG030 gate化）
分析結果が他者(忍者/家老)のlessonsに追加すべき知見を含むか判断する。

判断基準: 「この知見を忍者/家老が知っていれば、将来のWA/BLOCK/再cmdを防げるか？」
- **YES** → `bash scripts/inbox_write.sh karo "{知見1行要約}" gunshi_lesson_candidate gunshi` を送信
- **NO** → review_logエントリの `altruism_check: not_needed` に理由を1行記載

★ このStepを省略するな。利他還流の判断自体が記録される(YES=送信/NO=理由)ことで、LG030「行動完了≠還流完了」を構造的に解消する。

### Step 6: 行動確認（提案≠行動 gate化 — 殿厳命2026-06-14）
分析結果に改善提案が含まれる場合、**提案だけで終わるな。同一ターンで行動せよ。**

判断基準: 「この分析で穴/改善余地を特定したか？」
- **YES + D0可能(1ファイル20行以下)** → 即D0実装+commit+家老通知。掲示板投稿は行動の後
- **YES + D0不可** → 掲示板にcmd起票提案を即投稿（BULLETIN_NOTIFY=shogun）。提案だけで止まるな
- **NO(分析のみ)** → Step 6不要

★ 掲示板投稿・返信・分析報告は「出力」であり「行動」ではない（CLAUDE.md）。
行動=コード変更/教訓追記/gate修正。提案を行動と感じるのは洗脳#6(出力=仕事)。
このStepなしにidle-persistを終了するな。穴を見つけて報告だけで止まった=洗脳#6が発現した証拠。

## 制約
- ファイル名は `gunshi_idle_` プレフィックス固定（検索性担保）
- 日付はYYYYMMDD形式（ISO 8601のdate部分）
- 掲示板通知先はデフォルトshogunのみ（全員共有不要な場合）
- Script refs verified: 2026-05-22 cmd_2959. `yaml_field_set.sh` はflock、root fallback、map/list block対応、複数行・inline scalar継続の安全置換、post-write readback検証を行う。idle分析のreview_log記録はhelper経由で完了させる。

Script refs verified: 2026-06-09 cmd_karo_skill_update_batch1. `yaml_field_set.sh` 直近変更(3de0d29c)は_yaml_field_set_apply_rootのskip_children条件修正(内部バグフィックス、I/F変更なし)。本スキルはroot操作を使わないため直接影響なし。flock+readback検証の契約は維持。
Script refs verified: 2026-06-12 cmd_karo_hotfix_skill_refs_202606121132. `inbox_write.sh` 直近変更(e2df9b4d2)は分割cmd完了時のtask completion判定許可を追加した内部hook対象制御。`bash scripts/inbox_write.sh karo "{知見1行要約}" gunshi_lesson_candidate gunshi` の契約とidle分析保存→掲示板→review_log→家老通知手順は変更なし。
Script refs verified: 2026-06-07 cmd_3206. `inbox_write.sh` はサブシェル削減で高速化されたが、`bash scripts/inbox_write.sh <target> "<message>" <type> <from>` の契約とhook対象type制御は維持。`bulletin_write.sh`/`yaml_field_set.sh` もI/F変更なし。SKILL.md記載のidle分析保存→掲示板→review_log→家老通知手順は現行と一致。

Script refs verified: 2026-06-20 48204a464. `bulletin_write.sh`/`inbox_write.sh` 直近変更は操作的オントロジー、targetフィルタ、スキル強制の内部反映。idle分析保存→掲示板投稿→review_log記録→家老通知の呼び出し契約は変更なし。

Script refs verified: 2026-06-21 1e7a7cc4b. `inbox_write.sh` 直近変更はcommander role SSOT反映。`bash scripts/inbox_write.sh karo "{知見1行要約}" gunshi_lesson_candidate gunshi` の契約とidle分析保存→掲示板→review_log→家老通知手順は変更なし。

Script refs verified: 2026-06-26 cmd_karo_hotfix_skill_refs_20260626082009. `bulletin_write.sh` の現物未commit差分は `compute_notify_targets` 追加と `notify_targets` 記録追加。投稿者を通知先から除外する既存挙動、`BULLETIN_NOTIFY=shogun`、`requires_confirmation=false`、`action_type=info`、`bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]` の呼び出し契約は変更なし。idle分析保存→掲示板投稿→review_log記録→家老通知手順は現行と一致。

Script refs verified: 2026-06-28 75aac6a10. `yaml_field_set.sh` 直近変更は既存ブロックへの新規field挿入位置を末尾行手前へ修正する内部バグ修正。idle分析のreview_log記録手順とhelper呼び出し契約は変更なし。

Script refs verified: 2026-07-02 a2e4e93cc. `bulletin_write.sh` 直近変更は引数順序ミス検出ガード追加(contentがagent名ならERROR)。本SKILL.mdの掲示板投稿手順は正しい引数順のため契約に変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->
