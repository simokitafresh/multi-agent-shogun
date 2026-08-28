# cmd_4402 根治弾効果計測（before/after）

## 計測境界と一次証拠

- 対象: `cmd_4396` SG-PRE36、`cmd_4397` blocked ledger writer、`cmd_4398` 親report exact matcher。
- `cmd_4396`導入境界: commit `66add81c11187761613ae519777b985d53e35f9e`、`2026-08-25T01:52:13+09:00`。
- `cmd_4397`導入境界: commit `7a1e3734be9ac293dd392a2d3509f4fa6ec0ae9f`、`2026-08-25T02:28:29+09:00`。
- `cmd_4398`導入境界: commit `ba9b56a801e1403cfea335846f6aa635e6c43fb7`、`2026-08-25T02:19:00+09:00`。
- 固定終端: `2026-08-25T07:32:21`（計測実行時の `logs/deploy_issue_log.yaml` 最終観測時刻）。各境界から終端までと同幅をbeforeへ設定した。境界は `[start, end)`。
- source hashes: `deploy_issue_log.yaml=ef6edfebf90a7a1d941275f5083737860417da4e2707c007356987296da1bb7f`, `gunshi_review_log.yaml=c73fb5e2ee76e91fe707121d4f3c273d192b6320b10766c29e393af622653d40`, `deploy_task.log=12ced7f220dfa092fb415eb25fb53a65ceb7ad920d604e673e7bb61c08f3d6ee`。

## AC1: 家老deploy blocked・再試行・解消時間

定義はcmd_4393正本に合わせた。`blocked/deployed` は `deploy_issue_log.yaml` の `result`、再試行は同一 `cmd_id` の `issued` の2回目以降、解消時間はblocked後の同一cmd_idの次のdeployedまで（同一window内で完了したもの）とした。

実行コマンド（`logs/deploy_issue_log.yaml` の固定scalar行を抽出し、各windowの `result`・`cmd_id`・blocked→deployed秒を集計）:

```text
python3 - <<'PY'
from datetime import datetime
from collections import Counter
import statistics
rows=[]; cur={}
for line in open('logs/deploy_issue_log.yaml'):
    s=line.strip()
    if s.startswith('- attempt_id:'):
        if cur: rows.append(cur)
        cur={'attempt_id':s.split(':',1)[1].strip().strip('"')}
    elif s.startswith('cmd_id:'): cur['cmd_id']=s.split(':',1)[1].strip().strip('"')
    elif s.startswith('result:'): cur['result']=s.split(':',1)[1].strip().strip('"')
    elif s.startswith('timestamp:'): cur['timestamp']=s.split(':',1)[1].strip().strip('"')
if cur: rows.append(cur)
for x in rows: x['dt']=datetime.fromisoformat(x['timestamp'])
end=datetime.fromisoformat('2026-08-25T07:32:21'); cut=datetime.fromisoformat('2026-08-25T02:28:29'); start=cut-(end-cut)
print('cutover=%s end=%s before_start=%s width_sec=%.0f' % (cut.isoformat(),end.isoformat(),start.isoformat(),(end-cut).total_seconds()))
for label,lo,hi in [('before',start,cut),('after',cut,end)]:
    data=[x for x in rows if lo<=x['dt']<hi]; issued=[x for x in data if x.get('result')=='issued']; c=Counter(x.get('cmd_id') for x in issued); blocked=[x for x in data if x.get('result')=='blocked']; times=[]
    for i,b in enumerate(rows):
        if not(lo<=b['dt']<hi and b.get('result')=='blocked'): continue
        nxt=next((d for d in rows[i+1:] if d.get('cmd_id')==b.get('cmd_id') and d.get('result')=='deployed'),None)
        if nxt and nxt['dt']<hi: times.append((nxt['dt']-b['dt']).total_seconds())
    print('%s rows=%d issued=%d blocked=%d deployed=%d unique_issued_cmds=%d multi_attempt_cmds=%d repeat_attempts=%d blocked_to_next_deployed_resolved_n=%d median_sec=%s mean_sec=%s' % (label,len(data),len(issued),len(blocked),sum(x.get('result')=='deployed' for x in data),len(c),sum(v>1 for v in c.values()),sum(max(v-1,0) for v in c.values()),len(times),statistics.median(times) if times else 'NA',round(statistics.mean(times),2) if times else 'NA'))
PY
```

生出力:

```text
cutover=2026-08-25T02:28:29 end=2026-08-25T07:32:21 before_start=2026-08-24T21:24:37 width_sec=18232
before rows=32 issued=16 blocked=3 deployed=13 unique_issued_cmds=13 multi_attempt_cmds=2 repeat_attempts=3 blocked_to_next_deployed_resolved_n=3 median_sec=110.0 mean_sec=109.33
after rows=24 issued=12 blocked=4 deployed=8 unique_issued_cmds=11 multi_attempt_cmds=1 repeat_attempts=1 blocked_to_next_deployed_resolved_n=1 median_sec=141.0 mean_sec=141.0
```

