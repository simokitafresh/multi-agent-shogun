# Review-friction implementation latency retro

Date: 2026-07-20  
Task: `cmd_karo_retro_review_impl_latency_202607202122_normal`

## Phase ledger

| phase | wall_ms | BLOCK | owner wait_ms | retries |
|---|---:|---:|---:|---:|
| task/inbox load + status transition | 5,500 | 0 | 0 | 0 |
| implementation (opsim + report-deny 3 copies) | 300 | 0 | 0 | 0 |
| syntax + initial hook suite | 4,500 | 0 | 0 | 0 |
| boundary experiments and quoted-target correction | 15,100 | 0 | 0 | 2 |
| affected/unit single-flight attempts | 50,000 | 0 | 25,000 | 2 |
| three scope commits/precommit | 44,000 | 1 | 0 | 4 |
| report batch + gate/diagnosis | 54,000 | 4 | 0 | 4 |
| shared `gunshi_log_append.sh` owner convergence | 188,000 | 1 | 188,000 | 1 |
| generated hook LG058 owner wait before task replacement | 107,000 | 1 | 107,000 | 1 |

全9 phase計測済み、未計測0。合計概算468,400ms、BLOCK 7、owner待ち295,000ms、再試行14。支配項はowner待ち63.0%、report/commit/test pipeline 31.6%、実装0.1%。

## Top-three isolated experiments

| candidate | current (10 runs) | candidate (10 runs) | quality comparison | result |
|---|---:|---:|---|---|
| path dirty → own-hunk provenance | `git status` 9,851ms, BLOCK 10/10 | own patch reverse-check 3,451ms, BLOCK 0/10 | own committed hunk存在をbyte patchで確認し、他owner hunkを許可。自hunk欠落はfail-closed | **fastest/highest impact** |
| three commit receipts → immutable fingerprint receipt | 3 commit existence checks 21,652ms/30 checks | 3 files SHA-256 649ms/30 hashes | 対象byteを固定し、hash不一致なら再検証。品質差0 | adopt |
| repeated full hook suite → fingerprint-bound receipt reuse | full suite 4,500ms/run (104/104 PASS) | three-file SHA receipt 64.9ms/run | source hash一致時のみ既存104/104 receiptを再利用。不一致はfull suite | adopt |

最速かつ全体寄与最大は **path単位dirty BLOCKをcommit/hunk provenance判定へ置換**。直接比較で10反復6,400ms短縮(65.0%)に加え、今回のowner待ち295,000msとgate再試行2回を除去できる。parent/approval/write防止および他owner hunk自体は変更しないため品質差分0。

## Infra bug report

共有worktreeでpath全体をdirty判定すると、報告commitに自分のhunkが完全収束していても別ownerの非重複hunkでBLOCKする。これは品質欠陥ではなくownership attribution欠落である。候補は「報告commitに申告hunkが存在する」「残存diffが申告hunkと非重複」の二値確認へ変更し、重複時だけBLOCKすること。

## Binary result

- AC1: 9/9 phase、wall/BLOCK/owner wait/retry全項目記録、未計測0: yes
- AC2: 上位3候補を10反復で隔離比較し、品質差0の最速候補を特定: yes
