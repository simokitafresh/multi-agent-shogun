---
name: dashboard-update
argument-hint: ""
user-invocable: false
description: |
  【家老専用】将軍・忍者は使用禁止。
  ダッシュボードのKARO_SECTIONをプライマリYAMLデータから自動生成し、
  構成を固定化して手動編集による抜け・漏れ・構成ブレを防止する。
  生成後にntfyで殿に1行サマリを送信する。
  TRIGGER: /dashboard-update、cmd完了後のダッシュボード更新、GATE CLEAR後
  DO NOT TRIGGER: DASHBOARD_AUTO_SECTIONの更新（→dashboard_auto_section.sh）、
  ダッシュボードの閲覧のみ（→Read dashboard.md）
quality_metric: "当該スキル実行後のcmd_complete_gate.sh初回CLEAR率（dashboard/KARO_SECTION関連BLOCKの有無で集計）"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Glob
  - Grep
---

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-07-11 shogun起動時gate WARN解消。checked_at以降の変更(review two-phase race fix系/inbox gate trigger detach/report discovery偽BLOCK根治/rg grepフォールバック/memory DB cache atomic recovery)をgit logで確認。いずれも内部強化であり呼び出し契約・出口文言・本文手順に変更なし。
<!-- 検分: gate_report_format.sh bc8c87bc5 非重複post-commit dirty hunk許容(commit後に他エージェントが積んだ無関係hunkでFAILしない緩和)。報告gate契約 `bash scripts/gates/gate_report_format.sh <report_yaml>` とverdict自動導出は不変 -->
<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
<!-- 検分: dashboard_update.sh 9a4627f23 hyphenated training cmd id許可、gate_report_format.sh 460db6e2b session_state-only task diff除外。dashboard生成契約 `bash scripts/dashboard_update.sh <cmd_id> [--dry-run]` と報告gate契約は不変 -->
<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-07-04 cmd_training_skill_refs_dashboard_update_202607042005. checked_at 2026-07-03T02:15:00+09:00 以降の `dashboard_update.sh` 差分は bb140170d (`cmd_karo_hotfix_dashboard_snapshot_stale_status_202607041407`) のみ。AUTO域再生成直前に `ninja_monitor.sh` の `refresh_karo_snapshot_fast_path` をtimeout 20で呼び、snapshot stale status/model/idleを減らす内部更新で、呼び出し契約 `bash scripts/dashboard_update.sh <cmd_id> [--dry-run]` とpre-flightのcmd_id必須契約は変更なし。

Script refs verified: 2026-07-04 cmd_training_skill_refs_dashboard_update_202607042005. checked_at 2026-07-03T02:15:00+09:00 以降の `gate_report_format.sh` 差分は 83fc58fd (`cmd_karo_hotfix_commit_missing_structural_202607032250`) のみ。bc:commit=yes時の未commit検査が `target_path` に加えて報告YAMLの `files_modified` 申告ファイルも対象にする強化で、dashboard更新前に `bash scripts/gates/gate_report_format.sh <report_yaml_path>` を実行して報告YAMLをPASSさせる期待値は維持。binary_checks由来verdict自動導出、未記入/FILL_THIS BLOCK、PASS cache契約も変更なし。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-06-26 cmd_3550. `gate_report_format.sh` 直近変更後も `bash scripts/gates/gate_report_format.sh <report_yaml_path>` の報告YAML検証契約は変更なし。dashboard生成契約 `bash scripts/dashboard_update.sh <cmd_id> [--dry-run]` も変更なし。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-06-20 a16c93387+48204a464. `dashboard_update.sh` 直近変更はLS071統合/Guard18運用データ反映、`gate_report_format.sh` 直近変更は操作的オントロジー/targetフィルタ/スキル強制の内部検査強化。dashboard生成コマンドと報告YAML検証契約は変更なし。

Script refs verified: 2026-06-21 729635be5. `dashboard_update.sh` 直近変更はmodel family literalのSSOT化。`bash scripts/dashboard_update.sh <cmd_id> [--dry-run]` の生成契約、報告YAML検証契約は変更なし。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

