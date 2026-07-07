# LG048自動化: SG-PRE31 N×M意味検算リマインド
<!-- generated: 2026-07-06T20:45:00+09:00 by gunshi idle analysis -->

## 背景

LG048(きれいな数値一致は意味検算のサイン)はlesson_gunshi唯一の`automated:false`教訓だった。
cmd_3700で306=102×3を数値一致だけでLGTMし、将軍の疑義で非リバランス月event混入が発覚した事故が起源。

startup gateの教訓/clear耐久率が45/46(97%)で1件だけLevel 2(意志依存)が残存していた。

## 分析

LG048の内容: 「N×Mぴったりの数値は仕様上の分類(PF種別/trigger/月等)と照合し意味検算せよ」。
report reviewの数値再計算観点で軍師が意識的に実施するルール(Level 2=意志依存)だった。

deepdive Phase 4: 意志依存は/clear後に消える。自動化×強制で環境に埋め込むべき。

## 実装

gate_gunshi_report_precheck.shにSG-PRE31を追加:
- 報告YAMLのresultブロックから数値(>=3)を抽出
- N×M=Cの関係が見つかったらINFO表示
- 「意味検算せよ: 全件一律の数値は過剰集約や分類漏れの兆候」とリマインド

閾値設計: 1,2は偽陽性過多のため除外。3以上を対象。INFOレベル(BLOCK/FAILではない)で低コスト。

## テスト結果

| テスト | 結果 |
|--------|------|
| 102×3=306検出 | PASS(INFO表示) |
| N×M不成立(17,23,40) | PASS(N×M一致パターンなし) |
| 数値3個未満 | PASS(対象外) |
| resultブロックなし | PASS(SKIP) |
| 50×20=1000検出 | PASS(INFO表示) |
| 既存SG-PRE30テスト8件 | 全PASS(回帰なし) |

## 効果

| 指標 | 修正前 | 修正後 |
|------|--------|--------|
| LG048 automated | false | true |
| enforcement_level | 2 | 3 |
| /clear耐久率 | 45/46(97%) | 46/46(100%) |

commit: fc32f7e7c

## 因果リンク

- origin: [[LG048]] -> [[cmd_3700_意味検算見落とし]] -> [[SG-PRE31自動化]]
- deepdive Phase 4(自動化×強制) + Phase 9(ラルフループ)の軍師版実践
