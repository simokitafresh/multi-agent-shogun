# report_field_set.sh binary_checks保護 FILLバイパス修正

## 概要
GP-053のbinary_checks保護がFILLプレースホルダも保護し、忍者のcheck文更新を阻害するバグを修正。

## 根因
- `report_field_set.sh` L843: `len(ex_check.strip()) > 5` で全check文を保護
- deploy_task.sh L1602: `"FILL: ACxの確認項目を記入"` を生成（5文字超）
- FILL文が保護対象 → 忍者が具体的check結果で上書き不可 → gate「プレースホルダ残存」BLOCK → DIVERGENT BLOCK

## 修正
L846に `if ex_check.strip().startswith('FILL'): continue` を追加。FILLパターンは保護スキップ。

## 検証
- TEST1: FILLプレースホルダが忍者check文で上書き → PASS
- TEST2: 非FILLの実check文は保護維持 → PASS

## 発見経緯
- cmd_2397影丸レビュー中に殿が指摘「インフラバグでは？」
- capture-pane分析 → DIVERGENT BLOCK + binary_checks保護メッセージ確認
- LG014(忍者ミスに見える問題はインフラ真因を疑え)の実例

## commit
65d1ee3a (kagemaru auto-commit含む)
