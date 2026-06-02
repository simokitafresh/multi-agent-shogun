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

<!-- script_refs_checked_at: 2026-06-03T10:00:00+09:00 -->

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

## 制約
- ファイル名は `gunshi_idle_` プレフィックス固定（検索性担保）
- 日付はYYYYMMDD形式（ISO 8601のdate部分）
- 掲示板通知先はデフォルトshogunのみ（全員共有不要な場合）
- Script refs verified: 2026-05-22 cmd_2959. `yaml_field_set.sh` はflock、root fallback、map/list block対応、複数行・inline scalar継続の安全置換、post-write readback検証を行う。idle分析のreview_log記録はhelper経由で完了させる。

Script refs verified: 2026-06-03 cmd_3144. `bulletin_write.sh` 直近変更(c356e7ae)はDB insert同期/非同期切替(内部のみ)。`inbox_write.sh` 直近変更(0ec9b1fc)はreport_done typeのhook対象追加(Step 5のgunshi_lesson_candidate送信には影響なし)。`yaml_field_set.sh` 直近変更(670918b3)はsingle-quoteエスケープ修正(内部バグフィックス)。SKILL.md記載の手順は現行と一致。
