---
name: review-bundle
argument-hint: "[cmd_id] [verdict:APPROVE|FAIL] [fail_reason]"
user-invocable: false
quality_metric: "軍師系: review-bundle経由レビューのreview精度(後続gate/家老判定でverdict修正が不要だった割合)"
description: |
  【軍師専用】レビュー完了後のSG7バンドル生成→review_log記録→inbox送信を1コマンドで実行。
  precheck結果→報告YAML→判定→バンドルYAML構成→review_log追記→inbox_writeの4ステップ連鎖を自動化。
  TRIGGER: /review-bundle、レビュー完了後処理、SG7バンドル、レビュー記録
  DO NOT TRIGGER: レビュー判定そのもの（→手動）、gate_sync（→/gate-sync）、idle分析永続化（→/idle-persist）
---

<!-- script_refs_checked_at: 2026-05-22T18:54:13+09:00 -->

# /review-bundle — レビュー完了後処理スキル

レビュー判定後の4ステップ連鎖を1コマンドで実行。フォーマットブレ・転記忘れをゼロにする。

## 引数

`/review-bundle <cmd_id> <verdict: APPROVE|FAIL> [fail_reason]`

## 実行フロー

### Step 0: precheck実行（report review時のみ）

review_typeがreportの場合、レビュー判定の前提としてprecheckを実行せよ:
```bash
bash scripts/gates/gate_gunshi_report_precheck.sh <report_path>
```
- ERRORS>0 → FAIL理由にprecheck結果を含めよ
- precheckのGATE_PREDICTION出力をStep 1のgate_predictionに転記せよ
- precheck未実行のままStep 1に進むな（33件のGATE_PREDICTION記載なし=precheck未実行が根因。accuracy Goodhart是正で発見）
- **GATE_PREDICTION=WARN時はLGTMを出すな**。WARNの原因(lesson_candidate有/draft_lessons等)を確認し、BLOCK要因が家老処理待ちなら「verdict: LGTM, gate_prediction: WARN(理由)」と明記した上で家老に先行対処を依頼せよ。WARNを無視してLGTMを出すとBLOCK→再GATE無駄サイクルが発生する(cmd_karo_ci_fix_e2e_parallel事故)

### Step 1: SG7バンドル生成

レビュー結果をバンドルYAML形式で構成:
```yaml
review:
  cmd_id: <cmd_id>
  verdict: <APPROVE|FAIL>
  reviewer: gunshi
  reviewed_at: <ISO 8601>
  sg_checklist:
    SG1_ac_coverage: <PASS|FAIL>
    SG2_test_pass: <PASS|FAIL>
    SG3_parity: <PASS|FAIL|N/A>
    SG4_no_regression: <PASS|FAIL>
    SG5_lesson_candidate: <PASS|FAIL>
    SG6_code_quality: <PASS|FAIL>
    SG7_gate_prediction: <PASS|FAIL>
  fail_reason: <該当時のみ>
  gate_prediction: <CLEAR|BLOCK>
```

### Step 1.5: observations必須チェック（review_log追記前BLOCK）

**review_type = draft / report / self_study の場合に必須**。Step 2に進む前に確認せよ:

```
[ ] observationsフィールドが設定されているか？
[ ] 空リスト([])ではなく、具体的な事実が1件以上あるか？
```

→ **未記入/空の場合はSTOP。review_logへの追記を禁止する(BLOCK)。**
  observationsに事実3点（例: 「事実1: ...」「事実2: ...」「事実3: ...」）を記入してから再実行せよ。

**理由**: 22件中observationsが意志依存で放置された。記録なき知見は/clearで消える。
自動チェック(gunshi_log_append.sh使用時): observationsなし → exit 2(BLOCK)で追記拒否。

**draft review時の追加チェック**: review_type=draft の場合、ambiguity_pointsフィールドが設定されているか確認せよ。
未記入→STOP。`ambiguity_points: none` を明示してから再実行。理由: CS WARN 3件遡及(cmd_2881-2883)で発見。

**finding_categories自動補完**: ambiguity_points が `none` 以外の場合、finding_categories に `ambiguity` を含めよ。記録漏れ防止(2026-05-24: 全セッションambiguity 0件だが実態2件検出)。

### Step 2: review_log追記
```bash
# gunshi_review_log.yamlに追記
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" verdict "<verdict>"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" gate_prediction "<prediction>"
bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" reviewed_at "<timestamp>"
```

### Step 2.5: 初遭遇パターン検出（/clear耐久性）

review_log追記後、今回のレビューで使った判断パターンがreview_logヘッダに記載済みか照合せよ。

手順:
1. 今回のreview_logエントリのobservationsを読む
2. review_logヘッダ(#行)のキーワード群と照合する
3. **ヘッダに未記載の判断パターンがobservationsにあれば**、以下を表示:
   ```
   ★新パターン候補: {observationsの該当箇所}
   → review_logヘッダに1行追記して/clear耐久性を確保せよ
   ```
4. 該当なしなら無言で次へ

目的: レビュー中の判断パターンを/clear後も残す。「初遭遇パターンが頭の中だけに残り/clearで消失」を構造的に防止。
根拠: なぜなぜ7回(2026-05-15殿指示)で根因特定。5件/セッションの判断パターンが未埋込みだった。

### Step 3: 家老inbox送信
```bash
bash scripts/inbox_write.sh karo "cmd_<cmd_id>レビュー完了。verdict=<verdict>。" review_feedback gunshi
```

### Step 4: 掲示板投稿（FAIL時のみ）
FAIL時は将軍にも共有:
```bash
BULLETIN_NOTIFY=shogun,karo bash scripts/bulletin_write.sh gunshi "cmd_<cmd_id> FAIL — <fail_reason>" false action_required
```
`bulletin_write.sh` の現在仕様:
- 推奨形式は `bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]`。
- `requires_confirmation` は `true|false` または確認必須エージェントのCSV。`BULLETIN_NOTIFY` もCSV指定可能。
- `action_type` は `info` または `action_required`。FAIL共有は将軍/家老の対応が必要なため `action_required` を指定する。
- 同一 `posted_by` + 同一 `content` は重複投稿せずDEDUPする。
- 投稿後のinbox通知は掲示板本文全文を含む。`inbox_write` 失敗やwatcher未起動はWARN表示される。
- 投稿成功後に `yaml_auto_archive.sh` を自動呼出し。bulletin_board.yaml が閾値超過時に古いエントリをアーカイブする（cmd_2856）。

## 制約
- verdict判定は軍師の手動判断。このスキルは判定後の記録・送信のみ
- SG7チェックリストの各項目は事前に判定済みであること
- review_logのEdit直接編集禁止（yaml_field_set.sh経由）
- Script refs verified: 2026-05-22 cmd_2959. `yaml_field_set.sh` はflock、root fallback、map/list block対応、複数行・inline scalar継続の安全置換、post-write readback検証を行う。review_logへのverdict/gate_prediction/reviewed_at記録はhelper経由で実施する。
- Script refs verified: 2026-05-22 cmd_2952. `bulletin_write.sh` は明示 `posted_by` 形式を推奨し、旧形式(content先頭)も互換維持する。`requires_confirmation` / `BULLETIN_NOTIFY` のCSV正規化、不正agent名ERROR、`action_type=info|action_required` 制約、DEDUP、全文inbox通知、archive自動実行を前提にする。
