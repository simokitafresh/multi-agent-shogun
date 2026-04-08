# recalculate_fast.py Phase構成 + OPT-Eアーキテクチャ
<!-- cmd_286 | 2026-02-23 | ops.mdから移動 -->
<!-- 結論: 6Phase+OPT-E(Phase3.7)で signal_calc 1,724s→0.53s(3,786倍高速化) -->

## §6 recalculate_fast.py Phase別処理フロー

ファイル: `backend/app/jobs/recalculate_fast.py`
殿の制約: 全PF×全日を計算（差分計算・PF数削減・日数間引き禁止）

```
recalculate_history_fast()
│
├─ Phase0 (L694)  クリーンアップ
│   └─ _cleanup_before_recalculate(): DELETE(独立COMMIT)
│      ⚠ L038/L039: DELETE→INSERT間でOOM/redeployするとデータ消失
│
├─ Phase1 (L702)  データロード
│   └─ _load_all_prices(): 全銘柄の価格データをDBから一括ロード
│
├─ Phase1.5 (L740)  有効開始日決定
│   └─ 各PFの計算開始日を決定
│
├─ Phase2 (L827)  前処理 + MomentumCache初期化
│   └─ pivot + 全期間モメンタム事前計算。PriceCacheの構築
│
├─ Phase2.5 (L867)  MonthlyProductMomentumCache
│   └─ 月次プロダクトモメンタムのキャッシュ構築
│
├─ Phase3 (L903)  Pipeline モメンタムCache事前計算 (OPT-A)
│   └─ 全BBブロック×全ティッカーの事前計算
│
├─ Phase3.5 (L1166)  Pipeline block事前解決 (OPT-A)
│   └─ 各PFのpipeline_configからブロック設定を事前解決
│
├─ Phase3.7 (L1178)  ★OPT-E: Vectorizedシグナル事前計算
│   └─ _precompute_pipeline_signals()
│      全pipeline PFの全日付シグナルを1パスで事前計算→dictに格納
│      データ構造: Dict[str, Dict[date, str]] (L1185)
│      → Phase4ではO(1) dict lookupのみ
│      → miss時: 日次フォールバック→execute_pipeline_with_blocks (L1718-1738)
│
├─ Phase4 (L1508)  L2日次ループ（シグナル+パフォーマンス計算）
│   └─ 全日付×全PFをループ
│      OPT-E PF: Phase3.7のdict lookup (O(1))
│      Legacy PF: determine_signal_fast()
│      ボトルネック: trade_perf (58.7s) ← signal_calcは0.53sで脱落
│
├─ Phase4.5 (L1909)  月次リターン計算
│   └─ 月次リターンの集計・書込
│
├─ Phase5 (L1921)  L3 FoF再計算 (~89s)
│   └─ L2シグナルを集約→FoFシグナル+パフォーマンス計算
│
└─ Phase5 precompute (L1958)  プリコンピュートテーブル
    └─ パフォーマンスデータの事前計算テーブル生成
```

## §7 OPT-Eアーキテクチャ

### 概要

OPT-E = Phase3.7で全pipeline PFの全日付シグナルを**1パスで事前計算**し、Phase4では**O(1) dict lookup**で取得する最適化。signal_calc時間を**1,724s→0.53s（3,786倍高速化）**。

### 実装構造

```
Phase3.7: _precompute_pipeline_signals()
  ├─ 入力: pipeline PF一覧, 全日付リスト, momentum_cache
  ├─ 処理: 全PF×全日付でexecute_pipeline_with_blocks()を1回呼び
  ├─ 出力: vectorized_pipeline_signals: Dict[str, Dict[date, str]]
  │         key=portfolio_id, value={date: signal_string}
  └─ bisect: _dict_lookup_with_bisect (L509-523)
             target_date以前の直近日を検索(休日対応)

Phase4: dict lookup
  ├─ hit → O(1)でsignal取得
  └─ miss → 日次フォールバック: execute_pipeline_with_blocks (L1718-1738)
             ※91c04a4で追加(L045対応)
```

### バグ修正履歴

| Commit | 問題 | 修正 | 教訓 |
|--------|------|------|------|
| dc35b83 | OPT-E初期実装 | — | — |
| f452c23 | ReversalFilter方向逆転 | top_n降順→bottom_n昇順 | L045 |
| 151345c | bisectフォールバック消滅 | dict厳密一致→旧パスのbisect復元 | L045 |
| 91c04a4 | 112件signal消失 | Phase4にcontinue→日次フォールバック追加 | L045 |

### 112件signal消失(L045)

| 事象 | 原因 | 修正(91c04a4) |
|------|------|---------------|
| OPT-E後signal 112件減少 | Phase4 dict miss時`continue`→旧パスはSafeHaven/Terminalでsignal返却するため非等価 | continue→日次フォールバック(execute_pipeline_with_blocks) |

教訓: 最適化でskipするパスが旧ロジックと等価か必ず検証せよ

## §9 性能ベースライン

### 再計算性能推移

| 段階 | 全体 | signal_calc | 備考 |
|------|------|-------------|------|
| 初回ベースライン | 11,818s (3h17m) | — | — |
| OPT-A/D/F適用 | 2,397s (40m) | 2,007s | Phase3事前計算 |
| OPT-E適用 | 389s (6m30s) | 0.53s | **3,786倍高速化** |

### 現在のボトルネック (OPT-E後)

| 項目 | 時間 | 比率 |
|------|------|------|
| trade_perf | 58.7s | **新ボトルネック** |
| signal_calc | 0.53s | 脱落 |
| L3 FoF | ~89s | OPT-E対象外 |

### 注意事項

- ローカル→シンガポールDBでの再計算は197分（ネットワーク遅延支配的）(L041)
- 効果検証はRender上(DB同一サーバ)で行うべき
- フル計算を毎回待つな。2年テスト(2024-01-01〜)で計測→改善→再テストのサイクルを回せ
