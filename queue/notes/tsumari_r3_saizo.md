# tsumari 第3回 — 領域(b) gate 系（才蔵）

- 抽出窓: `2026-09-03T04:37:00`〜配備時刻 `2026-09-03T11:01:12`（PUBLISHER_SINGLE ON 以後）
- 対象: 領域(b) gate 系のみ。ログの時刻が窓外の行は集計対象外。
- 判定: 窓末尾で `WAIT:report_commit_main_ancestry` が5 cmdに残存し、`cmd_reflux_insight_202609030728_hayate` の terminal RC failure も残るため、未解消条件あり。

## 抽出コマンドと件数（実行結果の生貼付）

### `logs/gate_metrics.log`

```text
$ awk -F '\t' '$1 >= "2026-09-03T04:37:00" && $1 <= "2026-09-03T11:01:12" {print}' logs/gate_metrics.log | wc -l
634
$ awk -F '\t' '$1 >= "2026-09-03T04:37:00" && $1 <= "2026-09-03T11:01:12" {print $3}' logs/gate_metrics.log | sort | uniq -c
      9 BLOCK
     23 CLEAR
      1 INFO
    601 WAIT
$ awk -F '\t' '$1 >= "2026-09-03T04:37:00" && $1 <= "2026-09-03T11:01:12" && $3 == "WAIT" && $4 == "WAIT:report_commit_main_ancestry" {n[$2]++} END {for (c in n) print n[c] "\t" c}' logs/gate_metrics.log | sort -nr | awk '{n++; rows+=$1} END {print "rows=" rows " distinct_cmds=" n}'
rows=587 distinct_cmds=20
終端WAIT cmd:
cmd_karo_ci_fix_33611379072_gate_dual_read_202609021832
cmd_karo_hotfix_ga554_push_overlap_pattern_202609021650
cmd_karo_hotfix_ga555_context_freshness_trigger_202609021730
cmd_karo_hotfix_lesson_feedback_task_identity_202609021922
cmd_karo_hotfix_staged_preserve_index_regression_202609021832
end-state WAIT=5 cmd
```

`logs/gate_metrics.log` の根拠行: `L124,L291,L321,L426,L460,L463,L485,L488,L501,L508,L623,L632,L659,L701,L729,L745`。

### `logs/gate_metrics.jsonl`

```text
$ if [ -e logs/gate_metrics.jsonl ]; then awk 'NF' logs/gate_metrics.jsonl | wc -l; else echo 0; fi
0
$ test -e logs/gate_metrics.jsonl; echo $?
1
```

source は存在せず、0件。探索したコマンドと件数を記録した。

### `queue/gates/*/cmd_complete_gate.trigger.log`

```text
$ find queue/gates -type f -name 'cmd_complete_gate.trigger.log' -print0 | xargs -0 awk '/attempt=[0-9]+ rc=[0-9]+ timestamp=/{ts=substr($0,index($0,"timestamp=")+10,19); if(ts >= "2026-09-03T04:37:00" && ts <= "2026-09-03T11:01:12") n++} END{print n+0}'
22
$ find queue/gates -type f -name 'cmd_complete_gate.trigger.log' -print0 | xargs -0 awk '
{
  buf[++bn]=$0
  if ($0 ~ /attempt=[0-9]+ rc=[0-9]+ timestamp=/) {
    ts=substr($0,index($0,"timestamp=")+10,19)
    if (ts >= "2026-09-03T04:37:00" && ts <= "2026-09-03T11:01:12") {
      files[FILENAME]=1
      for(i=1;i<=bn;i++){if(buf[i] ~ /GATE WAIT/) nwait++; if(buf[i] ~ /GATE BLOCK/) nblock++; if(buf[i] ~ /AUTO_PUSH_WAIT/) naut++}
    }
    delete buf; bn=0
  }
}
END{for(f in files)nfiles++; printf "GATE_WAIT=%d GATE_BLOCK=%d AUTO_PUSH_WAIT=%d files=%d\n",nwait,nblock,naut,nfiles}'
GATE_WAIT=28 GATE_BLOCK=11 AUTO_PUSH_WAIT=14 files=22
$ find queue/gates -type f -name 'cmd_complete_gate.trigger.log' -print0 | xargs -0 awk '/attempt=[0-9]+ rc=[0-9]+ timestamp=/{ts=substr($0,index($0,"timestamp=")+10,19); if(ts >= "2026-09-03T04:37:00" && ts <= "2026-09-03T11:01:12" && /rc=1/) n++} END{print "rc1=" n+0}'
rc1=13
$ find queue/gates -type f -name 'cmd_complete_gate.trigger.log' -print0 | xargs -0 awk '/attempt=[0-9]+ rc=[0-9]+ timestamp=/{ts=substr($0,index($0,"timestamp=")+10,19); if(ts >= "2026-09-03T04:37:00" && ts <= "2026-09-03T11:01:12" && /WARN.*commit\\(s\\) after review/) n++} END{print "stale_review_warn=" n+0}'
stale_review_warn=3
```