Script refs verified: 2026-06-11. `dashboard_update.sh` の契約は `<cmd_id> [--dry-run]` のまま。`gate_report_format.sh` は `bash scripts/gates/gate_report_format.sh <report_yaml_path>` で報告YAMLを検証し、binary_checks由来verdict自動導出・未記入BLOCK・PASS cache・auto-commit contamination WARNの契約変更なし。

# /dashboard-update — KARO_SECTION自動生成

## 概要

dashboard.mdの `<!-- KARO_SECTION_START -->` 〜 末尾を、プライマリYAMLデータから自動生成する。
手動編集を排除し、構成を固定化する。

## 実行手順


### 自動防止ステップ
- <!-- skill-auto-improve:128a16e75f3b --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=cmd_karo_test dry_run=true」(count=3, last=2026-05-02T22:12:29+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:9d0870339f22 --> 自動防止: gate=gate_report_format のTop FAIL理由「verdict: \"\" is not valid (must be \"PASS\", \"FAIL\", or \"PASS_NO_IMPROVEMENT\")」(count=3, last=2026-05-02T18:11:25+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:3f94d27af048 --> 自動防止: gate=gate_report_format のTop FAIL理由「assumption_invalidation: is str (must be dict)」(count=1, last=2026-05-02T18:38:56+0900)を避けるため、該当Step完了直後に同条件を確認し、FAILなら次へ進まず修正する。
- <!-- skill-auto-improve:76e50054331e --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=cmd_2514 dry_run=false」(count=1, last=2026-05-03T03:37:31+0900)を避ける。確認: FAIL理由 `dashboard_update.sh exit=1 cmd=cmd_2514 dry_run=false` と同じ条件をゲート直前に再現確認する。修正: 同じFAILが出る状態なら次Stepへ進まず、該当フィールド/手順を修正してゲートを再実行する。
- <!-- skill-auto-improve:175323aca05b --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=cmd_karo_ci_fix_bulletin_flaky dry_run=false」(count=1, last=2026-05-02T20:33:17+0900)を避ける。確認: FAIL理由 `dashboard_update.sh exit=1 cmd=cmd_karo_ci_fix_bulletin_flaky dry_run=false` と同じ条件をゲート直前に再現確認する。修正: 同じFAILが出る状態なら次Stepへ進まず、該当フィールド/手順を修正してゲートを再実行する。
- <!-- skill-auto-improve:c398bf4e2c8d --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=cmd_2739 dry_run=false」(count=1, last=2026-05-15T02:21:46+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
- <!-- skill-auto-improve:9179239198ca --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=--dry-run dry_run=false」(count=1, last=2026-05-19T13:34:57+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
- <!-- skill-auto-improve:b21edfc61339 --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=<empty> dry_run=false」(count=1, last=2026-05-19T13:35:02+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。

Script refs verified: 2026-05-22 cmd_2959. `gate_report_format.sh` は `gate_report_format_combined.py` によるautofix+validation統合、PASS cache、`GATE_FAST_EXIT`/`GATE_NO_LOG`、中間状態FAILログ抑止、task_clarity未記入WARN、PASS時のreport-write/verdict-check skill log非同期化を持つ。dashboard更新前の報告YAML検証はこの現行gate出力を正本にする。
- <!-- skill-auto-improve:64b8fce83277 --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=<cmd_id> dry_run=false」(count=31, last=2026-05-19T12:33:06+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
- <!-- skill-auto-improve:40a8ebc501f9 --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=<cmd_id> dry_run=true」(count=4, last=2026-05-02T22:12:29+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。

- <!-- skill-auto-improve:71d8b7030df8 --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=1 cmd=--help dry_run=false」(count=2, last=2026-06-06T18:02:10+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
- <!-- skill-auto-improve:b6620bfa817a --> 自動防止: gate=dashboard_update のTop FAIL理由「dashboard_update.sh exit=2 cmd=<cmd_id> dry_run=false」(count=1, last=2026-06-08T02:29:18+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
### pre-flight: cmd_id空パラメータ検出

`dashboard_update.sh` 実行前に必ず `cmd_id` を明示し、空文字・`--dry-run`単独・`cmd_`以外の値なら実行しない。training cmdのskill名に含まれるハイフンは有効なcmd_id文字として許可する。cmd_id未指定のまま実行すると `dashboard_update.sh exit=1 cmd=<empty>` / `cmd=--dry-run` がskill FAILとして記録される。

```bash
cmd_id="${1:-}"
if [ -z "$cmd_id" ] || [ "$cmd_id" = "--dry-run" ] || ! [[ "$cmd_id" =~ ^cmd_[A-Za-z0-9_-]+$ ]]; then
  echo "BLOCK: dashboard-update requires cmd_id like cmd_3193 before optional --dry-run" >&2
  exit 1
fi
bash scripts/dashboard_update.sh "$cmd_id" --dry-run
```

実行例:

```bash
bash scripts/dashboard_update.sh cmd_3193 --dry-run
```
### Step 1: データ収集

以下のデータソースを読み、変数を収集する:

```
1. queue/karo_snapshot.txt
   → idle忍者リスト、配備状態、報告状態

2. queue/shogun_to_karo.yaml（直近10件のcmd）
   → 最近completed/delegatedのcmd一覧
   → パイプライン（status: delegated のcmd）

3. queue/reports/*_report_cmd_*.yaml（直近5cmd分）
   → 各報告のlesson_candidate(found: true), decision_candidate(found: true)
   → summary（1行要約）
   → workaround有無

4. logs/karo_workarounds.yaml（直近5件）
   → WA傾向

5. queue/pending_decisions.yaml
   → 未解決PD（status: pending のみ。resolved/archivedは除外）

6. logs/gunshi_review_log.yaml + logs/archive/gunshi_review_log_*.yaml（全ログファイル走査必須）
   → proposals内のstatus: pending/proposed のGP提案のみ抽出
   → implemented/accepted/rejected/completedは除外
   → ★current logだけでなくarchive含む全ファイルを走査せよ（LK039: archived logにもpending GPが残存する）

7. dashboard.md AUTO_SECTION（<!-- DASHBOARD_AUTO_START --> 〜 <!-- DASHBOARD_AUTO_END -->）
   → `### CI Status` の値を取得（CI GREEN / CI赤 / check failed 等）
   → 要修正事項の自動生成に使用。手書き禁止(LK043)
```

### Step 2: セクション生成

以下の**固定構成**でKARO_SECTIONを生成する。セクション順序・見出しは変更禁止:

```markdown
<!-- KARO_SECTION_START -->
## 最新更新 ({現在日時}更新)
- **cmd_XXXX**: {GATE結果}。{purpose要約}。{忍者名}完遂。WA: {WA有無}
- **cmd_YYYY**: ...
（直近GATE CLEARした3件。completedのcmdからpurposeとreport summaryを組み合わせる）

### パイプライン
{delegated状態のcmdがあれば表示。なければ「パイプライン空 — 次cmd待ち」}

### idle忍者
{karo_snapshotのidle行から。例: 6名全員idle(疾風,影丸,半蔵,才蔵,小太郎,飛猿)}

### 将軍宛報告
{直近報告からlesson_candidate(found:true)とdecision_candidate(found:true)を抽出}
{形式: - [INSIGHT] cmd_XXXX {忍者名}: {LC/DC}: {summary}}
{なければ「新規報告なし」}

### 要修正事項
{以下のデータソースから自動生成。手書き禁止(LK043)}
{1. CI状態: Step 1-7で取得したAUTO_SECTIONのCI Statusが「CI GREEN」以外なら「CI赤: {値}」を記載}
{2. 上記全て該当なし → 「（なし）」}

## 🚨要対応
{pending_decisions.yamlからstatus: pendingの項目を表示}
{形式: ### {PD-ID}: {title}\n{description}\n}
{0件なら「（なし）」}

## 🔧 軍師提案(pending)
{logs/gunshi_gp_tracker.yaml(SSOT)からstatus: karo_sent/pending/proposed のGPエントリを表示}
{形式: | GP | 内容 | 状態 |\n|----|------|------|\n| GP-XXX | {description} | {status} |}
{0件なら「新規提案なし」}
{★データソース=gp_tracker.yaml一択。archiveのproposalsは凍結スナップショットであり参照禁止(GP ID衝突+status未更新で古いGPが混入する根因)}
```

**重要: `<!-- KARO_SECTION_END -->` マーカーは生成しない。** KARO_SECTIONはファイル末尾まで。
これにより、手動追記がセクション外に溜まる構造を封じる。

### Step 3: dashboard.md更新

1. dashboard.mdを読む
2. `<!-- KARO_SECTION_START -->` から末尾までを、Step 2で生成した内容で置換
3. Edit toolで更新

### Step 4: ntfy通知

```bash
# 1行サマリを生成してntfy送信
bash scripts/ntfy.sh "📊 Dashboard: {直近cmd結果} | idle:{N}名 | pipeline:{M}件"
```

`scripts/ntfy.sh`はendpoint単位のflock付きグローバルthrottleを持つ。既定では10秒以内の連続送信をskipし、HTTP 429後は60秒cooldownするため、ここで独自retryや連打回避sleepを追加しない。

**重複防止**: `/tmp/last_dashboard_ntfy.txt` に前回送信内容を保存。同一内容ならスキップ。

## 注意事項

- **DASHBOARD_AUTO_START〜DASHBOARD_AUTO_ENDは絶対に触るな**
- データはプライマリYAML（queue/, logs/）から取得。dashboard.mdの既存内容をコピペするな
- 将軍宛報告セクションは**新規報告のみ**。過去に報告済みのINSIGHTは含めない
  - 判定基準: `queue/reports/` に存在する報告のうち、まだdashboard.mdに記載されていないもの
- スキル実行のたびに全セクションを再生成する（差分更新ではなく全置換）
- **KARO_SECTION_ENDマーカーは生成しない**。KARO_SECTIONはファイル末尾まで続く
  - 理由: ENDマーカーがあると「ENDの後に手動追記」が発生し、スキル管轄外にゴミが蓄積する
  - 全てのセクションを固定構成に含め、プライマリデータから自動生成することで手動追記の必要をゼロにする
- 🚨要対応のデータソースはpending_decisions.yaml。status: pendingのみ表示。resolved/archivedは自動除外
- 軍師提案のデータソースは**logs/gunshi_gp_tracker.yaml(SSOT)**。status: karo_sent/pending/proposedのみ。implemented/obsolete等は自動除外。archiveのproposalsは参照禁止（GP ID衝突+凍結status問題。旧LK039はgp_tracker導入により解消）
- **要修正事項のCI状態は手書き禁止**。AUTO_SECTIONから自動取得（Step 1-7）。前回のKARO_SECTIONの記載を引き継ぐな — 毎回プライマリデータから再生成(LK043: cmd_1806事故。KARO_SECTIONの手書きCI赤がCI緑後も残存→前提崩壊cmdを配備)

## 注意ポイント
- 2026-05-04: gate=gate_report_format result=FAIL executor=unknown reason=self_gate_check: is str (must be dict)

- 2026-05-02: gate=gate_report_format result=FAIL executor=unknown reason=knowledge_candidate: is str (must be dict)

Script refs verified: 2026-06-02T20:31:22+09:00 user infra-bug audit. `gate_report_format.sh` の現行契約を再確認。dashboard更新前の報告YAML検証は、binary_checks由来verdict自動導出・lessons_useful空リストBLOCK・中間FAILログ抑止を含む現在のgate出力を正本にする。

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の gate_report_format.sh 差分は c1f2b38d8 のみ(gate_loop_health集計向けログパス正規化=内部ログ記録のみの変更。報告YAMLパス引数・PASS/FAIL判定・verdict自動導出の契約は不変)。

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-12T13:20:00+09:00 -->
