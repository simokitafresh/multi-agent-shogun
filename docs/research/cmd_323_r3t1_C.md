# cmd_complete_gate.sh 仕様調査報告

- **cmd**: cmd_323 R3-Task1
- **blind_id**: C
- **対象**: `scripts/cmd_complete_gate.sh` (880行)
- **調査日**: 2026-02-25

---

## 1. 全体処理フロー

### 入力
- **引数**: `<cmd_id>` (必須、`cmd_XXX`形式)
- **暗黙の入力ファイル**:
  - `queue/shogun_to_karo.yaml` — cmd定義(purpose, project, status)
  - `queue/tasks/*.yaml` — 各忍者のタスクYAML(parent_cmd, task_type, related_lessons)
  - `queue/reports/*_report.yaml` — 忍者の報告YAML
  - `queue/gates/{cmd_id}/` — ゲートフラグディレクトリ
  - `config/projects.yaml` — プロジェクト設定
  - `queue/pending_decisions.yaml` — 未決裁定
  - `queue/inbox/karo.yaml` — 家老のinbox

### 処理パイプライン(順序)

```
1. 引数バリデーション (L12-23)
2. ディレクトリ・変数初期化 (L25-30)
3. auto_draft_lesson: 忍者報告からlesson_candidate自動draft登録 (L150-169)
4. 緊急override確認 — emergency.overrideファイル存在 → 即CLEAR (L172-187)
5. ゲートフラグ(.done)チェック — archive, lesson + 条件付き(report_merge, review_gate) (L190-217)
6. related_lessons注入チェック (L219-253)
7. lesson_referenced検証 (L255-329)
8. reviewed:false残存チェック (L331-369)
9. lesson_candidate検証 (L371-458)
10. skill_candidate検証 — WARNのみ (L460-521)
11. decision_candidate検証 — WARNのみ (L523-584)
12. draft教訓存在チェック — BLOCKする (L586-628)
13. inbox_archive強制チェック — WARNのみ、実行もする (L630-650)
14. 未反映PD検出 — WARNのみ (L652-680)
15. 調査恒久化チェック(穴4) — WARNのみ (L682-730)
16. 判定: ALL_CLEAR → GATE CLEAR / GATE BLOCK (L732-879)
```

### 出力・副作用

| 条件 | Exit Code | 副作用 |
|------|-----------|--------|
| GATE CLEAR | 0 | (a) gate_yaml_status.sh実行 (b) update_status()でYAML更新 (c) append_changelog() (d) lesson_score helpful+1 (e) ntfy通知なし |
| GATE CLEAR (override) | 0 | (a)-(c)同上 + ntfy通知あり |
| GATE BLOCK | 1 | (a) gate_metrics.logにBLOCK記録 (b) 自動draft教訓生成(最大3パターン) |
| 全パス共通 | - | (a) auto_draft_lesson.sh実行 (b) stdout出力(各チェック結果) (c) gate_metrics.log追記 |

---

## 2. 全関数一覧

| # | 関数名 | 行 | 入力 | 出力 | 呼出元 |
|---|--------|-----|------|------|--------|
| 1 | `update_status()` | L33-49 | `cmd_id` | stdout(STATUS UPDATED/ALREADY) | GATE CLEAR時(L184,L743) |
| 2 | `append_changelog()` | L52-101 | `cmd_id` | changelog追記+stdout | GATE CLEAR時(L185,L744) |
| 3 | `detect_task_types()` | L104-124 | `cmd_id` | stdout(`true/false true/false`) | メイン(L138) |
| 4 | `record_block_reason()` | L127-132 | `reason`文字列 | グローバル配列`BLOCK_REASONS`に追記 | 各チェックセクション |

### 依存外部スクリプト

| スクリプト | 呼出行 | ブロック性 |
|-----------|--------|-----------|
| `scripts/auto_draft_lesson.sh` | L160 | non-blocking(失敗時WARN) |
| `scripts/gates/gate_yaml_status.sh` | L179, L738 | non-blocking(失敗時WARN) |
| `scripts/ntfy.sh` | L177 | override時のみ |
| `scripts/inbox_archive.sh` | L640 | non-blocking(WARNのみ) |
| `scripts/lesson_write.sh` | L824,L839,L862 | BLOCK時draft生成 |
| `scripts/lesson_update_score.sh` | L778 | CLEAR時ベストエフォート |

