---
name: cmd-complete
argument-hint: "[cmd_id]"
user-invocable: false
description: |
  【家老専用】cmd GATE CLEAR後の完了処理を1コマンドで実行するスキル。
  lesson review→cmd_complete_gate→品質記録→status completed→archive→dashboard→ntfyの全ステップを順序保証で実行。
  TRIGGER: /cmd-complete、GATE CLEAR後処理、cmd完了処理
  DO NOT TRIGGER: dashboard単独更新（→/dashboard-update）、lesson-sort（→将軍スキル）、cmd起票（→将軍）
quality_metric: "当該スキルで完了処理したcmdのcmd_complete_gate.sh初回CLEAR率（logs/gate_metrics.logでCLEAR/BLOCKを集計）"
---

# /cmd-complete — cmd完了処理スキル

GATE CLEAR後の5-7ステップを順序保証で1コマンド実行。ステップ抜け=ゼロ。

## 引数

`/cmd-complete <cmd_id>` — 完了処理するcmd IDを指定

## 実行フロー（順序厳守）

### SG7バンドルを完了処理の単一情報源にする

軍師LGTM済みのcmdは、軍師から届いたSG7バンドルの `cmd_spec_summary` を起点にする。
まず `python3 scripts/review_bundle.py consume --cmd "$CMD_ID" --bundle "$BUNDLE_PATH" --expect-verdict APPROVE`
を実行し、exit 0で出力された実値だけを使う。exit 2は必須値欠落・cmd/verdict矛盾なので即停止する。
`acceptance_criteria_count`・`scope`・`project` を完了スタンプ/GATE入力として使い、
忍者の報告YAML全文と `queue/shogun_to_karo.yaml` のcmd specを再Readしてはならない。
例外はSG7 verdict=FAIL、`karo_attention` あり、またはsummaryの必須3値が欠落/矛盾した場合のみ。
その場合はfail-closedで停止し、バンドルの要点から必要箇所だけを一次確認する。


### 自動防止ステップ
- <!-- skill-auto-improve:407f5d0b9905 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「draft_lessons:1」(count=1, last=2026-05-05T09:25:12+0900)を避ける。確認: 関連教訓ごとに lessons_useful の id/useful/reason が埋まっていることを確認する。修正: UNKNOWN/null/FILL_THISを使わず、各教訓の有用性と理由を記入する。
- <!-- skill-auto-improve:bf42976b4e85 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「missing_gate:lesson|hanzo:lesson_done_missing」(cmd_2686以降WARN化済み)。lesson.doneはdeploy_task.shのpreflight_gate_flags()が自動生成する(found:trueなしならlesson_check.sh経由)。忍者は何もしなくてよい。
- <!-- skill-auto-improve:38f7fb84d163 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「missing_gate:lesson|<ninja>:lesson_done_missing」(cmd_2686以降WARN化済み)。BLOCKしない設計。lesson.doneはpreflight_gate_flags()が自動生成。手動対処不要。
- <!-- skill-auto-improve:cmd_2944 --> 自動防止: ac_version_mismatch(task=d41d8cd9)。ac_versionはACのdescription/check文字列のmd5(deploy_task.sh _compute_ac_hash)。gitハッシュ(git rev-parse --short HEAD)ではない。karo_direct配備のtask.ac_versionとreport.ac_version_readはdeploy_task.shが自動で一致させる。手動でgit hashを書き込むことは禁止。
- <!-- skill-auto-improve:75c5317166e9 --> 自動防止: gate=cmd_complete_gate のTop FAIL理由「<ninja>:ac_version_mismatch:task=d41d8cd9:report=88572c76」(count=1, last=2026-05-02T23:46:44+0900)を避ける。確認: ac_version_read がHEADの短縮ハッシュと一致するか `git rev-parse --short HEAD` で確認する。修正: `report_field_set.sh <report> ac_version_read $(git rev-parse --short HEAD)` で記入する。
### Step 1: lesson review
```bash
bash scripts/lesson_review.sh <project_id>
```
`lesson_review.sh` はproject ID必須。対象cmdの `project:` を正本にする
（例: `project: dm-signal` → `bash scripts/lesson_review.sh dm-signal`、
`project: infra` → `bash scripts/lesson_review.sh infra`）。引数なし実行は禁止。
draft教訓レビューを必ず実行する。draft=0ならスキップしてStep 2へ進む。
draft>0なら全件confirm/edit/deleteで完了させるまでStep 2以降へ進むな。
lesson_review完了前にcmd_complete_gateを実行することは禁止。

