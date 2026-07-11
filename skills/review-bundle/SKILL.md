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

<!-- script_refs_checked_at: 2026-07-12T01:45:00+09:00 -->

Script refs verified: 2026-07-11 shogun起動時gate WARN解消。checked_at以降の変更(review two-phase race fix系/inbox gate trigger detach/report discovery偽BLOCK根治/rg grepフォールバック/memory DB cache atomic recovery)をgit logで確認。いずれも内部強化であり呼び出し契約・出口文言・本文手順に変更なし。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: bulletin_write.sh 61ad778f4で通知失敗が3回retry+failure log+exit 1のfail-closedへ変更。FAIL掲示板投稿の終了コードを確認し、失敗時はバンドル完了扱いにしない。inbox_write.sh e89307c7cはreport/task_done時の非重複dirty hunk除外をSSOT化した内部gate変更で、review_feedbackの位置引数契約は不変 -->

Script refs verified: 2026-07-07 cmd_3743. `inbox_write.sh` checked_at以降の変更(b8285b3c9/e949b27b5/71ab22b6d)をgit logで確認。review context添付、memory references追加、model-aware injection profileの内部メタデータ追加で、Step 3の `bash scripts/inbox_write.sh karo "$MESSAGE" review_feedback gunshi` 契約、永続化確認、retry手順は変更なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `inbox_write.sh` 直近変更(832a032d4)はAGENT_CONFIG_LOADED gateによるtypeコマンドskip高速化で、Step 3の `bash scripts/inbox_write.sh karo "$MESSAGE" review_feedback gunshi` 契約、永続化確認、retry手順は変更なし。

Script refs verified: 2026-06-12 cmd_karo_hotfix_skill_refs_202606121132. `inbox_write.sh` 直近変更(e2df9b4d2)は分割cmd完了時のtask completion判定許可を追加した内部hook対象制御。Step 3の `bash scripts/inbox_write.sh karo "$MESSAGE" review_feedback gunshi` 契約、永続化確認、retry手順は変更なし。
Script refs verified: 2026-06-09 cmd_karo_skill_update_batch1. `yaml_field_set.sh` 直近変更(3de0d29c)は_yaml_field_set_apply_rootのskip_children条件修正(内部バグフィックス、I/F変更なし)。本スキルはroot操作を使わないため直接影響なし。flock+readback検証の契約は維持。
Script refs verified: 2026-06-07 cmd_3206. `inbox_write.sh` はサブシェル削減の高速化のみで、review_feedback送信の引数契約は変更なし。`bulletin_write.sh` のposted_by/content/requires_confirmation/action_type仕様と`yaml_field_set.sh`のflock+readback検証も維持。SKILL.md記載のレビュー記録・通知手順は現行と一致。

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
- precheckのGATE_PREDICTION reasonをStep 1のgate_prediction_reasonに転記せよ（GP-259）。CLEAR時は `all checks passed`、WARN/BLOCK時は具体reasonを記録する。
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
  gate_prediction_reason: <precheck reason。CLEAR時は all checks passed>
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

**q11突合チェック(draft review時)**: q11_not_already_doneに「rg → 0件」等の現物確認記載がある場合、`git show HEAD:対象ファイル`で独立検証せよ。将軍のq11事実誤認率50%(2/4, 2026-05-24)。LG001(git show HEAD検証)をq11にも適用。

**finding_categories自動補完**: ambiguity_points が `none` 以外の場合、finding_categories に `ambiguity` を含めよ。記録漏れ防止(2026-05-24: 全セッションambiguity 0件だが実態2件検出)。

**adversarial自動補完**: 全レビューでfinding_categoriesに `adversarial` を含めよ。adversarial_review フィールドに検討結果(PASS/N/A+reason)を必ず記載。scripts/変更cmdは必須。その他cmdもN/Aで記録。記録なし=冷え観点zero_streak蓄積→WARN→3セッション先送りCRITICAL(2026-06-17遡及修正で解消した事故の再発防止)。

**6観点全記録(冷え観点防止)**: draftレビューではfinding_categoriesに6観点カタログ全て(assumptions, numbers, simulation, premortem, north_star, adversarial)を記載せよ。reportレビューでも4観点(assumptions, numbers, premortem)+adversarialを記載。1観点のみの記載は冷え観点WARNの直接原因(2026-06-21: 11件冷え+3セッション連続ALERT事故)。観点を通したが所見なしの場合もfinding_categoriesに含めよ。

**GATE結果確証バイアス防止**: report reviewでGATE CLEARを既に知っている場合、brainwash_checkに「GATE CLEAR既知で確証バイアスリスクあり」と明記し、成果物を`git show`で全行独立確認せよ。GATE結果を知った上で「問題ない」と感じるのはP1(早期終了)の典型(2026-05-24: cmd_3037でリスク顕在化、cmd_karo_ci_fix_cs_checklistでLGTM→BLOCK発生)。

