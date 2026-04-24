# CoDD準備cmd AC3文言曖昧性分析

## 発見日
2026-04-24 gunshi idle自走 Step 5

## 観察
cmd_2244/2245/2246/2247の4本で同一AC構造:
- AC2: spec保存(docs/research/に新規ファイル作成)
- AC3: コード変更ゼロ。本cmdで新規変更したファイルがないこと

## 結果
| 忍者 | cmd | verdict | AC3解釈 |
|------|-----|---------|---------|
| kagemaru | cmd_2244 | PASS | 「コード変更」=ソースコード限定 |
| hanzo | cmd_2245 | PASS | 同上 |
| hayate | cmd_2246 | FAIL | 字面通り「新規変更ファイルなし」→spec作成と矛盾 |
| saizo | cmd_2247 | PASS | kagemaru同様 |

## 因果鎖
AC3「新規変更したファイルがないこと」→AC2「spec保存=新規ファイル作成」と矛盾→忍者の解釈分岐→verdict不統一→GATE BLOCK(hayate)

## 提案
AC3の文言を「ソースコード変更ゼロ(docs/research/新規作成は許可)」に修正。
「新規変更ファイル」が何を指すかの定義が必要。

## 複利の問い
10回繰返した場合: 同じ曖昧性で毎回1/4がFAIL→GATE BLOCK→家老workaround=負の複利。文言修正1回で以後全件PASS=正の複利。