---

## 3. ゲート判定ロジック

### 3.1 必須ゲート(ALWAYS_REQUIRED)

| ゲート | .doneファイル | BLOCK条件 |
|--------|-------------|-----------|
| `archive` | `queue/gates/{cmd}/archive.done` | ファイル不在 |
| `lesson` | `queue/gates/{cmd}/lesson.done` | ファイル不在 |

### 3.2 条件付きゲート(CONDITIONAL)

| ゲート | 発動条件 | .doneファイル |
|--------|---------|-------------|
| `report_merge` | タスクYAMLに`task_type: recon`あり | `queue/gates/{cmd}/report_merge.done` |
| `review_gate` | タスクYAMLに`task_type: implement`あり | `queue/gates/{cmd}/review_gate.done` |

task_type検出: `queue/tasks/*.yaml`を全走査し、`parent_cmd: {cmd_id}`一致かつ`task_type: recon/implement`を検出。

### 3.3 ブロッキングチェック(.doneファイル以外)

| チェック | 行 | BLOCK条件 |
|---------|-----|-----------|
| lesson_referenced | L255-329 | related_lessonsあり & 報告にlesson_referenced空/欠落 |
| reviewed:false残存 | L331-369 | タスクYAMLのrelated_lessonsにreviewed:false残存 |
| lesson_candidate | L371-458 | found:trueだがlesson.doneのsource≠lesson_write / lesson.done不在 / フィールド欠落 / 構造不正 |
| draft教訓存在 | L586-628 | プロジェクトのlessons.mdにstatus: draftが1件以上 |

### 3.4 非ブロッキングチェック(WARNのみ)

| チェック | 行 | 出力 |
|---------|-----|------|
| skill_candidate | L460-521 | foundキー欠落等のWARN |
| decision_candidate | L523-584 | foundキー欠落等のWARN |
| inbox_archive | L630-650 | karo既読10件以上で自動archive実行 |
| 未反映PD | L652-680 | resolved但しcontext_synced=FalseのPD |
| 穴4: 調査恒久化 | L682-730 | recon系cmdでcontext/projects変更なし |

### 3.5 緊急override

`queue/gates/{cmd}/emergency.override` ファイル存在 → 全チェックスキップ → 即GATE CLEAR (exit 0)。ntfyで通知。

---

## 4. YAML操作方式

### 4.1 awk/sed方式(シェルネイティブ)

| 箇所 | 行 | パターン | 懸念(L034関連) |
|------|-----|---------|---------------|
| `update_status()` sed読取 | L40 | `sed -n "/^  - id: ${cmd_id}$/,/^  - id: /p"` + `grep "^    status: completed"` | **4spaceインデント固定**。`^    status:`は先頭4space決め打ち |
| `update_status()` sed書換 | L45 | `sed -i "/^  - id: ${cmd_id}$/,/^  - id: /{s/    status: pending/    status: completed/}"` | **4space固定**。インデント変動に脆弱(L034教訓そのもの) |
| `append_changelog()` purpose抽出 | L60-64 | awk: `/^[ ]*- id:/`→`/^[ ]*purpose:/` | **柔軟マッチ**(`[ ]*`)。update_statusとは対照的に堅牢 |
| `append_changelog()` project抽出 | L67-71 | awk: 同上 | 柔軟マッチ |
| `CMD_PROJECT` 抽出 | L590-594 | awk: 同上 | 柔軟マッチ |
| `CMD_PURPOSE` 抽出 | L686-690 | awk: 同上 | 柔軟マッチ |

### 4.2 Python yaml.safe_load方式

以下のチェックで使用(全てインラインpython3 -c):
- related_lessons有無 (L232-241, L266-276)
- lesson_referenced検証 (L285-300)
- related_lessons ID抽出 (L306-317)
- reviewed:false検出 (L341-355)
- lesson_candidate検証 (L392-415)
- skill_candidate検証 (L480-499)
- decision_candidate検証 (L543-562)
- unsynced PD検出 (L657-669)
- projects.yaml パス取得 (L598-606)
- lesson_referenced ID抽出 (L759-775)