**gate_prediction_reason必須(GP-259)**: review_type=report で gate_prediction を記録する場合、`gate_prediction_reason` も必ず記録せよ。未記入/空/`engine未実行` は `gunshi_log_append.sh` がBLOCKする。理由: gate_prediction偽陽性分析で「BLOCK予測の理由」が残らず、後続の精度改善が推測依存になった。

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

### Step 3: 家老inbox送信 + 永続化確認 + retry
report reviewでLGTMを通知する前に、レビューした現物へfingerprintを固定する。この承認境界が将軍へ「完了レビューLGTM・家老/GATE判定待ち」を自動永続通知する:
```bash
bash scripts/review_approval.sh "$CMD_ID" gunshi LGTM "$REPORT_PATH"
```
このコマンド成功前にLGTM通知を送るな。report更新後は再レビュー・再実行が必須。

```bash
CMD_ID="<cmd_id>"
VERDICT="<verdict>"
MESSAGE="${CMD_ID}レビュー完了。verdict: ${VERDICT}。report: ${REPORT_PATH}"
MAX_ATTEMPTS=3
attempt=1

while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  bash scripts/inbox_write.sh karo "$MESSAGE" review_feedback gunshi

  if python3 - "queue/inbox/karo.yaml" "$MESSAGE" <<'PY'
import sys
import yaml

path, expected = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

for msg in reversed(data.get("messages") or []):
    if (
        str(msg.get("content") or "") == expected
        and str(msg.get("from") or "") == "gunshi"
        and str(msg.get("type") or "") == "review_feedback"
    ):
        print(msg.get("id", "id_missing"))
        raise SystemExit(0)

raise SystemExit(1)
PY
  then
    echo "[review-bundle] inbox_write verified: karo received review_feedback"
    break
  fi

  if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
    echo "[review-bundle] BLOCKED: karo inbox verification failed after ${MAX_ATTEMPTS} attempts" >&2
    exit 1
  fi

  echo "[review-bundle] WARN: karo inbox verification failed; retry ${attempt}/${MAX_ATTEMPTS}" >&2
  sleep 1
  attempt=$((attempt + 1))
done
```

送信後は必ず `queue/inbox/karo.yaml` に同一 `content` + `from: gunshi` + `type: review_feedback` が存在することを確認せよ。確認不能のままStep 4へ進むな。

### Step 4: 掲示板投稿（FAIL時）
LGTMはStep 3の `review_approval.sh` が将軍へ自動投稿する。手動の二重投稿は不要。FAIL時は将軍にも共有:
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

Script refs verified: 2026-06-03 cmd_3144. `bulletin_write.sh` 直近変更(c356e7ae)はDB insert同期/非同期切替(内部のみ)。`inbox_write.sh` 直近変更(0ec9b1fc)はreport_done typeのhook対象追加(Step 3のreview_feedback送信には影響なし)。`yaml_field_set.sh` 直近変更(670918b3)はsingle-quoteエスケープ修正(内部バグフィックス)。SKILL.md記載の手順は現行と一致。

Script refs verified: 2026-06-20 48204a464. `bulletin_write.sh`/`inbox_write.sh` 直近変更は操作的オントロジー、targetフィルタ、スキル強制の内部反映。review_log記録後の掲示板投稿・家老通知の呼び出し契約は変更なし。

Script refs verified: 2026-06-21 1e7a7cc4b. `inbox_write.sh` 直近変更はcommander role SSOT反映。review_log記録後の掲示板投稿・家老通知の呼び出し契約は変更なし。

Script refs verified: 2026-06-26 cmd_karo_hotfix_skill_refs_20260626082009. `bulletin_write.sh` の現物未commit差分は `compute_notify_targets` 追加と `notify_targets` 記録追加。投稿者を通知先から除外する既存挙動、`BULLETIN_NOTIFY=shogun,karo`、`requires_confirmation=false`、`action_type=action_required`、`bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]` の呼び出し契約は変更なし。FAIL時掲示板投稿手順は現行と一致。

Script refs verified: 2026-06-28 75aac6a10. `yaml_field_set.sh` 直近変更は既存ブロック内の新規field挿入位置を修正した内部バグ修正。review_logへのverdict/gate_prediction/reviewed_at記録契約は変更なし。

Script refs verified: 2026-07-02 a2e4e93cc. `bulletin_write.sh` 直近変更は引数順序ミス検出ガード追加(contentがagent名ならERROR)。本SKILL.mdのinbox送信・掲示板投稿手順は正しい引数順のため契約に変更なし。

<!-- script_refs_checked_at: 2026-07-12T01:45:00+09:00 -->
<!-- origin: [[報告未送信]] -> [[手動後処理依存]] -> [[review_approval_fail_closed通知]] -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->
