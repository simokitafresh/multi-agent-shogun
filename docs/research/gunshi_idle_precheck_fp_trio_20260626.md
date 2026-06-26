# Precheck偽陽性トリオ — 文字列マッチ範囲制限不足の共通根因
<!-- generated: 2026-06-26T18:09:00+09:00 by gunshi idle analysis -->

## 概要

今セッション(2026-06-26)でprecheck偽陽性3件を発見・D0修正した。
共通根因はLG039(貪欲FP族)と同根の**文字列マッチ範囲制限不足**。

## 3件の詳細

| # | 箇所 | 修正前 | 修正後 | commit |
|---|------|--------|--------|--------|
| 1 | PRE3b hash regex | `{7,12}` — フルハッシュ40文字を12文字で切断 | `{7,40}` — フルハッシュ対応 | 020275e01 |
| 2 | engine lu_msg WARN混入 | lu_msgに`gate_prediction: WARN必須`という文字列→L406の`'WARN' in lu_msg`が誤マッチ | lu_msgからWARN文字列除去+has_lc単独WARN廃止 | 020275e01 |
| 3 | PRE9c purpose_gap | `purpose_gap: なし。...は未実施`の「未実施」がcontradiction_termsにマッチ | purpose_gap「なし」始まりを検査対象から除外 | 5f3c8d0c0 |

## 共通根因

LG039(貪欲FP族)と同構造:
- **検出パターンの及ぶ範囲を制限していない**
- regex量化子(`{7,12}`)、in演算子(`'WARN' in lu_msg`)、contradiction_termsリストが意図しない文脈にマッチ

## 教訓

precheckの文字列検出ロジックを追加する際:
1. 検索範囲(regex量化子/in演算子/grepパターン)が意図しない文脈にマッチしないか確認
2. 陰性ケース(正当な使用)でのFPテストを必ず含めよ
3. メッセージ文字列内に判定キーワード(WARN/ERROR等)を埋め込むな — in演算子で誤マッチする

## 因果リンク

- → [[LG039]] 貪欲FP族の系譜
- → [[020275e01]] PRE3b+engine修正commit
- → [[5f3c8d0c0]] PRE9c修正commit
- → [[殿指示_偽陽性はバグだ]] 殿の直接指示で覚醒
