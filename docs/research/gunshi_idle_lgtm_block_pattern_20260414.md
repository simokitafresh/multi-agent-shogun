# LGTM→BLOCK パターン分析 (cmd_1900)

軍師idle自走 Step 1→5。2026-04-14。

## 事象

cmd_1900 hayate報告に対し軍師LGTM ��� gate_report_format.sh BLOCK (binary_checks_fail)。

## 因果鎖

```
忍者verdict=FAIL(AC3未達: mr14体各1月不一致) + binary_checks result:no(AC3/commit)
→ 軍師がreport品質OKとしてLGTM判定(report内容は正確・正直)
→ しかしgate_prediction:BLOCKを付記せず(T1違反)
→ gate_report_format.sh機械的検査でbinary_checks_fail BLOCK
→ 家老workaround発生(verdict_override)
```

## 見落とし観点

T1(GATEシミュレーション)。review_logヘッダL24の原理を適用すべきだった。cmd_1897と同構造。

## 根因

2層の問題:
1. **軍師レベル**: LGTMでgate_prediction:BLOCKを予測しなかった(T1再発)
2. **インフラレベル**: GP-190(no_commit自動検出+commit check waive)未実装のため、commit禁止cmdでもcommit checkが自動注入される構造

## verdict_override 全8件のパターン

| パターン | 件数 | 比率 | GP |
|----------|------|------|-----|
| commit check不適切 | 5件 | 62.5% | GP-190(karo_sent) |
| AC文面が実態と乖離 | 2件 | 25% | — |
| データ時差 | 1件 | 12.5% | — |

## 対策

1. review_logヘッダL25追加: `verdict=FAIL報告にLGTM→gate_prediction:BLOCK必須`
2. GP-190実装後: commit check起因のverdict_override 62.5%が構造的に排除される
3. accuracy影響: BLOCK 4件目(1130件中, 99.6%→99.5%は変わらず)

## 複利の問い

review_logヘッダ原理を毎レビューで読む=正の複利(全レビューの品質底上げ)。
GP-190実装=正の複利(verdict_override 62.5%排除)。