### 4.3 grep/head方式

| 箇所 | 行 | パターン |
|------|-----|---------|
| parent_cmd一致 | L112,154,225,261,337,377,466,529,753 | `grep -q "parent_cmd: ${CMD_ID}"` |
| task_type抽出 | L114 | `grep 'task_type:'` + `sed` + `tr` |
| entry_count | L94 | `grep -c '^  - id:'` |
| draft_count | L611 | `grep -c '^\- \*\*status\*\*: draft'` — lessons.md(マークダウン)のパース |
| read_count | L635 | `grep -c 'read: true'` |
| lesson.done source | L425 | `grep '^source:'` + `sed` |

---

## 5. エッジケース

### EC-1: update_status()の4space固定インデント依存 (L40, L45)

**重大度**: HIGH

`update_status()`のsedパターンは`^    status:`(4space)に固定依存している。shogun_to_karo.yamlのインデントが2spaceや0spaceに変動した場合(L034教訓で実証済み)、status更新が空振りする。

一方、同ファイル内のappend_changelog()やCMD_PROJECT抽出のawkパターンは`/^[ ]*/`で柔軟マッチしており、**同一ファイル内でインデント対応が不統一**。

**影響**: GATE CLEARなのにYAML statusがpendingのまま残る → 後続処理(家老のダッシュボード判定等)で完了未検知。

### EC-2: parent_cmd部分一致問題 (L112等)

**重大度**: MEDIUM

`grep -q "parent_cmd: ${CMD_ID}"` はsubstring matchなので、`cmd_1`がcmd_10, cmd_100, cmd_1234等にも一致する。
例: `cmd_3` を指定すると `parent_cmd: cmd_300` も拾う。

全9箇所(L112,154,225,261,337,377,466,529,753)で同一パターン使用。

**影響**: 短いcmd_id指定時に無関係なタスクのreport/lessonを巻き込む。

### EC-3: Python -c内でのシェル変数直接展開 (L233-240等)

**重大度**: MEDIUM (L047教訓関連)

`python3 -c` 内で `$task_file`, `$report_file`, `$PD_FILE` などをシェル変数として直接展開している。ファイルパスにシングルクォートが含まれるとPythonコード実行可能(injection)。

タスクYAMLやレポートYAMLのパスはスクリプトが管理するパスなので実用上のリスクは低いが、防御的プログラミングの観点からは`os.environ`経由が望ましい。

影響箇所: L233, L267, L286, L307, L342, L393, L481, L544, L598, L657, L760 (計11箇所)

### EC-4: changelog剪定の行数固定前提 (L96-98)

**重大度**: LOW

```bash
{ head -1 "$changelog"; tail -n 80 "$changelog"; } > "${changelog}.tmp"
```

エントリが4行固定(id/project/purpose/completed_at)を前提にtail -n 80(=20エントリ分)で切り取る。purposeに改行が含まれた場合やフォーマット変更でエントリ行数が変わった場合、切断されたYAMLが生成される。

### EC-5: detect_task_types()が全タスクファイルを走査 (L109-120)

**重大度**: LOW

`$TASKS_DIR/*.yaml`の全ファイルを走査する。完了済みタスクが残っていると、過去のcmdと同一忍者に再配備されたケースで意図しないtask_type検出が起こりうる。ただし通常はdeploy_task.shがタスクファイルを上書きするため発生頻度は低い。

### EC-6: grep -cの0件時挙動 (L94, L611, L635)

**重大度**: LOW (L019教訓関連)

L94: `grep -c '^  - id:' "$changelog" 2>/dev/null || echo 0` — grep -cは0件時も'0'出力+exit 1。`|| echo 0`で'0\n0'になるリスク(L019教訓)。ただしL94は変数代入`$(...)`なので改行が除去され**実害なし**。

