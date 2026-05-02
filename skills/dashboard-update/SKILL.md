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
allowed-tools:
  - Bash
  - Read
  - Edit
  - Glob
  - Grep
---

# /dashboard-update — KARO_SECTION自動生成

## 概要

dashboard.mdの `<!-- KARO_SECTION_START -->` 〜 末尾を、プライマリYAMLデータから自動生成する。
手動編集を排除し、構成を固定化する。

## 実行手順

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

