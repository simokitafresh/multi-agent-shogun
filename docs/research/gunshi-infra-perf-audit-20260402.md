# Infrastructure Performance Audit — 2026-04-02

cmd: 殿直接指示。hook/script/testの最適化・高速化の未着手領域を調査。
auditor: gunshi
scope: scripts/, hooks/, tests/, gates/

---

## §1 Scripts — Python subprocess残存（最大ボトルネック）

### §1.1 deploy_task.sh（3,184行、毎配備実行）

**問題**: yaml.safe_load()が7箇所残存（L190-210, L226-260, L437-500, L713-800）
- 7個のPython processが毎deploy発生
- 各yaml.safe_load: ~50-150ms on WSL2
- **推定コスト**: 350-1050ms/deploy

**対策**: field_get.sh / awk方式でYAMLフィールド抽出に置換。inbox_mark_read.shの28%削減と同じ手法。

**優先度**: P1（最頻実行スクリプト×最多Python呼出）

### §1.2 archive_completed.sh（1,432行）

**問題**: L77-100 get_report_summary_for_cmd()内でPython glob+yaml.safe_loadをループ内使用
- cmd_idごとにPython起動+globbing+YAML parsing
- **推定コスト**: 200-300ms/cmd

**対策**: bash globbing + field_get.shに置換。

**優先度**: P2（毎archive cycle実行）

### §1.3 cmd_complete_gate.sh（4,001行）

**問題**: grep -A5 | grep -q の二重grepパターンが4箇所（L1417, L2585, L2907, L2954）
- lesson_candidate/skill_candidate/decision_candidate のfound:チェック
- 2 grepプロセス × 4箇所 = 8プロセス/cmd
- ループ内で毎回ファイルを再オープン

**対策**: 単一awk passで全候補を一括チェック。
```bash
# 現行（L1417）:
grep -A5 'lesson_candidate:' "$rfile" | grep -q 'found: true'
# 最適化案:
awk '/^lesson_candidate:/{p=1} p&&/found: true/{exit 0} /^[^ ]/{if(p)exit 1}' "$rfile"
```

**優先度**: P2（毎cmd完了時実行）

---

## §2 Hooks — 重複実行と不要Python起動

### §2.1 pre-bash二重発火

**問題**: PreToolUse Bash hookがproject(.claude/settings.json L12-18)とuser(~/.claude/settings.json L50-56)の両方で発火
- 毎Bash呼出で~120ms重複

**対策**: user-level hookをproject-levelに統合、または条件分岐で重複排除。

**優先度**: P2（全Bash操作に影響）

### §2.2 pre-bash-combined.sh Python guard（L85-240）

**問題**: git/rm/chmod等のキーワード検出時にPython subprocess起動（~100-150ms）
- 80%のケースはpure bashで判定可能（単純な文字列マッチ）

**対策**: bash前段フィルタで明確なケースを即判定。Python起動はエッジケースのみ。

**優先度**: P3（影響は50 bash calls × 120ms ≈ 6s/session）

### §2.3 post-search-completeness-guard.sh

**問題**: 全Grep/Glob呼出で無条件出力（L12）。コメントに「only show if results」とあるが未実装。
- session中100+行のノイズ

**対策**: 結果件数チェックを追加。0件時のみ警告出力。

**優先度**: P3（機能的影響は低い、ノイズ除去）

### §2.4 PostToolUse状況

**過去の最大ギャップ（PostToolUse Hook未導入）は完全解消済み**。
- Project: Bash(test parser+commit reminder), Grep|Glob(search guard), Write|Edit(shellcheck+instruction consistency)
- User: Bash(state restoration)

---

## §3 Tests — OOM根因 + gate冗長読み

### §3.1 bats OOM根因（4.3GB → テスト全量実行不能）

**問題**: tests/helpers/deploy_task_scaffold.bash L92-94
```bash
deploy_task_teardown() {
    :  # 空のno-op — 何も削除しない
}
```
- 8テストファイル × ~31テスト = 310+ tmpディレクトリが未削除で蓄積
- 各tmpdir: ~50MB → 合計 ~3,900MB+

**対策**: teardown関数にcleanup追加。
```bash
deploy_task_teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}
```
+ teardown_file()にDEPLOY_TASK_TEMPLATE_DIR cleanup追加。

**優先度**: P1（1行修正でOOM解消→全量テスト復活）

### §3.2 gate_gunshi_report_precheck.sh（246行）

**問題**: 13個の個別python3 -c呼出（L34-221）
- 同一REPORT_PATH+TASK_FILEを5回以上読み直し
- **推定コスト**: 13 × 30ms = 390ms/report。100報告で39秒浪費

**対策**: 13個のPythonブロックを1つのPythonスクリプトに統合。ファイル読込を1回に。

**優先度**: P2（レビューパイプラインのホットパス）

### §3.3 startup gate間の重複ファイル読み

**問題**: shogun/karo/gunshi の3 startup gateが同一ファイル（karo_workarounds.yaml等）を各自で読む
- gate_shogun_startup.sh: 43 grep/cat操作
- gate_karo_startup.sh: 14 grep/cat操作
- gate_gunshi_startup.sh: 11 grep/cat操作
- 合計68 file operations

**対策**: 共有ファイルを1回読み込んでtmpにキャッシュ、各gateはキャッシュから読む。
またはstartup gate内でsub-gateを呼ぶ際にファイル内容をパイプで渡す。

**優先度**: P3（起動時のみ。体感への影響小）

---

## §4 優先度サマリ

| P | 対象 | 手法 | 推定効果 | 頻度 |
|---|------|------|---------|------|
| **P1** | deploy_task.sh Python除去 | yaml.safe_load→awk/field_get.sh | 40-60%高速化 | 毎配備 |
| **P1** | bats teardown修正 | 1行cleanup追加 | OOM解消→全量テスト復活 | 毎テスト |
| P2 | archive_completed.sh | Python→bash glob | 50-70%高速化 | 毎archive |
| P2 | cmd_complete_gate.sh | 二重grep→awk | 30-40%高速化 | 毎cmd完了 |
| P2 | gate_gunshi_report_precheck.sh | 13 Python→1統合 | 90%削減 | 毎報告 |
| P2 | pre-bash二重発火 | hook統合 | 120ms/bash削除 | 全bash |
| P3 | pre-bash Python guard | bash前段フィルタ | 80%のケースで100ms削減 | keyword match時 |
| P3 | search guard | 条件分岐追加 | ノイズ除去 | 全search |
| P3 | startup gate重複読み | キャッシュ共有 | 68→~25 ops | 起動時のみ |

---

## §5 原則との整合

- **機械的部分は効率化→浮いた時間を判断に回す**（殿の基本方針）
- deploy_task.sh高速化 = 毎配備で全エージェントが恩恵。+1点の複利が最大
- bats OOM修正 = テスト基盤復活。全量テストが回ることでregression検知能力回復
- inbox_mark_read.sh(28%削減)の実績が全対策の手法テンプレート
