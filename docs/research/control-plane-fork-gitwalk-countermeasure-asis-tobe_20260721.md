# 制御面 fork / gitwalk 恒久対策設計（As-Is / To-Be）

- cmd: `cmd_4112`
- date: 2026-07-21
- scope: 設計のみ。実装は後続cmdへ引き継ぐ。
- origin: `[[cmd_4112]] -> [[WSL2_mntc_subprocess反復fork_大履歴gitwalk]] -> [[制御面レイテンシ恒久対策]]`

## §1 結論

4ホットスポットの共通病理は、WSL2 `/mnt/c` 上で「行・対象ごとの短命process fork」または「対象ごとの全履歴gitwalk」を反復することである。対策単位は個別gateではなく、(1) 時刻・入力走査の単一process化、(2) staged/git objectの単一pass batch化、(3) commit hashを一次キーにした狭域参照、(4) immutable入力に対するext4 atomic snapshotの4方式とする。

新規汎用cacheは作らない。既存の `scripts/lib/memory_db_cache.sh` が持つsingle-flight・stale-while-refresh・atomic publish契約と、`scripts/gates/gate_gunshi_report_precheck.sh` のcommit-hash優先pathを横展開する。対象固有で既存資産だけでは解けないのは、台帳時刻parseの単一process化、pre-commit staged snapshot共有、skill checked-atのtimestamp→commit解決batch化である。

## §2 As-Is：一次実測と根因

計測値は将軍の2026-07-21直接計測を正本とする。現行コードには同日配備された個別fast pathが既に含まれるため、以下の秒数は病理発見時のbaselineであり、行番号は現在の対応箇所を示す。

| # | ホットスポット | baseline実測 | 根因メカニズム | 現行コード上の対応箇所 |
|---|---|---:|---|---|
| 1 | `gate_test_health.sh` 台帳鮮度 | 65.7秒（`date` fork 8,195回）→ mktime化0.3秒 | ledger各行で外部`date`を起動し、件数Nに対してforkがO(N) | `scripts/gates/gate_test_health.sh:100-126`。現在はPython 1 process内の`csv.DictReader`+時刻parseへ集約 |
| 2 | `git-pre-commit.sh` self_sync | 6.37秒、commitの96.5%が無変更 | 毎commitでfull `sync_git_hooks.sh`を起動し、manifest各hookについて複数git subprocess/hash/配置比較を反復 | `scripts/hooks/git-pre-commit.sh:70-92` staged snapshotを1回取得、`:128-168` staged hook有無+`cmp`でfull sync要否を判定。full側のper-hook git呼出は`scripts/sync_git_hooks.sh:117-168,196` |
| 3 | `gate_skill_script_refs.sh` | `git rev-list --before` 5.37秒/回 × 37 skillで120秒超 | skillごとのchecked-atをcommitへ解決する全履歴gitwalk。timestamp重複があってもprocess/cache境界が細かい | `scripts/gates/gate_skill_script_refs.sh:249-282` timestamp cache、`:285-305` persistent `git cat-file --batch`。全履歴点は`:269-278` |
| 4 | `gate_gunshi_report_precheck.sh` | git呼出20回、24.97秒 | PRE3/PRE13/PRE19等が同じcmd/fileを別々に全履歴grepし、対象数に比例してgitwalk | `scripts/gates/gate_gunshi_report_precheck.sh:175-218` batch共有。hash有りは`:184-200`の`diff-tree/show`、hash無しのみ`:202-216`の全履歴fallback |

網羅確認: 指定4ホットスポットを4/4記載し、各々にbaseline秒数、forkまたは全履歴gitwalk点、現行行番号を付した。

## §3 既存資産の横展開可否

### §3.1 grepで確認した既存契約

- ext4 snapshot: `scripts/lib/memory_db_cache.sh:52-58`がsource/WAL/SHM鮮度、`:61-99`がflock single-flight非同期refresh、`:152-167`がlast atomically-published snapshotの継続読取を実装する。publisherは`os.replace()`を用いる契約が`:157-162`に明記される。
- commit-hash優先path: `scripts/gates/gate_gunshi_report_precheck.sh:184-200`が報告記載hashを抽出し、`git diff-tree`/`git show`で狭域参照する。hash欠落時だけ`:202-216`で`git log --grep`へfallbackする。