判定: blockedは `3→4` で1件悪化、再試行は `3→1` で2件減少、解消時間中央値は `110.0→141.0秒` で31.0秒悪化。したがってblocked全体の改善は未確認であり、再試行減少だけを根治効果とは断定しない（窓内母数がbefore 32行/after 24行）。

## AC2: 軍師レビューFAIL反復と親report誤BLOCK

### precheck関連FAIL

`logs/gunshi_review_log.yaml` のトップレベルreview recordについて、`review_type=report`、`verdict=FAIL`、summaryまたはgate_prediction_reasonに`precheck`を含むものを数えた。`cmd_4396` commit境界から終端までの前後同幅は `before_start=2026-08-24T20:12:05`、`after_start=2026-08-25T01:52:13`。

実行コマンド:

```text
python3 - <<'PY'
from datetime import datetime
reviews=[]; cur=None
for line in open('logs/gunshi_review_log.yaml'):
    if line.startswith('- cmd_id:'):
        if cur: reviews.append(cur)
        cur={'cmd_id':line.split(':',1)[1].strip().strip('"\'')}; continue
    if cur and line.startswith('  ') and not line.startswith('    '):
        s=line.strip()
        for k in ('review_type','verdict','gate_prediction_reason','summary','timestamp'):
            if s.startswith(k+':'): cur[k]=s.split(':',1)[1].strip().strip('"\'')
if cur: reviews.append(cur)
for x in reviews:
    if 'timestamp' in x: x['dt']=datetime.fromisoformat(x['timestamp'].replace('+09:00',''))
end=datetime.fromisoformat('2026-08-25T07:32:21'); cut=datetime.fromisoformat('2026-08-25T01:52:13'); start=cut-(end-cut)
for label,lo,hi in [('before',start,cut),('after',cut,end)]:
    hits=[x for x in reviews if lo<=x.get('dt',datetime.min)<hi and x.get('review_type')=='report' and x.get('verdict')=='FAIL' and 'precheck' in ((x.get('summary','')+' '+x.get('gate_prediction_reason','')).lower())]
    print('%s precheck_fail_reports=%d' % (label,len(hits)))
    for x in hits: print(' raw',x.get('timestamp'),x.get('cmd_id'),x.get('review_type'),x.get('verdict'),x.get('gate_prediction_reason'))
PY
```

生出力:

```text
cutover=2026-08-25T01:52:13 end=2026-08-25T07:32:21 before_start=2026-08-24T20:12:05
before precheck_fail_reports=1
 raw 2026-08-25T01:06:00+09:00 cmd_4393 report FAIL parent_ac_uncovered:AC1-4。家老はAC全カバー確認済みだがprecheckが認識していない
after precheck_fail_reports=1
 raw 2026-08-25T03:15:00+09:00 cmd_karo_hotfix_ga496_context_freshness report FAIL vercel_phase:broken_refs
```

判定: 件数は `1→1` で減少なし。ただしafterの1件はSG-PRE36のparent_ac認識ではなく、contextのbroken_refsを検出した別根因である。SG-PRE36対象の再発0は観測できたが、precheck関連FAIL全体の消滅は未確認。

### 親report誤BLOCK

`logs/deploy_task.log` から `archive_terminalが誤BLOCKした` を含む行を `cmd_4398` 導入境界（`2026-08-25T02:19:00`）の前後同幅で数えた。

生出力:

```text
parent_false_block_cutover=2026-08-25T02:19:00 end=2026-08-25T07:32:21 before_start=2026-08-24T21:05:39
before parent_archive_false_block=1
 raw [2026-08-25 01:51:35] [DEPLOY] wave_cache: miss ... target_key=cmd_4393のGATE CLEAR後archive_terminalが誤BLOCKした(家老報告blt_20260825_014333_48517c)。原因=completion_active_report_countの親report matcherが前方一致で子cmd(接尾辞付きID)のreport・symlinkを親の未終端reportとして計数する構造。
after parent_archive_false_block=0
```

判定: 親report誤BLOCKは `1→0`。この指標だけはcmd_4398導入後の再発を観測しなかった。

## AC3: 未確認・悪化指標と還流候補

- `decision_candidate`: blocked全体は `3→4`、blocked解消中央値は `110.0→141.0秒` と悪化。cmd_4397は分類記録を構造化したが、分類はblocked発生そのものを抑制しないため、前倒し検査の効果と混同しない。
- `decision_candidate`: precheck FAIL全体は `1→1`。afterのbroken_refsは別根因であり、SG-PRE36の有効性をFAIL全体の減少で評価できない。
- 親report誤BLOCKは `1→0` で、cmd_4398のexact matcherはこの観測窓で再発なし。
- 結論: 根治3弾の効果は指標ごとに分離しており、全体改善を宣言しない。次回はblocked理由別の自然cohortを同じ定義で追加蓄積し、cmd_4397の分類後データで理由別の前倒し検査へ接続する。

## 現物確認

```text
$ ls -l docs/research/cmd_4402_konti_effect_measurement_20260825.md
$ head -1 docs/research/cmd_4402_konti_effect_measurement_20260825.md
$ test -s docs/research/cmd_4402_konti_effect_measurement_20260825.md; echo $?
```
