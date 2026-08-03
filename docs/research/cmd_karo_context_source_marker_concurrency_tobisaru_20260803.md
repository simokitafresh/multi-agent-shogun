# context source_commit marker concurrency recon (2026-08-03)

## 結論

`context/dm-signal-research.md` に対する本日対象3 source commit は `3222293887bdbc9c23b8a2090a0cf3ced16bc5ae`、`faf45ac6f5fc70c44e8a0e5301da751e97780771`、`cc4882758a985d65f1fec16c55462e4b7523ada7`。GATEが同時に認識できたのは3件中1件、後続更新で認識不能・消失したものは2件である。したがって「3件を安全に設定済み」という前提との差は **認識 -2件**。競合時だけの事故ではなく、逐次実行でも必ず単一化する仕様である。

## AC1 — 履歴再計数

| 時刻/infra commit | 設定されたsource commit | 現物とGATEから見える状態 |
|---|---|---|
| 15:07 `c2a528c7…` | `322229388…` | 先頭markerとして1/1認識。その後15:26更新で消失 |
| 15:26 `03276e021…` | `faf45ac6…` | `322229…`を置換し1/2のみ認識 |
| 15:51 `b7477765…` | `cc488275…` | `cc488…`は末尾側へ追加され、先頭5行readerから不可視。`faf45…`のみ1/3認識 |
| 15:54 `4cec33fc…` | `cc488275…`を正規化 | `faf45…`と末尾`cc488…`を除去し、先頭へ`cc488…`を単一挿入。1/3認識、2/3消失 |

一次証跡は `git log -p -- context/dm-signal-research.md`。現在の履歴でも `c2a528c7` の `322229…`、`03276e02` の `faf45…`、`b7477765` の `cc488…`、`4cec33fc` の2 marker削除と単一marker挿入を再構成できる。現行ファイルも `source_commit` は1行だけである。

## AC2 — 読書き契約と根因

### writer

- `scripts/context_source_commit_set.sh:79-83`: ファイル全体をlockなしで読み、今回commitのmarkerを1行生成する。
- 同 `:84-88`: 正規表現に一致する **全source markerを無条件削除**。逐次3 writerでも先行2件は仕様通り消える。
- 同 `:100-105`: `last_updated`直後へ今回markerを1行だけ挿入する。
- 同 `:107-113`: temp+`os.replace`は破損防止のatomic publishに過ぎない。read-modify-write全体を`flock`していないため、2 writerは同じ旧世代を読み、最後のreplaceがmarker・reason・evidence・last_updatedを丸ごと上書きする。

### readers / callers

- `scripts/context_freshness_check.sh:228,334-347`: regexは複数にmatch可能だが、先頭5行を走査して最初の1件でreturnするscalar契約。
- `scripts/gates/gate_context_freshness.sh:100-121`: `head -n 5 | ... | head -n 1`で1 hashだけ取得し、そのhashとalert latestの祖先性だけを判定する。
- `scripts/cmd_complete_gate.sh:6921-6954`: 複数report commitは連想配列へ保持する一方、後段のcontext境界は上記scalar readerへ流れる。複数独立GATEの要求hashをmarker identityへ結びつけるkeyがない。
- 既存 `tests/unit/test_context_source_commit_set.bats:76-81` はduplicateを1件へ潰すことを正解として固定し、競合喪失を防ぐtestは0件。

### 最小変更対象

1. `scripts/context_source_commit_set.sh`: markerを `(project, source_commit)` の集合として保持し、同一hashのみdedupeする。対象context専用lockを取り、lock内でread→merge→temp fsync→replaceする。全削除は禁止。
2. `scripts/context_freshness_check.sh`: `source_commit_marker -> source_commit_markers` として先頭5行内の全hashを返し、要求commitごとに満たすmarkerを選ぶ。
3. `scripts/gates/gate_context_freshness.sh`: `head -1`を廃止し、alert latestを閉じるhashが集合中に1件以上あることを判定する。
4. `scripts/cmd_complete_gate.sh`: `_reported_commit_hashes` の各要求commitについて独立にclosure結果を集約し、1件でも未解消ならBLOCKする。
5. tests: `tests/unit/test_context_source_commit_set.bats`、`tests/unit/test_context_freshness_check.bats`、`tests/unit/test_gate_context_freshness.bats`、`tests/unit/test_cmd_complete_gate_context_freshness_block.bats`。

race条件は「同一context path、異なる有効ancestor commit、writer A/Bが双方read完了後にreplace」。atomic renameだけではlost updateを防げない。lock scopeはcontext path単位とし、異なるcontext間は並行性を維持する。

## AC3 — 二値fixture案

既存Batsの一時git repo fixtureを拡張し、直列3 commitと2並行writerを作る。並行fixtureはwriter直前にtest-only barrierを置き、A/B双方が同一旧世代を読んだことを保証してから解放する。続けて独立GATE A/Bを各要求hashで実行する。

| 二値check | 現行 | 修正後期待 |
|---|---:|---:|
| 直列3 writer後に3 marker保持 | FAIL (1/3) | PASS (3/3) |
| 並行A/B後に両marker保持 | FAIL (1/2) | PASS (2/2) |
| 独立GATE AがA hashを認識 | writer順次第でFAIL | PASS |
| 独立GATE BがB hashを認識 | writer順次第でFAIL | PASS |

現行の確定FAILは少なくとも2/4（保持test 2件）。GATE A/Bはlast-writerにより片方だけPASSするため、fixture全体では **FAIL 3/4・PASS 1/4**。修正後期待は **PASS 4/4、FAIL 0、SKIP 0**。未解消条件は (a) marker集合のGC境界、(b) 複数projectが同一contextを共有する場合のidentity、(c) test barrier注入方式の3件であり、実装着手判定は **BLOCK**。

## 因果

`[[複数GATE並行完了]] -> [[scalar source_commit + lockなし全削除RMW]] -> [[2/3境界消失・独立GATE誤BLOCK]]`
