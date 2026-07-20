# 9p worktree完了安定性 retro（hayate）

- 対象: `cmd_karo_retro_worktree_stability_202607202105`
- fixture: `/mnt/c`上の独立clone。各runでindex.lockを作成し40ms後にrenameで解放、さらに40ms後にtracked fileへdirtyを後着させた。
- 比較: 即時status / lock消失後status / lock消失後80ms間隔のstatus安定2回。各10回、timeout 500ms。

## §1 一次結果

| 候補 | N | 偽完了 | 平均待機ms | min-max ms | timeout | 最終dirty合計 | complete / dirty判定 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 即時status | 10 | 10 | 256.1 | 209-308 | 0 | 10 | 10 / 0 |
| index.lock消失→status | 10 | 0 | 333.0 | 306-359 | 0 | 10 | 0 / 10 |
| lock消失→status安定2回 | 10 | 0 | 705.7 | 560-875 | 0 | 10 | 0 / 10 |

即時statusはコマンド自体に平均256.1ms掛かる間にdirtyが後着しても、開始時snapshot相当のcleanを10/10で返した。lock消失を先に観測すると後着dirtyを10/10捕捉した。安定2回も欠落0だが、単発lock待ちより平均372.7ms遅い。

## §2 採用候補と適用境界

欠落0かつ待機最小は「writer所有のindex.lock消失をbounded waitし、その後にstatusを1回取得」である。即時statusは禁止候補、安定2回は常用しない。

- 適用: Git更新主体がindex.lockを最後まで所有し、lock解放がwriter終端を表すcommit/add/index repair。
- 安定2回へ昇格: lock解放後にも別process・hook・非Git writerがworktreeを書き得ることを一次確認した経路。2回の内容一致かつ両方cleanを完了条件とする。
- 非適用: lock非所有writer、複数独立lock、network job、意図的dirtyを残す操作。これらは対象固有の終端signal/process drainが必要。
- timeout時: completeに倒さず未完了を返す。lock削除や閾値緩和は行わない。

品質差分は偽完了10→0、dirty見逃し10→0、timeout 0→0。待機増分は即時比+76.9msで、安定2回の追加+372.7msを避けられる。

## §3 生データ

`/tmp/hayate_stability_results.tsv` に30試行のcandidate/run/false_complete/wait_ms/timeout/final_dirty/decisionを保存した。共有worktree、本体、gate、hookは変更していない。

origin: `[[9p_worktree_false_completion]] -> [[status_snapshot_before_index_writer_terminal]] -> [[bounded_lock_absence_then_status]]`
