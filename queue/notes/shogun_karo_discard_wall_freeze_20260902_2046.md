# 捨てる壁への hotfix 凍結(殿 2026-09-02 20:44『捨てる壁に時間をかけるのは原理原則に反していないか』)

[MEM: memory_db knowledge:ff7ed7af81758ba8 2026-09-02T14:43 "殿裁定 14:02『本質に戻ろう』…lease/credential/pre-push 検査を撤回し flock 1 本へ"]

## 事実(将軍集計 20:45)
- 13:00 以降の hotfix/ci_fix cmd = 15 本。変更 file 上位: cmd_complete_gate.sh 6 / extract_command_files.sh 4 / gate_gunshi_report_precheck.sh 3 / safe_shared_main_ff.sh 2 / gate_report_format.sh 2。
- 設計書 §10 manifest 照合: cmd_complete_gate.sh の autopush 群=M1(削除)・M8(削除)・M11(test 削除)、safe_shared_main_ff.sh=M3(削除)、gate_report_format.sh の ancestry/receipt 検査=M7(縮退)、push_lane=M2(削除)。今日の壁の大半は U7/U8 で捨てる file に発生し、そこへ hotfix を当てていた。

## 規則(今から)
1. **§10 manifest(M1-M11)の対象 file と precheck の検出器へ hotfix を出さない。** 偽陽性は判断で越える: 4 観点 LGTM を正本に karo_attention へ FP 根拠を書いて APPROVE(30 秒)。hotfix(40 分)は禁止。
2. 例外は「単一 publisher の実装 file(§9.1 の作る file)そのものが壊れている時」だけ。U2 の restore 欠陥(cmd_4449 検出)はこれに該当=修正 lane を出す。
3. 走行中の hotfix(半蔵 PRE11 task identity、影丸 ga556 doc_no_changelog、才蔵 ci_fix generated_instructions_cache)は、本規則の対象なら**報告まで待たず idle 化**して主線へ回す。対象外(pre-commit 等の commit 側)は完走。
4. 順序の前倒し: 第 2 波を U3(publisher daemon、dry-run)から始める。U3 が origin へ publish し始めた時点で ancestry WAIT・push lane・GA-PUSH1 の壁は主線から消える(§3 の U5→U3 順は、U5 admit が無い間は U3 の enqueue 側で migration_ack を要求しない dry-run で代替)。U1b/U5/U6 は U3 dry-run と並走。将軍が今夜 U3/U1b/U5/U6 を起票する。

## 二値AC
- 20:45 以降、§10 対象 file を触る hotfix の新規配備 0(deploy_task.log で確認)。
- cmd_4445/4450 の gate は次 cycle の再 gate で CLEAR(偽 WAIT は remote 参照の一時失敗。hotfix 不要)。
