# tsumari 第3回 — kagemaru / 領域(a) publisher・ledger

- 対象領域: (a) publisher/ledger 経路のみ
- 抽出窓: 2026-09-03T04:37:00+09:00〜配備時刻 2026-09-03T11:17:22+09:00
- UTC換算: 2026-09-02T19:37:00.000Z〜2026-09-03T02:17:22.000Z
- 対象一次ログ: `/home/simokitafresh/.local/share/multi-agent-shogun/publish_queue/events.jsonl`、`/home/simokitafresh/.local/share/multi-agent-shogun/ledger_inbox/*/rc/*`、`/home/simokitafresh/multi-agent-shogun/logs/publisher_daemon.log`、`/home/simokitafresh/multi-agent-shogun/logs/publish_artifact_capture.log`
- 判定方法: 同一根因の反復は1事例に集約し、発生回数と全seqを併記。指定8分類は「偽陽性 / 過剰 BLOCK / 構造バグ / 循環拘束 / 遅い script・test / Claude↔Codex 仕組み差 / サンクコスト過剰複雑化 / 影響範囲・依存未解明の浅い対応」を使用。

## 抽出コマンドと出力件数

### events.jsonl

```text
$ jq -s -r --arg s '2026-09-02T19:37:00.000Z' --arg e '2026-09-03T02:17:22.000Z' 'map(select(.ts >= $s and .ts <= $e and (.kind == "c2a_rc" or .kind == "root_sync_skipped" or .kind == "ledger" or .kind == "already_published" or .kind == "published"))) | "total\t\(length)", (group_by(.kind)[] | "\(.[0].kind)\t\(length)")' /home/simokitafresh/.local/share/multi-agent-shogun/publish_queue/events.jsonl
total	134
c2a_rc	7
ledger	78
published	9
root_sync_skipped	40
```

`already_published` は独立kindではなく `ledger` の `reason=duplicate_id` として記録されていた。

### ledger_inbox/*/rc

```text
$ find /home/simokitafresh/.local/share/multi-agent-shogun/ledger_inbox -type f -path '*/rc/*' -printf '%f\n' | awk 'BEGIN{n=0} $0 >= "20260902T193700000000000Z_000000000000.yaml" && $0 <= "20260903T021722000000000Z_999999999999.yaml" {n++} END{print "rc_files=" n}'
rc_files=31

$ find .../ledger_inbox -type f -path '*/rc/*' ... | awk ... | sort | uniq -c
      2 bulletin
     29 insights
```

`events.jsonl` の対応する `ledger rc=1` は `apply_failed=3`（seq 10,14,15）と `source_outside_root=28`（seq 18〜33,43,46,103〜107,112〜116）。RC退避31件の内訳は bulletin 2件、insights 29件である。

### publisher_daemon.log

このログの各行には時刻字段がない。従って次の件数は「窓内件数」ではなく、抽出時点 2026-09-03T11:21:34+09:00 のファイル全体件数であり、対象窓への厳密な帰属は不能である。時刻なしを欠測として記録する。

```text
$ rg -n -c 'missing artifact' logs/publisher_daemon.log
28
$ rg -n -c 'root sync BLOCK' logs/publisher_daemon.log
43
$ rg -n -c 'root drain BLOCK' logs/publisher_daemon.log
913
$ wc -l < logs/publisher_daemon.log
3424
```

### publish_artifact_capture.log

このログも各行に時刻字段がない。ファイル全体32行を数え、窓内件数とは断定しない。抽出時点のファイルmtimeは `2026-09-03 11:16:42.875915946 +0900` であった。

```text
$ wc -l < logs/publish_artifact_capture.log
32
$ rg -n -c 'capture: OK' logs/publish_artifact_capture.log
20
$ rg -n -c 'base refreshed' logs/publish_artifact_capture.log
3
$ rg -n -c 'task_id/worktree/base/source_sha はすべて必須' logs/publish_artifact_capture.log
9
```

## 事例表

