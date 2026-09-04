# X 投稿パイプライン prompt/生成器 変更記録

殿指示 2026-09-04 18:55 §19: 実装が動いたら細かい違和感で毎日 system prompt を変えない。変更は理由付きでここに記録する。大きな方針変更は本人が実際に使って明確なズレを感じた時だけ。

| 日時 | 対象 | 変更 | 理由(殿の言葉) |
|---|---|---|---|
| 2026-09-04 14:38 | system_prompt v5→v5.1 | conversation gap/fact≠completeness/説明しすぎ禁止/Fact・Voice 分離 | 殿『少し荒い方が隙が出来てプラス』 |
| 2026-09-04 17:47 | x_round5_gen.py | 記事本文入力を廃止、neta_ledger 必須(rc=2) | 殿『記事の抜粋、使えるネタが 0』 |
| 2026-09-04 18:29 | x_claim_gen.py 新設 | claim_bank 1 行→Short、記事本文を渡さない、数字 fail-close | 殿『俺が何もしなくても無限に生成し続けるから意味がある』 |
| 2026-09-04 18:55 | x_claim_gen.py / claim_bank.yaml / slot_calendar v5 | 必須 4 項(belief/claim/why/audience)欠落は SKIP、`--format long`(claim→疑い→検証→数字→結論)、slot instruction に外部 Voice 移植禁止、18:30 の Series 連続を解除 | 殿『記事から投稿を作るな。ネタから投稿を作れ。外部バズから本人を作るな』 |

system prompt 本体(v5.1)は 18:55 で変更していない。
