# セマンティック監査: cmd_2621変更(stale alert gates)
<!-- date: 2026-05-10 | auditor: gunshi | scope: scripts/ 3ファイル -->

## 対象

| ファイル | 変更内容 |
|---------|---------|
| scripts/deploy_task.sh | FILL_THIS→空文字列+コメント統一 |
| scripts/gates/gate_shogun_startup.sh | stale insight/GP proposal滞留検出+startup連続出現BLOCK |
| scripts/gates/gate_vercel_phase.sh | broken ref検出時の類似ファイル候補提案(Level5) |

## 結果サマリ

| カテゴリ | 検出数 | P0 | P1 | P2 | P3 | 真の問題 |
|---------|--------|----|----|----|----|---------|
| silent_failure | 7 | 0 | 4 | 1 | 2 | 0(全件設計意図) |
| state_transition | 5 | 0 | 2 | 3 | 0 | 0(全件偽陽性) |
| race_condition | 2 | 0 | 0 | 2 | 0 | 0(単一実行) |
| implicit_assumption | 1 | 0 | 0 | 1 | 0 | 0(テスト検証済) |
| **合計** | **15** | 0 | 6 | 7 | 2 | **0** |

## P1判定の峻別

### `2>/dev/null || true` パターン (gate_shogun_startup.sh L393,L677)
- 検出: Python実行失敗時にALERT未検出
- 判定: **偽陽性(設計意図)**。gate startup全体を止めないための安全設計
- 改善余地: stderrにログ出力すればデバッグ容易性向上(P3レベル)

### BLOCK後の復帰経路なし (gate_shogun_startup.sh L1490-1493)
- 検出: overall="BLOCK"からの遷移ロジック不在
- 判定: **偽陽性**。ALERTが解消されればstreak条件(N回連続)が崩れ自然復帰

### pending deadlock (gate_shogun_startup.sh L426,L738)
- 検出: pending insight/GP proposalの自動状態遷移なし
- 判定: **偽陽性(運用設計)**。軍師/将軍が手動resolve。本セッションで9件→0件resolve実績

## P2判定の峻別

### FILL_THIS→"" regex (deploy_task.sh L1962-1969)
- 判定: **偽陽性**。cmd_karo_ci_fix_fill_this_tests CLEAR(テスト検証済み)

### 並行アクセス (gate_shogun_startup.sh L1456-1533)
- 判定: **偽陽性**。gate_shogun_startup.shは将軍のみが1プロセスで実行

### find候補リスト (gate_vercel_phase.sh L113-115)
- 判定: **偽陽性**。情報提供用(BROKEN_DETAILS表示)で実害なし

## 副作用スキャン(cmd_2613-2620 残り7ファイル)

| # | ファイル | 深刻度 | 内容 | 判定 |
|---|---------|--------|------|------|
| 1 | cmd_save.sh L2962-2966 | P2 | HIT_GS=false条件で偵察+grid_search偽陰性 | 偽陽性(偵察=CSV参照のみ、設計意図) |
| 2 | gate_gunshi_cs_checklist.sh L285 | P2 | GATE待機中エントリのcold判定混入 | 偽陽性(finding_categoriesはレビュー時確定、GATE無関係) |
| 3 | semantic_search.sh L206-212 | P3 | キャッシュtmpファイルcleanup漏れ | 既存カバー(ninja_monitor lock_cleanup) |

結論: **副作用なし。全3件偽陽性/既存カバー**
