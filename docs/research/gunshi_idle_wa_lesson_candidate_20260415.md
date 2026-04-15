# GP-195 SG-PRE12 lesson_candidate自動WARN設計

## 問題
lesson_candidate(found:true)がある報告→gate draft_lessons BLOCK→軍師がgate_prediction: CLEARを出す(意志依存)→4回見落とし(cmd_1811/1814/1909/1911)

## 因果推論
```
lesson_candidate有
→ gate_report_format draft_lessons BLOCKリスク
→ 軍師gate_prediction:CLEAR設定(意志依存)
→ BLOCK発生→家老workaround
→ ×4回再発(意志依存は機能しない=Phase 4)
```

## 解決
gate_gunshi_report_precheck_engine.py + gate_gunshi_report_precheck.sh にSG-PRE12追加。

### engine変更
- `HAS_LESSON_CANDIDATE`変数追加
- lesson_candidateがdict形式の場合`found: true`のみ検出(found:false→PASSにする)
- LESSONS_USEFUL_MSGのメッセージ修正(「BLOCKリスクなし」→「BLOCKリスクあり」)

### shell変更
- SG-PRE12セクション追加(SG-PRE11の後)
- HAS_LESSON_CANDIDATE=1 → ★★★ WARN表示(gate_prediction: WARN/BLOCK必須)

## 検証結果
| テストケース | 期待 | 結果 |
|---|---|---|
| kagemaru_cmd_1909 (found:false) | PASS | PASS |
| hanzo_cmd_1922 (found:false) | PASS | PASS |
| hanzo_cmd_1125 (found:true) | WARN | WARN |
| 既存SG-PRE9テスト3件 | PASS | PASS (副作用なし) |

## S0 Self-Change Review
- S0-1 Assumptions: OK (engine L163でlesson_candidate既読、grep確認)
- S0-2 Numbers: OK (4見落とし実績、3テストケース検証)
- S0-3 Simulation: OK (殿原則衝突なし。自動化×強制の正当適用)
- S0-4 Premortem: 3 FM (型判定/変数名/既存テスト破壊) all mitigated by testing
- S0-5 Verification: OK (3レポート実測 + bats 3/3 PASS)
- S0-6 North Star: OK (Phase 4 意志依存→環境埋込み)

## Defense Level: 5 (事前コンテキスト提供)
review_logヘッダL38更新済み。