### Step 2: workaroundログ（該当時のみ）
cmd処理中にworkaround（忍者報告の手動修正等）があった場合:
```bash
bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
```
なければスキップ。

### Step 3: cmd_complete_gate
```bash
bash scripts/cmd_complete_gate.sh <cmd_id>
```
GATE CLEAR → Step 3.5へ。BLOCK → 停止。BLOCK理由を報告。

### Step 3.5: context鮮度チェック（GA-038防御層A・殿裁定2026-06-10）
```bash
bash scripts/gates/gate_context_freshness.sh
```
研究系cmd（research/分析/検証系）の完了時にcontext索引の鮮度劣化を検出する。
- ALERT/WARNが出たら: 当該cmdの結果が対象context（例: `context/dm-signal-research.md`）に
  反映済みか確認し、未反映なら索引層スタイル（結論1-2行+参照先）で追記+last_updated更新
- OK → Step 4へ。BLOCKしない（WARN表示のみ）
- 理由: cmd-complete Step1-8にcontext更新ステップが構造的に欠落しており、
  研究系cmd完了後にcontextが停滞する（GA-038実例: 研究3件が12日未反映。L771）

### Step 4: cmd品質記録
```bash
bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>
```

### Step 5: status → completed
```bash
bash scripts/gates/gate_yaml_status.sh <cmd_id>
```
`cmd_complete_gate.sh` が既にactive queueからarchive済みにしたcmdは `gate_yaml_status.sh` が
`not found` を返すことがある。その場合は `rg <cmd_id> archive queue dashboard.md logs/gate_metrics.log`
でarchive/dashboard/gate_metrics上のCLEARを確認し、status更新は不要としてStep 6へ進む。

### Step 6: dashboard更新
[[dashboard-update]] スキルを実行。

### Step 7: ntfy送信
```bash
bash scripts/ntfy_cmd.sh <cmd_id> "完了"
```

### Step 8: inbox archive
```bash
bash scripts/inbox_archive.sh karo
```

## BLOCK時の手順
- Step 3でBLOCK → BLOCK理由を確認し修正。修正後Step 3から再実行
- 新しいinbox nudgeが来ても上記Step 1-8を先に完了する（CTX膨張防止）

## 制約
- archive_completed.shはGATE CLEAR時に自動実行されるため手動不要
- 順序を崩すな（§8ルール）

## 注意ポイント
- 2026-05-11: gate=cmd_complete_gate result=FAIL executor=hayate reason=missing_gate:review_gate

- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:hanzo_report_cmd_2611.yaml|hanzo:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503',MISSING;parent_cmd:MISSING;ac_...
- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=report_format:hanzo_report_cmd_2611.yaml|hanzo:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503']|hanzo:lesson_candidate_no_rea...

- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|report_format:hanzo_report_cmd_2611.yaml|hanzo:empty_lessons_useful:related=['L512','L511','L510','L509','L508','L507','L506','L505','L504','L503']|hanzo:les...
- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:report_merge

- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|kagemaru:lesson_done_missing|draft_lessons:1
- 2026-05-09: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|hanzo:lesson_done_missing|draft_lessons:1

- 2026-05-06: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|kotaro:lesson_done_missing|draft_lessons:1
- 2026-05-06: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|tobisaru:lesson_done_missing|draft_lessons:1

- 2026-05-06: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|kagemaru:lesson_done_missing
- 2026-05-05: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|hayate:lesson_done_missing|draft_lessons:1

- 2026-05-05: gate=cmd_complete_gate result=FAIL executor=unknown reason=missing_gate:lesson|hanzo:lesson_done_missing
- 2026-05-05: gate=cmd_complete_gate result=FAIL executor=unknown reason=draft_lessons:1

- 2026-05-02: gate=cmd_complete_gate result=FAIL executor=unknown reason=hanzo:ac_version_mismatch:task=d41d8cd9:report=88572c76
