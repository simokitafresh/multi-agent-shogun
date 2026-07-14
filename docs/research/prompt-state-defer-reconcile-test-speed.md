# prompt_state defer reconcile テスト速度

## 結論

`tests/unit/test_prompt_state_defer_reconcile.bats` は、対象外の三層検索preflightを各ケースで起動していた。共通fixtureで `PROMPT_STATE_PREFLIGHT_CMD=/bin/true` を設定し、3ケースと全期待値を維持したまま先送り突合だけを計測する。

## 因果リンク

- 実装対象: [[test_prompt_state_defer_reconcile.bats]]
- 被テスト本体: [[prompt_state_inject.sh]]
- 計測経路: [[run_timed_bats.sh]]
- 原則: [[training-cycle]]

## 改善候補3件

1. 最高インパクト: 共通fixtureで対象外preflightを無害化する。被テスト本体は `PROMPT_STATE_PREFLIGHT_CMD` を明示的な差替え口として持ち、テストは先送り突合のみを検証するため。
2. `run_hook` の標準エラーを常時破棄せず、失敗時に診断できる捕捉方法へ変える。現状の `2>/dev/null` は異常原因を隠す。
3. 3ケースでhookプロセスを個別起動する構造を、被テスト本体の関数分離後に直接関数テストへ変える。現時点では本番入口の統合契約を守るため未実装。

## 検証契約

`bash scripts/run_timed_bats.sh /mnt/c/tools/multi-agent-shogun/tests/unit/test_prompt_state_defer_reconcile.bats` を使い、PASS 3件、FAIL 0件、SKIP 0件および台帳の変更前後wall秒を確認する。