trigger 根拠行: `cmd_4468/cmd_complete_gate.trigger.log:L321`、`cmd_reflux_insight_202609030920_hayate/cmd_complete_gate.trigger.log:L325`、`cmd_reflux_insight_202609031014_kotaro/cmd_complete_gate.trigger.log:L312`。各 BLOCK/WAIT 行は各 attempt ブロックに含まれるため、上記 awk で attempt 時刻を境界にして集計した。

### `logs/gunshi_review_log.yaml` と SG-PRE 出力

```text
$ rg -n 'SG-PRE[0-9]+ ERROR|ERROR.*SG-PRE[0-9]+' logs/gunshi_review_log.yaml | wc -l
1
$ rg -n 'SG-PRE[0-9]+ ERROR|ERROR.*SG-PRE[0-9]+' logs/gunshi_review_log.yaml
1152:  - root worktreeにファイル不在(worktree内commitのため)→SG-PRE35 ERROR→review_bundle停止
$ find logs -maxdepth 1 -type f \( -iname '*precheck*' -o -iname 'gate_gunshi_report_precheck*' \) -print | wc -l
0
```

`logs/gunshi_review_log.yaml:L1152` の entry は `2026-09-03T10:07:00+09:00` の review。別ファイルの SG-PRE 出力は0件。後続の `logs/gunshi_review_log.yaml:L1552` では `result: PASS` を確認した。

### `queue/gates/*/single_review_terminal.json`

ディレクトリ名の `20260903HHMM` を時刻境界として抽出した。

```text
$ find queue/gates -type f -name single_review_terminal.json | awk -F/ '{d=$(NF-1); if (match(d,/20260903[0-9][0-9][0-9][0-9]/)) {t=substr(d,RSTART+8,4); if (t >= "0437" && t <= "1101") print $0}}' | tee /tmp/saizo_terminal_window_paths.txt | wc -l
19
$ while IFS= read -r f; do jq -r '.status // "missing"' "$f"; done < /tmp/saizo_terminal_window_paths.txt | sort | uniq -c
      2 failure
     17 success
$ jq -r '.error // empty' queue/gates/cmd_reflux_insight_202609030627_kotaro/single_review_terminal.json
report identity is not in the canonical report registry
$ jq -r '.error // empty' queue/gates/cmd_reflux_insight_202609030728_hayate/single_review_terminal.json
autogen spec fallback requires completed/PASS or completed/PASS_NO_IMPROVEMENT report
```

RC 根拠: `queue/gates/cmd_reflux_insight_202609030627_kotaro/single_review_terminal.json:2`、`queue/gates/cmd_reflux_insight_202609030728_hayate/single_review_terminal.json:2`。JSONにはRC理由を含む failure 2件があり、success 17件だった。

## 事例表

