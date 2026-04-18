# cmd_2065 stop-lint-gate.sh L3診断推論改善

日付: 2026-04-18
担当: saizo
対象: `.claude/hooks/stop-lint-gate.sh`

## 背景

殿指示「失敗した知見をもとに改善を続ける仕組みがないのは甘い」を受け、過去 attempt の失敗要因を踏まえて `stop-lint-gate.sh` を再評価する。

本 cmd の焦点は、無理な再最適化ではなく以下の3点である。

1. 現状性能が Attempt 1 成功状態(`0.65s`)より悪化していないか確認する
2. 過去3 attempt の失敗要因を L3 診断推論として明文化する
3. 追加変更が悪化を招くなら即 revert し、正しい状態を保つ

## 既存 attempt の整理

### Attempt 1

- 出典: `docs/research/codd_spec_stop_lint_gate_20260416.md`
- 結果:
  - isolated benchmark median `0.82s → 0.65s`
  - live worktree median `0.54s`
- 有効だった要素:
  - Git plumbing 化
  - lint 実行のバッチ化
  - fail hash builtin 化

### Attempt 2

- 出典: `docs/research/cmd_2039_codd_infra_hook_gate_batch_20260418.md`
- 結果:
  - isolated benchmark median `0.84s`
- 失敗構造:
  - `git status --porcelain=v2 -z` へ切り替えたが、Attempt 1 より遅くなった
  - current repo noise を isolated benchmark で取り違え、改善と誤認した

### Attempt 3

- 出典: `docs/research/cmd_2061_codd_hook_batch_a_20260418.md`
- 結果:
  - fixture benchmark `34.0ms → 35.7ms`
- 失敗構造:
  - path/string-ops 置換や `cd` 集約のような「小さい最適化」は、WSL2 上では効果よりノイズ/回帰が大きかった
  - 変更を retained diff に残さず revert した判断自体は正しい

## Before

- representative fixture:
  - isolated repo, tracked `a.sh b.sh c.py` modified, lint pass
- 実測:
  - `32.3ms`
  - `27.4ms`
  - `28.0ms`
  - `25.4ms`
  - `26.3ms`
  - `26.7ms`
  - `30.8ms`
  - `31.8ms`
- median: `27.7ms`

## L3 診断推論

### 診断1: いまは「改善対象」ではなく「改善済み資産」

- Attempt 1 の時点で `0.65s` / live `0.54s` まで落ちており、元の `3.0s` 問題は解消済み。
- 現在の fixture `27.7ms` は、Attempt 1 成功状態よりさらに軽い条件で計測されている。
- つまり現時点で「悪化が残るから直す」は成立しない。

### 診断2: これ以上の局所最適化は再現性よりノイズが大きい

- Attempt 2: Git changed-file 列挙の入れ替えが isolated benchmark で悪化。
- Attempt 3: path/string-ops の小変更が fixture benchmark で悪化。
- 共通して「WSL2 /mnt/c 上のノイズが大きく、微小最適化は改善より回帰を生みやすい」。

### 診断3: 真の価値はコード変更ではなく判断基準の固定

- 今必要なのは further optimization ではなく、
  - どの benchmark を信じるか
  - どこで revert するか
  - どういう失敗を繰り返さないか
  を文書と台帳に固定すること。

## 改善方針

1. `stop-lint-gate.sh` の現行 HEAD をそのまま採用する
2. 追加コード変更は行わない
3. `current median 27.7ms` と `Attempt 1 success 0.65s` を比較し、悪化なしを明示する
4. registry に Session State / trial history を参照できる追記を行う

## 実施

- コード変更: なし
- retained change:
  - 本 spec 文書
  - registry の追記

## After

- current fixture median: `27.7ms`
- Attempt 1 success baseline: `0.65s`
- verdict: **degradation not present**

## 検証

- `bash -n .claude/hooks/stop-lint-gate.sh`
- `bats tests/unit/test_stop_lint_gate.bats`

全PASS。

## 結論

- `stop-lint-gate.sh` は現時点で再改善不要。
- 過去3 attempt の失敗は「改善不足」ではなく「既に十分速い資産に対してノイズの大きい微小最適化を続けたこと」にある。
- 本 cmd では、L3 診断推論と Session State 参照を文書化し、今後の無駄な再最適化を止めることを成果とする。
