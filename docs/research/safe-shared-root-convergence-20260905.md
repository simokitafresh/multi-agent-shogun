# Shared root convergence D0 — 2026-09-05

## 結論

`safe_shared_main_ff.sh` の停止循環は単一原因ではなかった。家老の本番再走で、公開済みsupersetの誤BLOCK、非対象dirtyの旧snapshot上書き、Git `index.lock` 一時競合、C2a側の実行bit誤判定を順に検出し、全てoriginへ反映した。

## 根因と修正

| 根因 | 修正 | 二値防御 |
|---|---|---|
| originがローカル変更を包含してさらに安全修正を持つと、最終blob不一致だけでBLOCK | `git cherry` のpatch同値、またはorigin履歴の厳格な `Safe-Shared-Main-Equivalent-Source: <40hex>` を連続first-parent範囲だけ認証 | 未知SHA・非連続markerはBLOCK |
| 全unstaged pathを退避・復元し、並行runtime writerの新値を旧snapshotで上書き | indexだけtargetへ更新し、worktreeは変更clean pathだけmaterialize。unstaged overlapと非対象dirtyには触れない | read-tree直後の別writer更新を保持 |
| publisherとsafe helperのGit index操作が一時競合 | `index.lock` 文字列に限定した最大5秒の有界再試行 | 他エラーは即BLOCK、恒久lockは有界FAIL |
| mode 100644のhelperをpublisherが`-x`で拒否 | `bash`起動契約に合わせ`-r`で判定 | publisher 23件を含む回帰検証 |
| `publisher.sh sync_root` がSHAと文字列`origin/main`を比較 | 入口で`${tip}^{commit}`を解決し、SHA同士でpostsync検証 | symbolic tip fixture |

## 計測

- safe helper敵対fixture: 35/35 PASS、SKIP 0。
- safe helper + publisher: 59/59 PASS、SKIP 0。
- honest FAIL no-code identity補強: 52/52 PASS、SKIP 0。欠落・空・未知resultはfail-closed。
- 本番root: ローカルsource commitをisolated republish後、diverged同期PASS。直後の二回目は`already_contains_target` PASS。
- dirty保全: 同期前後のstatus/worktree/index fingerprint一致を確認。並行runtime更新は旧snapshotへ戻さないfixtureを追加。

## 因果

`[[shared_root_divergence]] -> [[published_superset_false_block]] -> [[equivalent_source_contract]] -> [[changed_path_only_materialization]] -> [[bounded_index_lock_retry]]`

関連実装: `scripts/safe_shared_main_ff.sh`, `scripts/publisher_c2a_merge.sh`, `scripts/publisher.sh`。