| ID | 時刻 | 事象 | 主分類 | 副分類 | 真因（ログ記載） | 根治済/未根治 | 次の一手 | 根拠（file:line） |
|---|---|---|---|---|---|---|---|---|
| T3-saizo-01 | 04:40:39〜11:01:05 | `WAIT:report_commit_main_ancestry` 587回、20 cmd。同一理由の再GATEが継続し、窓末尾で5 cmdがWAIT | 循環拘束 | PUBLISHER_SINGLE publication待ち | report commit が remote ancestry に含まれず、gate push は `publisher_request`/`source_publication_failed` で待機 | 未根治 | 5 cmdのpublisher publication完了または失敗理由を一次確認し、同一cmdを再GATEする | `logs/gate_metrics.log:L124,L745` |
| T3-saizo-02 | 04:40:39〜10:43:09 | CI readiness WAIT 13回、12 cmd。`run_pending`、`workflow_no_verdict`、`run_predates_review` | 遅い script・test | CI評価未到着 | CI評価が待機中またはverdict不在。ログは「GATEは止めない」と記録 | 根治済/解消 | 後追いCI verdictを確認し、pending/no-verdictを新規待機原因として残さない | `logs/gate_metrics.log:L124,L291,L344,L729` |
| T3-saizo-03 | 05:54:37〜07:55:44 | report_format BLOCK 5回、fallback_gate_status BLOCK 3回。cmd_4465、publisher_root_drain、task_worktree_reclaimで発生 | 過剰 BLOCK | 報告形式・fallback判定 | `report_format:<report>` または `fallback_gate_status:lesson:PASS|review_gate:PASS` がBLOCK理由として記録 | 根治済/解消 | 各reportの再発時は `gate_report_format` の具体的FAILフィールドを一次確認してから再提出する | `logs/gate_metrics.log:L321,L426,L460,L463,L485,L488,L501,L508` |
| T3-saizo-04 | 05:54:37、09:25:20 | `review_two_phase_pending` 2回。1回はreport_format理由と併記 | 循環拘束 | 二段階review待ち | gate_metrics が `WAIT:review_two_phase_pending` を記録 | 根治済/解消 | 二段階reviewの完了receiptを確認してから再GATEする | `logs/gate_metrics.log:L321,L632` |
| T3-saizo-05 | 09:17:14 | `sg7_bundle_missing_or_invalid` 1回。後続09:33:38に同cmdがCLEAR | 過剰 BLOCK | SG7成果物不在/不正 | gate_metrics にSG7 bundle missing/invalidが記録 | 根治済/解消 | bundle存在と内容を確認し、missing時は生成完了後に一度だけ再GATEする | `logs/gate_metrics.log:L623,L644` |
| T3-saizo-06 | 06:39付近 | terminal RC failure: `report identity is not in the canonical report registry` | 影響範囲・依存未解明の浅い対応 | report registry依存 | terminal JSONのerror欄にcanonical report registry不在が記録 | 根治済/解消 | registry登録状態とreport identityを突合し、再レビュー時に同一identityを使用する | `queue/gates/cmd_reflux_insight_202609030627_kotaro/single_review_terminal.json:2` |
| T3-saizo-07 | 07:28付近 | terminal RC failure: `autogen spec fallback requires completed/PASS or completed/PASS_NO_IMPROVEMENT report` | 影響範囲・依存未解明の浅い対応 | autogen fallbackの前提 | terminal JSONのerror欄がcompleted/PASS系reportを要求 | 未根治 | 対象reportのstatus/verdictを一次確認し、要件を満たすreportを生成してから再実行する | `queue/gates/cmd_reflux_insight_202609030728_hayate/single_review_terminal.json:2` |
| T3-saizo-08 | 10:07:00 | root worktreeにtest file不在としてSG-PRE35 ERROR、review_bundle停止 | 構造バグ | commit内存在とroot worktree存在の不一致 | review logが「worktree内commitのため」と記録。後続entryでPASSを確認 | 根治済/解消 | commitとroot worktreeの双方を確認するSG-PRE35証跡を維持する | `logs/gunshi_review_log.yaml:L1152,L1552` |
| T3-saizo-09 | 09:42:50 | `production_proof=FAIL reason=predicate_mismatch` INFO。cmd_4468は10:18:40にCLEAR | 構造バグ | production proof predicate | gate_metrics がpredicate_mismatchを記録 | 根治済/解消 | predicate各項目の実測値と期待値を同じrunで再計数する | `logs/gate_metrics.log:L659,L701` |
| T3-saizo-10 | 09:44、09:44、10:42 | trigger logの「commit(s) after review」WARNが3回。同型が複数cmdで再発 | 影響範囲・依存未解明の浅い対応 | review時点とcommit時点の競合 | trigger logがreview後commitを1件としてWARN | 未根治 | review receipt後のcommit経路を特定し、同一commitを含む再レビュー境界を一次確認する | `queue/gates/cmd_4468/cmd_complete_gate.trigger.log:L321`; `queue/gates/cmd_reflux_insight_202609030920_hayate/cmd_complete_gate.trigger.log:L325`; `queue/gates/cmd_reflux_insight_202609031014_kotaro/cmd_complete_gate.trigger.log:L312` |

## 集計

### 主分類別（事例数）

| 主分類 | 件数 |
|---|---:|
| 偽陽性 | 0 |
| 過剰 BLOCK | 2 |
| 構造バグ | 2 |
| 循環拘束 | 2 |
| 遅い script・test | 1 |
| Claude↔Codex 仕組み差 | 0 |
| サンクコスト過剰複雑化 | 0 |
| 影響範囲・依存未解明の浅い対応 | 3 |
| **合計** | **10** |

### 根治状態

| 状態 | 事例数 |
|---|---:|
| 根治済/解消 | 7 |
| 未根治 | 3 |
| **合計** | **10** |

未根治は T3-saizo-01（窓末尾5 cmdの ancestry WAIT）、T3-saizo-07（terminal RC failure）、T3-saizo-10（同型WARN 3回再発）。各事例のlog行引用は表の根拠欄および抽出結果に含めた。推測語は使用していない。
