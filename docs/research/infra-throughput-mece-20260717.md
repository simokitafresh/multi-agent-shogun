# Infra Throughput MECE Register — 2026-07-17

品質合格スループット = 固定品質で合格した成果数 / 壁時計時間。受領提案は以下6領域へ重複なく統合する。

| Domain | Included proposals | Status / owner |
|---|---|---|
| Campaign control-plane | retry pending-report BLOCK、隔離queue二重正本、stage別duration/超過ALERT | Active / saizo |
| Deploy & knowledge I/O | 4-way重複memory/lesson scan、118秒lock、wave snapshot/cache | Active / kagemaru |
| Report & gate state machine | field逐次subprocess、FAIL/completed矛盾、二重gate、terminal順序、strict metrics scaffold | Active / hanzo |
| Review & recovery | gunshi recovery 11分、同一instruction/skill再読、campaign shard approval不在 | Active / kotaro |
| Delivery & execution state | 同文pending重複、busy配送、SESSION_ID running/completed曖昧 | Active / tobisaru |
| Monitor & lifecycle ledger | reflux 630 YAML O(N)走査、snapshot stale、append-only completion ledger | Active / hayate |
| Commit concurrency | private/shared index競合、HEAD/index/worktree不一致、lock待ちとterminal状態不可視 | Active / kagemaru |
| Skill health | startup script-ref未確認、直近50件FAIL率10%超、改善action未接続 | Active / tobisaru |

Completion skill 3本の880行超hot-pathは Review & recovery 領域に属する。既存未commit変更を保護したうえで、内容hash cache/短縮正本の最終統合対象とする。

## Already resolved and regression-protected

- `/mnt/c` materialize p95: 613s → 18.041s (`44bb1d23c`)
- process drain / heavy run admission / index lock / retry cwd: child survivors 1+ → 0, heavy concurrency 7+ → <=1 (`ef9c88492`, `78cbbe43c`)
- ignored explicit owned commit + identity inheritance: commit failures 2/2 → 0 (`22a14d076`)
- canonical report pointer: potential wait 900s → 5.95s (`eee01961a`)
- reflux repeat selection: same promotion 3+ → 0, inventory 189 → 188 (`4a122414d`)

## Endpoint

各domainはbefore/after、FAIL 0、SKIP 0、未解消BLOCKを必須とする。統合後にF1未合格I1/A1/A2を再試行し6/6を確認する。

## 20:13 長時間化RCA（一次証跡）

| Cause | Before evidence | Fix / status |
|---|---|---|
| shared Git commit transaction | helper 22-34秒、3忍者並列時にscope path `MM`、7c2a802e7が一時`bad object` | `ea11789a0` terminal hash/object/ref contract。既存campaign 2pathの対象限定repairを追加中 |
| report/gate early terminalization | report_gate/review_recoveryともgate log 5回。実装後約4分をrevision往復 | `7c2a802e7`: 46 fields/1 atomic、15-19秒→0.16秒、FAIL lane一発導出 |
| campaign fixture process amplification | 28 tests=121.59秒。1 bridge当たり24 yaml_field_set、最大672 subprocess | setup共有/batch化をcampaign follow-upで実施 |
| deploy/read duplication | 6並列wave 19:51:33→最終deploy 19:53:47=134秒。memory/lesson cold miss重複 | `30748a921`: wave build 4→1、focused 1.109秒。次waveで実測30秒以下を再確認 |
| hot-path global test discovery | new `test_*.bats` commit時に全unit Batsへ`grep -h '^@test'` | test catalog/indexへ置換するfollow-up対象 |
| lifecycle O(N) scan | 647 report parse 5.7秒、inventory 7.09秒 | `68847eb9`: ledger lookup 0.14秒、inventory 0.34秒、diff 0 |

結論: 固有テストは0.16〜1.24秒級だが、共有Git・gate・fixture・配備I/Oが壁時計を6〜12分へ増幅した。品質計算ではなく周辺待機が支配していた。

## 20:21 追加実測と第3波

| Hot path | Before | Action / endpoint |
|---|---:|---|
| 将軍startup gate | 66,936ms/回、recovery中2回=134秒 | 疾風へ配備。check別durationを記録し10,000ms以下、警告集合差分0 |
| commit transaction | 19,855〜27,468ms、lock wait 5ms | `b3716c042`: 残留MM 2→0、41/41 PASS。次段でhook/sync/postcheck別msを計測 |
| report revision | 約50 field逐次=16.6秒、途中completed再遷移で更新BLOCK | 飛猿へ配備。unlock+field更新+verdict+terminalを1 transaction、1秒以下 |
| gunshi review | 約60秒/件、理論tool最小21秒 | 小太郎へ配備。同型5件batch、単件p95 30秒以下、SG証跡欠落0 |
| campaign fixture | 28 tests=121.59秒、最大672 YAML subprocess | 才蔵へrevision続行。30秒以下、subprocess 50以下 |
| deploy wave | 旧6並列=134秒 | 第3波3並列=30.865秒、77.0%短縮。次endpoint 20秒以下 |

追加根因は、実装計算ではなく、(1) startup全検査の直列重複、(2) commit hook/sync/postcheckの不可視な約20〜27秒、(3) report field単位process起動、(4) review tool chain逐次化、(5) fixture内YAML subprocess増幅である。第3波は全て品質集合を固定し、時間閾値とFAIL0/SKIP0を同時AC化した。

## 21:01 第3波結果と第4波

| Lane | Before | Current | Verdict |
|---|---:|---:|---|
| report revision transaction | 16.6秒 / atomic publish 50 | 182〜216ms / publish 1、22/22 PASS | LGTM、98.7〜98.9%削減 |
| review batch | 同型5件 約300秒 | wall 275ms、p95 119ms、30/30 PASS | LGTM、99.9%削減 |
| campaign fixture | 121.59秒、YAML逐次19 | 21秒、batch 1、28/28 PASS | LGTM、82.7%削減 |
| commit reminder | 他者dirty 13件で誤警告 | owned scope判定、16/16 PASS、FP0/FN0 | LGTM |
| startup gate | 66.936秒 | 20.581秒timeout | 69.2%削減だが10秒AC未達、revision中 |
| CI failure visibility | first FAIL後2,211秒継続 | fail-fast 30秒以下を実装中 | run 29574746129はGREENでなくcancelled |

startup残差の一次実測はfull `git status` 15.709秒、scope status 1.554秒、full `rg` 2分35秒、loadavg 33.39、process 986。`/mnt/c` v9fs上の無制御fan-outが561倍の待機増幅を起こす。第4波ではfull repo走査のscope化、runner fail-fast、PostTool注入最大3件、skill freshnessのmtime→content hash、preflight alias fallback/no-hit fail-closed、no-code commit契約を6忍者へ配備した。

## 因果リンク

- ← [[品質合格スループット]] スループット第一原則の計測・改善台帳
- ← [[長時間化]] v9fs I/O飽和+共有lock+tool往復が実作業を圧倒
- → [[infrastructure]] infra platform層の性能改善