| ホットスポット | commit-hash優先path | ext4 atomic snapshot | 判定 | 既存で解けない限定部分 |
|---|---|---|---|---|
| test health台帳鮮度 | 不要（git履歴を読まない） | 条件付き採用。ledgerが大規模化し反復readが支配的な場合のみ、既存freshness/single-flight契約を再利用 | 新規cache禁止。現行Python単一processでまず完結 | 時刻parseの単一process化は対象固有（現行実装済み） |
| pre-commit self_sync | staged/HEAD blobを一次キーに採用可能 | 不採用。commit直前の可変indexをstale snapshotで読むと真陽性を失う | staged snapshot共有+hash/cmp fast path | staged indexの1回走査とhook manifest一括hash比較 |
| skill refs | checked-at→commit hashを一次キーに採用 | 条件付き採用。immutableな`commit:path` baseline/resultだけを既存atomic publish契約で保存可能 | timestamp解決をbatch化し、blobは既存`cat-file --batch`を維持 | 複数timestampの単一gitwalk解決（`rev-list --before`のN回呼出廃止） |
| gunshi precheck | 全面採用（既に実装） | 不採用。report/worktreeは実行時可変でstale許容不可 | report commit hash必須化を上流へ寄せ、fallbackを例外化 | hash欠落legacy報告のbounded fallback |

## §4 To-Be マッピング

| ホットスポット | 割当方式 | 目標（warm / 通常経路） | 真陽性維持の境界条件 |
|---|---|---:|---|
| test health台帳鮮度 | 単一process batch（全行を1回parse）。大容量時のみext4 snapshot退避 | 65.7秒→0.5秒以下（現行0.3秒を上限確認値とする） | ledger全行を省略せず読む。timezone/不正行/空台帳/未来時刻を明示処理し、stale閾値判定を変えない。snapshot利用時はsource+WAL/SHM相当の全入力identityが一致すること |
| pre-commit self_sync | commit-hash/内容hash fast path + staged snapshot単一pass | 6.37秒→0.10秒以下（hook非変更commit） | `scripts/hooks/*`または`.githooks/*` staged時、installed/source unreadable時、hash/cmp不一致時は必ずfull syncへfail-closed。fast pathは「同期不要の証明」でのみ選ぶ |
| skill refs | checked-at timestamp群を単一gitpassへbatch統合 + persistent `cat-file --batch` + immutable resultのみext4 atomic snapshot | 120秒超→3秒以下（37 skill warm）、cold 15秒以下 | 全37 skill/全参照を縮小しない。cache keyはgate本体、全SKILL bytes、全参照script bytes、verified state、repo HEAD/checked-at集合を含む。不明timestamp/欠損blobはPASSへ倒さず従来判定へfallback |
| gunshi precheck | report commit-hash優先pathを全PREへ展開 + numstat単一gitpass共有 + legacy全履歴grepに件数/時間上限 | 24.97秒→3秒以下（hashあり）、fallback 6秒以下 | report hashが対象repoに存在し、報告filesとcommit差分が一致する時だけ狭域pathを採用。hash不在・別repo・浅いcloneはWARNで消さずbounded fallback。上限到達をPASS扱いせずBLOCK/WARNとして可視化 |

方式別の期待効果は、外部process数をN→1、全履歴走査数を対象数N→最大1、9pの反復random readをatomic ext4 snapshot readへ置換することに由来する。目標秒数は後続cmdのbinary thresholdであり、達成しなければ方式採用を完了扱いしない。

## §5 実装順序と後続cmd境界

1. pre-commit self_sync: 無変更commit fast pathを独立fixtureで検証し、hook変更/installed欠損/linked worktree/異常終了の4境界を敵対試験する。
2. test health: 現行Python parseについて8,195行fixtureで旧判定との結果一致と0.5秒以下を測る。
3. skill refs: timestamp集合を一括解決する単一gitpass adapterを追加し、既存`cat-file --batch`とcache identityへ接続する。37 skill全件を検証対象とし縮小しない。
4. gunshi precheck: 全PRE consumerをhash由来batchへ接続し、hash欠落fallbackにtimeout/件数上限と非PASS出口を付ける。
5. 最終checkpoint: 同一固定HEAD・同一入力で旧/新の判定差分0件、SKIP 0、各目標秒数達成を確認する。

本cmdではコード・gate・hook・testを変更しない。後続実装cmdのscopeは上記4経路および既存contract testの更新に限定し、新規cache daemon、別ledger、検証対象のサンプリング、パラメータ空間縮小は対象外とする。

## §6 二値受入基準

- 4ホットスポットのbaseline・根因・行番号が4/4揃う。
- 既存2資産について各ホットスポットの採用/不採用/条件付き採用が4/4揃い、新規cache機構を提案していない。
- To-Be割当、目標秒数、真陽性境界条件が4/4揃う。
- 実装変更が0ファイルであり、後続cmdの実装scopeが明示される。

## §7 因果リンク

- `[[cmd_4112]]`
- `[[WSL2_mntc_subprocess反復fork_大履歴gitwalk]]`
- `[[利他調査で制御面4経路の同一病理確定]]`
- `[[既存資産横展開のas-is-tobe設計書cmd_4112]]`
- 実ファイル: `docs/research/control-plane-fork-gitwalk-countermeasure-asis-tobe_20260721.md`