L611: `grep -c '...' "$DRAFT_LESSONS_FILE" 2>/dev/null || true` — `|| true`は正しい処理。0件時grep -cの'0'出力のみ。

L635: 同上パターン。

---

## 6. 改善提案

### 提案1: update_status()のインデント柔軟化 (L40, L45)

**現状** (L40):
```bash
sed -n "/^  - id: ${cmd_id}$/,/^  - id: /p" "$YAML_FILE" | grep -q "^    status: completed"
```

**提案**: append_changelog()と同様のawk方式に統一。または`[ ]*`で柔軟マッチに変更。

```bash
# 案A: sedパターンを柔軟化
sed -n "/^[ ]*- id: ${cmd_id}$/,/^[ ]*- id: /p" "$YAML_FILE" | grep -q "^[ ]*status: completed"

# L45も同様に
sed -i "/^[ ]*- id: ${cmd_id}$/,/^[ ]*- id: /{s/^([ ]*)status: pending/\1status: completed/}" "$YAML_FILE"
```

```bash
# 案B: Python yaml.safe_load + yaml.dump に統一(堅牢だが重い)
python3 -c "
import yaml, os
f = os.environ['YAML_FILE']
cmd = os.environ['CMD_ID']
with open(f) as fh:
    data = yaml.safe_load(fh)
# ... status更新 ...
"
```

**推奨**: 案A。最小変更でL034教訓を解消。

### 提案2: parent_cmd一致の完全マッチ化 (L112等, 全9箇所)

**現状** (L112):
```bash
grep -q "parent_cmd: ${CMD_ID}" "$task_file"
```

**提案**: 行末アンカーまたはword boundary追加。

```bash
# 案A: 行末アンカー追加
grep -q "parent_cmd: ${CMD_ID}$" "$task_file"

# 案B: より厳密なパターン
grep -qE "parent_cmd:\s+${CMD_ID}\s*$" "$task_file"
```

全9箇所: L112, L154, L225, L261, L337, L377, L466, L529, L753

**推奨**: 案A。`$`追加のみの最小変更。

### 提案3: Python -c内のシェル変数展開をos.environ経由に (L233等, 11箇所)

**現状** (L232-241):
```bash
has_rl_key=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
```

**提案**: 環境変数経由でパスを渡す。

```bash
has_rl_key=$(TASK_FILE="$task_file" python3 -c "
import yaml, sys, os
try:
    with open(os.environ['TASK_FILE']) as f:
```

改修コスト大(11箇所)だが、L047教訓と一致する防御的改善。

---

## 7. 補足: フロー図(テキスト)

```
                         cmd_complete_gate.sh <cmd_id>
                                |
                    [引数バリデーション]
                                |
                    [auto_draft_lesson実行]
                                |
                [emergency.override存在?]─YES─→ GATE CLEAR (exit 0)
                                |NO
                    [.doneフラグチェック]
                    archive / lesson
                    + report_merge (if recon)
                    + review_gate (if implement)
                                |
                [ブロッキングチェック群]
                ├─ lesson_referenced
                ├─ reviewed:false残存
                ├─ lesson_candidate整合性
                └─ draft教訓存在
                                |
                [非ブロッキングWARN群]
                ├─ skill_candidate
                ├─ decision_candidate
                ├─ inbox_archive
                ├─ 未反映PD
                └─ 穴4: 調査恒久化
                                |
                    [ALL_CLEAR?]
                   /            \
                YES              NO
                 |                |
          GATE CLEAR         GATE BLOCK
          exit 0             exit 1
          (status更新,       (metrics記録,
           changelog,         auto-draft教訓)
           lesson score)
```

---

## 8. 教訓参照

本調査で以下の教訓を直接確認・活用した:

| 教訓 | 調査での適用 |
|------|-------------|
| L034 | EC-1で`update_status()`の4space固定依存を特定。提案1の根拠 |
| L010 | `^status:`先頭マッチの重要性。L40の`grep "^    status: completed"`は先頭マッチだが4space固定 |
| L001 | 成果物作成前にRead実施を遵守 |
| L009/L007 | 本タスクではファイル作成のみのため直接的影響なし。認識済み |
