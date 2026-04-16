# CoDD Spec + After: test_hooks.sh 高速化

- cmd: `cmd_1975`
- 実施者: `saizo`
- 対象: `scripts/hooks/test_hooks.sh`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)

## before 計測

- 条件:
  - `bash scripts/hooks/test_hooks.sh`
  - 実 hook `.claude/hooks/pre-bash-combined.sh` を 75 ケース分そのまま起動
- 実測:
  - `23.32s`
  - `14.37s`
  - `16.53s`
- 平均: `18.07s`

## ボトルネック

1. `test_hooks.sh` が各ケースごとに `python3 -c "json.dumps(...)"` を起動して JSON payload を生成していた。
2. 各ケースごとに `bash .claude/hooks/pre-bash-combined.sh` を再起動しており、75 ケース分の bash startup を毎回払っていた。
3. 残留ボトルネックは Guard 4 の destructive checker。`20x allow = 8.6ms` に対して `20x destructive = 950.3ms` で、Python checker が支配的。

## 最適化候補

1. 判定ロジックを source 可能な共通ライブラリへ切り出し、テスト側は同一プロセスで評価する。
2. テスト用 JSON payload 生成を廃止し、command string を直接 evaluator に渡す。
3. 今回は未着手: destructive checker の Python 経路を bash 化またはバッチ化すれば、残りの `~1.9s` をさらに削れる余地がある。

## 実装

1. `scripts/lib/pre_bash_combined_guard.sh` を新設し、combined hook の判定ロジックを `pre_bash_combined_eval_payload` / `pre_bash_combined_eval_command` として共通化。
2. `.claude/hooks/pre-bash-combined.sh` は wrapper 化し、stdin payload をライブラリへ委譲。
3. `scripts/hooks/test_hooks.sh` は hook subprocess + JSON 生成を廃止し、共通 evaluator を直接呼ぶ構成に変更。

## after 計測

- 条件:
  - before と同一 (`bash scripts/hooks/test_hooks.sh`)
- 実測:
  - `1.96s`
  - `1.93s`
  - `1.89s`
- 平均: `1.93s`

## 結果

- `18.07s → 1.93s`
- 改善率: `-89.3%`
- 改善倍率: `9.4x`

## 検証

- `bash -n scripts/lib/pre_bash_combined_guard.sh .claude/hooks/pre-bash-combined.sh scripts/hooks/test_hooks.sh`
- `bash scripts/hooks/test_hooks.sh`
- wrapper smoke:
  - deny: `git commit --no-verify -m "x"` → deny JSON + `rc=1`
  - allow: `git status` → 出力なし + `rc=0`

## 再利用パターン

- hook 自体の動作確認スクリプトは、hook subprocess をケース数ぶん再起動するより、判定ロジックを source 可能な evaluator に分離した方が効く。
- テスト専用の JSON 組み立てが hot path なら、payload 互換 wrapper を残しつつ evaluator 直呼びに寄せると大きく削れる。