| ID | 時刻・発生回数 | 事象 | 主分類 | 副分類 | 真因（一次ログで確認できる範囲） | 根治済/未根治 | 次の一手 | 証跡 |
|---|---|---|---|---|---|---|---|---|
| T3-kagemaru-01 | 7件 | c2a request が `rc=1` | 影響範囲・依存未解明の浅い対応 | `base_blob_mismatch` | publisher event が `base_blob_mismatch` と対象pathを明記。`scripts/insight_write.sh` 1件、`scripts/publisher.sh` 2件、`queue/insights.yaml` 4件 | 未根治（窓内rc=1） | base refresh後の同一request再試行を行い、rc=0の一次eventを記録する | events.jsonl seq=7,11,16,40,57,62,96 |
| T3-kagemaru-02 | 3件 | ledger apply が失敗 | 影響範囲・依存未解明の浅い対応 | `apply_failed` | publisher event のreasonは `apply_failed`。対象opはRC退避に残るが、指定ログに適用失敗の下位エラーはない | 未根治（rc=1） | apply対象path・stderr・再試行結果を同一RC/eventへ記録し、rc=0を確認する | events.jsonl seq=10,14,15; ledger_inbox bulletin 2件/insights 1件 |
| T3-kagemaru-03 | 28件 | ledger source が publisher root 外 | 構造バグ | producer/publisher root 境界 | daemon行が `ledger source outside publisher root` と具体path `/home/simokitafresh/shogun-task-worktrees/hayate_97e516c55ca20a7b/queue/insights.yaml` を出力し、event reasonも `source_outside_root` | 未根治（rc=1が28件） | source_fileのroot射影契約を統一し、全28 opの再投入rc=0を確認する | events.jsonl seq=18〜33,43,46,103〜107,112〜116; publisher_daemon.log:177 |
| T3-kagemaru-04 | 14件 | 同一opの再送が `already_published` 扱い | 偽陽性 | `duplicate_id` idempotent replay | ledger event reasonが `duplicate_id`、rc=0。既公開opとして処理された | 根治済（観測上rc=0） | duplicate_id のrc=0維持を次窓で再計数する | events.jsonl seq=17,81,82,89,99,100,110,111,119,120,125,128,137,138 |
| T3-kagemaru-05 | 40件 + daemon全体43件 | root dirty によりroot syncをスキップ/阻止 | 循環拘束 | `root_dirty` / `root sync BLOCK` | events reasonが `root_dirty=<件数>`。daemonには `root sync BLOCK` が存在する。daemon側は時刻なしのため窓内件数を確定しない | 未根治（eventsで40件、daemon窓帰属は欠測） | root syncの対象・dirty根拠・完了を時刻付き一次ログで同一publicationへ結び、skip後の収束を確認する | events.jsonl seq=13,35,37,39,42,45,48,50,52,54,56,59,61,64,66,68,70,72,74,76,78,80,84,86,88,91,93,95,98,102,109,118,122,124,127,130,132,134,136,140; publisher_daemon.log全体rg=43 |
| T3-kagemaru-06 | daemon全体913件 | root drain が divergence BLOCK | 循環拘束 | root drain divergence | daemon行が `root drain BLOCK divergence base=<sha>` を出力。行時刻がなく、窓内件数は確定しない | 未根治（全体913件、窓帰属欠測） | divergenceのbase・再取得・drain完了を時刻付き一次ログで追跡し、BLOCK消失を確認する | publisher_daemon.log全体rg=913 |
| T3-kagemaru-07 | daemon全体28件 | publish artifact が見つからない | 構造バグ | missing artifact | daemon行が `missing artifact task=<task>` を出力。行時刻がなく、窓内件数は確定しない | 未根治（全体28件、窓帰属欠測） | task_idごとにartifact生成・capture・publishの存在を時刻付き一次ログで連結する | publisher_daemon.log全体rg=28 |
| T3-kagemaru-08 | daemon全体9件 | capture必須メタデータ不足 | 過剰 BLOCK | `task_id/worktree/base/source_sha` missing | capture logが必須3項目不足メッセージを9行出力。行時刻がなく、窓内件数は確定しない | 未根治（全体9件、窓帰属欠測） | 欠落taskの入力と再capture結果を一次ログへ記録し、必須3項目付きOKへ収束させる | publish_artifact_capture.log:3〜5,12〜15,30〜31 |
| T3-kagemaru-09 | ledger成功33件 + published 9件 + capture OK20件/refresh3件 | 成功した公開・ledger・captureの正常対照 | 偽陽性 | rc=0 / `published_sha` / `capture: OK` | eventsのledger成功33件・published 9件はrc=0、captureはOK20件とbase refreshed 3件 | 根治済（観測上成功） | 成功件数を失敗件数と混ぜず、次窓も同じ抽出式で再計数する | events.jsonl ledger成功seq=8,9,34,38,41,44,47,49,51,53,55,58,63,65,69,71,73,77,83,85,87,90,92,101,108,117,121,126,129,131,133,135,139; published seq=12,36,60,67,75,79,94,97,123; publish_artifact_capture.log:1〜2,6〜11,16〜29 |

## 集計

### 主分類別

| 主分類 | 事例数 | 発生件数（同一根因を集約） |
|---|---:|---:|
| 偽陽性 | 2 | 14 duplicate_id + 成功対照42件（ledger33 + published9） |
| 過剰 BLOCK | 1 | capture必須メタデータ不足9件（daemon全体） |
| 構造バグ | 2 | source_outside_root 28件 + missing artifact 28件（daemon全体） |
| 循環拘束 | 2 | root_sync_skipped 40件 + root drain BLOCK 913件（daemon全体） |
| 影響範囲・依存未解明の浅い対応 | 2 | c2a_rc 7件 + apply_failed 3件 |
| 遅い script・test | 0 | 0 |
| Claude↔Codex 仕組み差 | 0 | 0 |
| サンクコスト過剰複雑化 | 0 | 0 |

### 根治状態

- 事例数: 9
- 未根治: 7（T3-kagemaru-01, 02, 03, 05, 06, 07, 08。daemon時刻欠測を含む未解消観測を未根治として扱う）
- 根治済/成功対照: 2（T3-kagemaru-04, 09）
- 時刻欠測により窓内判定不能: 4（T3-kagemaru-05, 06, 07, 08）
- 証跡なし行数: 0（events事例は全行にseq、daemon/capture集計はファイル名+行条件を記録）
- 推測語: 0

## AC3判定

指定窓の `events.jsonl` に `c2a_rc rc=1` 7件と `ledger rc=1` 31件が存在する。さらにpublisher daemon/captureログには未解消BLOCK・artifact欠落・必須メタデータ欠落の記録がある。ただしdaemon/captureは行内時刻がなく、指定窓への厳密帰属ができない。従ってAC3はPASSにせずBLOCKとして報告する。
