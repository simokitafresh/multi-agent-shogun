# インフラバグ調査: stale report蓄積+交差汚染+GATE不整合

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-03
- トリガー: 殿「未解決のインフラバグがないか調査せよ」

## 要約

queue/reports/に237件のstale reportファイルが蓄積。3つの根因バグを特定。

## バグ1: stale report蓄積 (161件/237件) — archive_completed.sh

### 現象
完了済みcmdの報告YAMLがarchiveされず237件蓄積(archive済み4092件の5.8%)。

### SKIP理由内訳(archive_completed.sh sweep実行)
| 理由 | 件数 | 割合 |
|------|------|------|
| archive.done not found | 87 | 54% |
| review_gate.done is placeholder (deploy_preflight) | 54 | 34% |
| review_gate.done not found | 20 | 12% |

### 根因
1. **archive.done不在(87件)**: cmd_complete_gate.shのGATE CLEAR最終ステップでarchive.doneが作成される。GATE未通過(途中停止・manual_override等)のcmdはarchive.doneが永久に作成されない → reportが永久残存
2. **placeholder(54件)**: deploy_task.shが配備時にreview_gate.doneを`source: deploy_preflight`で仮作成(GP-133)。軍師レビュー→家老スタンプ後に本物に上書きされるが、karo_direct配備やCI修正cmdfで上書きされないケースがある
3. **review_gate.done不在(20件)**: gates directoryが作成されていない or 手動CLEAR

### 因果鎖
配備→report生成→GATE未完走→archive.done/review_gate.done欠損→sweep SKIP→report永久残存→次回同cmd_idで交差汚染(バグ2)のリスク蓄積(負の複利)

### 影響
- ディスク: 237×3KB≈700KB(軽微)
- **交差汚染リスク**: 同cmd_idが6忍者分のreportを保持(cmd_2094)。cmd_complete_gate.shが全件拾う(バグ2)
- inode消費: WSL2 NTFSでは問題なし

## バグ2: cmd_complete_gate.sh L1980 glob交差汚染

### 現象
cmd_2526でtobisaru(旧配備先)のstale reportが残存 → cmd_complete_gate.shがglobで拾いreport_format BLOCKを発生。5回BLOCKの後manual_overrideで手動CLEAR。

### 根因
`scripts/cmd_complete_gate.sh` L1976-1986:
```python
if not ninjas:
    for rpath in sorted(glob.glob(...f"*_report_{cmd_id}*.yaml")):
        ...
        add_unique(ninjas, bname[:idx])
```
task YAMLがidleの場合(再配備後)、reportファイル名から忍者名を抽出。globが全忍者のreportを拾い、stale reportのvalidation FAILでBLOCK。

### 再現条件
1. cmd_Xがninja_Aに配備
2. ninja_Aが報告作成
3. cmd_Xがninja_Bに再配備(stale task → idle化)
4. ninja_Bが報告作成+GATE実行
5. L1976のfallback glob → ninja_A+ninja_B両方を検出
6. ninja_Aの旧report → format FAIL → BLOCK

### 影響
cmd再配備のたびにmanual_overrideが必要。バグ1の蓄積で影響範囲が拡大(cmd_2094は6忍者分のreportが残存)。

### 修正案
L1980のglobで拾ったreportのparent_cmdがCMD_IDと一致するか、またはtask YAML上の現在の配備先忍者のみをninjasリストに追加する。stale reportは除外。

## バグ3: cmd_karo_ci_fix_rfs_quoteのGATE不整合

### 現象
- gate_metrics.log: 最終エントリ=BLOCK(binary_checks_fail, 11:04:03)。CLEAR記録なし
- queue/gates/cmd_karo_ci_fix_rfs_quote/: review_gate.done + lesson.done 存在
- review_gate.doneの内容: `source: gunshi_review, result: LGTM`

### 根因
review_gate.doneは軍師LGTMで作成されたが、cmd_complete_gate.shの再実行(GATE CLEAR判定+gate_metrics CLEAR書込み)が行われなかった。review_gate.done作成 → gate再トリガーの連携が途切れた。

### 影響
- archive_completed.shのsweepでは review_gate.done=ok → archive.doneチェックへ進む → archive.doneあり → archive可能(このcmdは問題なし)
- gate_metrics.logの統計が不正確(CLEARカウント漏れ)

## 修正優先度

| バグ | 緊急度 | 修正方法 | 効果 |
|------|--------|----------|------|
| バグ1 | **urgent** | archive_completed.shにplaceholder上書き+archive.done不在時のfallback(gate_metrics CLEAR確認 or 一定期間経過) | 161件即解消+今後の蓄積防止 |
| バグ2 | **urgent** | cmd_complete_gate.sh L1980のfallback globでstale report除外 | 再配備時の偽BLOCK根絶 |
| バグ3 | normal | gate_metrics CLEAR書込みの保証(review_gate.done作成後のgate再トリガー) | 統計精度向上 |

generated: 2026-05-03T20:45:00+09:00
