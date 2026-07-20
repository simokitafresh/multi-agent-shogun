# scope commit helper silent-exit 一次再現（小太郎）

日時: 2026-07-20 / 対象: `scripts/ninja_scope_commit.sh` / 実験場所: `/tmp` の独立Git repo（共有worktree変更なし）

## 結論

silent-exitの必要十分な再現条件は、helper冒頭のsnapshot再exec後、`trap 'publish_terminal_failure ...' EXIT` と terminal ledger 初期化へ到達する前に外部終了することだった。TERM timeout 3/3、INT timeout 3/3で `stdout=0 byte / stderr=0 byte / ledger=0 / HEAD差分0` を再現した。

最小修正候補は、snapshot childの最初（`sleep "$NINJA_SCOPE_COMMIT_TEST_AFTER_SNAPSHOT_DELAY"` より前）にsignal/EXIT用の最小bootstrap ledgerを設置し、通常ledger初期化後に正式handlerへ置換すること。commit公開境界や既存fail-closed gateを増やす必要はない。

## 15試行の一次結果

| 候補 | 各3回の結果 | stdout | stderr | ledger | HEAD | 終了理由 |
|---|---|---:|---:|---|---|---|
| set-e wrapper | 3/3 rc=0（偽成功） | 11 B | 512 B | 3/3あり | 不変 | helper rc=2後もwrapper継続 |
| subshell | 3/3 rc=2 | 0 B | 515 B | 3/3あり | 不変 | no-change BLOCK |
| timeout/TERM | 3/3 rc=124 | 0 B | 0 B | 3/3なし | 不変 | snapshot delay中TERM |
| signal/INT | 3/3 rc=124 | 0 B | 0 B | 3/3なし | 不変 | snapshot delay中INT |
| untracked成果物 | 3/3 rc=0 | 41 B（hashのみ） | 1361 B | 3/3あり | 各1世代進行 | 正常完了 |

生データ: `/tmp/kotaro_scope_trials.tsv`。実験root: `/tmp/tmp.367ucV5HNV`。

## 根因

1. 冒頭L14-22でsnapshotへ`exec`する。
2. childはL25でsnapshot pathnameを消し、L29-31の任意delayへ入る。
3. terminal state/ledgerはL202以降、EXIT trapはL298で初めて作られる。
4. よってL22後〜L298前のsignal/timeoutは観測契約を一切持たず、完全無出力となる。実測6/6が一致した。

set-e候補では別の呼出側罠も確認した。`( set -e; helper; printf unreachable ) || rc=$?` のようにcompound command全体をOR-listへ置くと、その内部では`errexit`が抑制される。helper自身はrc=2とledgerを返しても後続が実行され、wrapperはrc=0となった（3/3）。したがって呼出側はhelperを単独実行して即rcを保存する必要がある。

## 安全性と最小修正候補

- 成果物欠落: 正常untracked 3件中0件。全3件でファイルが存在し、stdoutは40hex+改行、ledger complete=true。
- 誤commit: 異常系12件中HEAD変化0件。正常系のみ3/3で各1 commit。
- 修正候補A（根治）: snapshot child開始直後にrun_idと最小ledger pathを確定し、TERM/INT/HUP/EXITで `rc/signal/phase=bootstrap/complete=false` をatomic記録する。正式trap導入時にbootstrap trapを置換。
- 修正候補B（呼出側）: `set -e`任せやOR-list内compound commandを避け、`set +e; output=$(helper ...); rc=$?; set -e` 相当でrcを明示捕捉し、rc!=0またはhash不正なら後続を止める。
- 維持条件: 成功stdoutは40hex 1行のみ、metadataはstderr、HEAD公開前の異常はHEAD不変、公開後の異常はledgerからcommit hash回収可能、異常系の誤commit 0。

origin: `[[cmd_karo_retro_scope_helper_silent_exit_202607202145]] -> [[snapshot前trap未設置]] -> [[silent-exit]]`
