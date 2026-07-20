# ninja_monitor snapshot stall case65/70 retro

日時: 2026-07-20  
対象: `write_karo_snapshot()` / `tests/unit/test_ninja_monitor_stall.bats` case65・70  
本体変更: なし

## 結論

FAILの原因は全repo/fixtureが共有する固定lock `/tmp/karo_snapshot.lock` である。case65/70の判定内容は正しく、production monitor等が5秒超lockを保持した時だけsnapshotが生成されず、後続grepが偽FAILする。個別再実行ではcase65 3/3 PASS（7396–10514ms）、case70 PASSで、常時の機能回帰ではなかった。

最速候補はlock identityをsnapshot path単位にする方式である。productionの同一`queue/karo_snapshot.txt` writer同士は同じlockを共有して排他を維持し、Batsの各`$NINJA_MONITOR_TEST_ROOT/queue/karo_snapshot.txt`はfixture固有lockとなる。待機延長は偽FAILを消すがwallを増やすため不採用。

## 同一fixture実験

8秒間 `/tmp/karo_snapshot.lock` を保持し、同じcaseを実行した。false positiveは正しいfixtureがlock競合だけでFAILした件数、見逃しは不正snapshotをPASSした件数。

|候補|case|rc|wall_ms|false positive|見逃し|
|---|---:|---:|---:|---:|---:|
|現行 固定global lock/5秒|65|1|8181|1|0|
|snapshot path単位lock|65|0|2095|0|0|
|固定global lock/10秒待機|65|0|12980|0|0|
|現行 固定global lock/5秒|70|1|7523|1|0|
|snapshot path単位lock|70|0|1531|0|0|

一次fixture: `/tmp/saizo-stall-lock.W029Wq`。候補版は一時copyの`lock_file`だけを`${KARO_SNAPSHOT_LOCK_FILE:-/tmp/karo_snapshot.lock}`へ置換し、本番ファイルは変更していない。

## 適用境界

1. lock defaultはsnapshot自身から導出する（例: `${snapshot_file}.lock`）。同一snapshot writerは必ず同一lockを使う。
2. fixtureは`SCRIPT_DIR`が異なるため自然に別lockとなり、production daemonと競合しない。
3. atomic `mktemp → mv`、5秒bounded wait、snapshot内容とcase65/70の全grep assertionは変更しない。
4. lock取得失敗をPASSへ変換しない。機能FAIL・snapshot欠落の見逃し0を維持する。
5. 単なるwait延長、テストSKIP、assertion削除は採用しない。

この境界なら再現率（8秒競合時に現行2/2 FAIL）を維持して真因を検出しつつ、fixture固有lockでは2/2 PASS、false positive 2→0、見逃し0、case65はwait延長候補比12980→2095ms（83.9%短縮）となる。
