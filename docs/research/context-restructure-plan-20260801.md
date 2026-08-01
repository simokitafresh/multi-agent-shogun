# context再構築分割設計（2026-08-01）

結論: 残る500行超6ファイルは各見出しをsource lineで一意化し、下表の詳細正本へexactly-onceで割り当てる。実施は後続cmd。

| 対象 | source line | 見出し | 移設先 |
|---|---:|---|---|
| `context/senkyoku-log.md` | 1 | 戦局日誌 (Campaign Log) | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 4 | 2026-07-31 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 12 | 2026-07-18 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 19 | 2026-07-17 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 36 | 2026-07-16 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 49 | 2026-06-30 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 67 | 2026-06-29 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 92 | 2026-06-26 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 98 | 2026-06-21 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 106 | 2026-06-20 (session 2) | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 115 | 2026-06-16 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 124 | 2026-06-14 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 155 | 2026-05-21 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 171 | 2026-05-20 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 191 | 2026-05-19 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 253 | 2026-05-17 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 265 | 2026-05-16 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 291 | 2026-05-15 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 304 | 2026-05-12 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 330 | 2026-05-10〜11 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 346 | 2026-04-24 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 352 | 2026-04-20 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 359 | 2026-04-19 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 373 | 2026-04-18 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 379 | 2026-04-16 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 386 | 2026-03-28 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 429 | 2026-03-29 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 474 | 2026-03-27 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 500 | 2026-03-26 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 513 | 2026-03-25 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 524 | 2026-03-24 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 531 | 2026-03-23 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 553 | 2026-03-22 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 594 | 2026-03-21 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 618 | 2026-03-20 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 620 | Chain A: shutsujin HC事故 → 構造改革4件 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 633 | Chain B: 報告3層解像度の整備 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 643 | Chain C: 3層学習ループ構築 + インフラ強化 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 681 | 2026-03-21 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 704 | 2026-03-23 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 718 | 2026-03-24 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 729 | 2026-03-25 将軍自走最適化サイクル | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 736 | 2026-03-28 fullrecalculate最適化 + 知識循環分析 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 751 | 2026-03-29 Silent Fallback掃討 + Cash修正検証 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 765 | 2026-03-29 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 783 | 2026-03-30 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 904 | 2026-03-31 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 932 | 2026-04-01 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 972 | 2026-04-02 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 984 | 2026-04-03 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 990 | 2026-04-05 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1085 | 2026-04-27 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1107 | 2026-04-29 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1145 | 2026-05-10 (後半: cmd_2659-2666) | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1170 | 2026-05-12 セッション: 二重配備3層防御+起動手順強制化 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1181 | 2026-05-12 セッション2: 教訓品質改善+race condition解消 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1245 | 2026-05-16 | `docs/research/senkyoku-log-detail-01.md` |
| `context/senkyoku-log.md` | 1274 | 2026-05-27 (夜)〜2026-05-28 | `docs/research/senkyoku-log-detail-01.md` |
| `context/dm-signal-ops.md` | 1 | DM-signal 運用コンテキスト | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 10 | §6-7 recalculate_fast.py + OPT-E | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 25 | fullrecalculate実行方法（本番=Render。ローカルではない） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 37 | monthly_returns_gen分解計測の次checkpoint（`f7489c3b`） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 47 | DM-Signal本番FE CDP確認手順（2026-05-05実証済み） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 52 | 前提: PYTHONPATH=/mnt/c/Python_app/auto-ops | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 56 | Step 1: 隔離プロファイルEdge自動起動(user-data-dir=$TEMP/cdp-edge-9222) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 60 | Step 2: DM-Signal FEにAdmin認証(backend/.envのADMIN_USER/ADMIN_PASS) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 66 | Step 3: 確認したいページに遷移+スクショ | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 114 | §36 API認証 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 123 | §37 ETL | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 137 | Render CLI (v2.12.0) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 173 | §38 シグナル変更アラート | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 181 | §39 月初signal input snapshot | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 189 | パリティ全基準チェックリスト（殿定義集約 2026-04-11） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 224 | §9 性能ベースライン | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 294 | §12 計算データ管理 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 313 | §14 ドキュメントインデックス | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 327 | §16 知識基盤改善（穴1/2/3対策完了 — 2026-02-22） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 353 | Ops教訓索引 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 471 | §18 研究道具APIカタログ（cmd_1823追記） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 478 | GS（グリッドサーチ） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 505 | WF（ウォークフォワード） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 532 | champion_selector.py（事後チャンピオン選出） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 545 | research_engine（ライブラリ） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 565 | metrics（metrics_research_engine、ライブラリ） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 572 | MRE.NUMERIC_METRICS  — 38メトリクス名リスト（本番MetricsCalculatorと同一定義） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 580 | §19 サービスURL一覧（CDP/API操作前に必ず参照） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 593 | §19.1 体感主導デプロイ後のFE正しさ検分 (2026-07-02殿裁定) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 600 | §17 現在の全体ステータス（2026-03-11） | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 624 | §31 ALM浄化記録 (2026-04-25) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 628 | 発見した事実 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 637 | 浄化実施 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 648 | 正しいALM構築の前提 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 654 | §32 バグパターン認識表 (2026-04-25) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 672 | 共通パターン (汎用6) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 683 | DM-Signal 固有パターン (6) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 698 | §33 GS正規化 進捗 (2026-04-27) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 705 | 汚染発覚と方針転換 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 711 | Phase構造(v3.5 — 2026-04-28 04:32更新) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 716 | 基盤整備(Phase 0-6) — CSV依存の完全排除 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 729 | 本番検証(後続A-D) — チャンピオン再選出+検証 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 752 | ★L1パリティバグ(2026-04-29 00:07発見 → 修正完了) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 761 | 進捗サマリ(2026-05-07更新) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 772 | 軍師確認事項(2026-04-28 04:04) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 780 | Phase 1.9c結果(2026-04-28完了) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 790 | GS正規化関連教訓 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 800 | 検証済み事実 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 813 | Phase 3-7設計(軍師分析 2026-04-28) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 830 | PI候補 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 866 | §32 GSシン忍法21体hide登録 (cmd_2392, 2026-04-29) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 871 | §34 GSシン奥義21体hide登録 (cmd_2422〜cmd_2424, 2026-04-30) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 876 | §35 knowledge-base methods拡張 (cmd_2429〜cmd_2434, 2026-04-30) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 883 | §37 価格データ取得開始年統一 (cmd_3076偵察→cmd_3077修正, 2026-05-27) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 891 | §38 2026-05 運用・CI・知識基盤更新 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 910 | §39 PF物理削除手順 (2026-06-01) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 927 | §40 2026-06-01 backend運用更新 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 935 | §41 2026-06-11 source freshness照合 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 943 | §42 main反映・デプロイ裁可ルール (2026-06-11 / **2026-07-10殿裁定で改定**) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 955 | §43 2026-06-12 source freshness照合 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 967 | §44 2026-06-20 source freshness照合 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 979 | §45 2026-06-27 source freshness照合 | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 994 | §46 password rotation運用リスク (cmd_3634_recon3) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1000 | §47 Phase1 stability fix (cmd_3635) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1006 | §48 Phase2 PrecomputedRaw基盤 (cmd_3636) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1012 | §49 Phase3 P1 raw lookup + invalidate (cmd_3637) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1020 | §50 compare-returns bulk precompute (cmd_3639) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1027 | 因果リンク | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1048 | §51 precomputed_raw鍵整合 (cmd_3666-3669, 2026-07-03) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1060 | §52 signal decision ledger初期台帳 (cmd_3700/3702, 2026-07-06) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1071 | §53 PF削除アーカイブ・復元API (cmd_3753/3754, 2026-07-08) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1077 | §54 工程3: 全PF事前バックアップ確定 (cmd_3783, 2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1083 | §55 工程4前段: 入替対象リスト・実行手順確定 (cmd_3784, 2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1090 | §56 工程4実行中断状態 (cmd_3785, 2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1101 | §57 工程4ロールバック完了状態 (cmd_3786 / cmd_karo_hotfix_cmd3786_sequence_rerun, 2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1109 | §58 Monthly Trade検証用リターン計算のticker欠落問題発見・設計書化 (2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1117 | §59 再計算ステータスDB SSOT化 (cmd_3788, 2026-07-09) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1123 | §60 Monthly Trade matched_weight表示展開後不整合 (cmd_3809, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1129 | §61 Fusion可視性の殿裁定とCI修正による裁定逆行事故 (cmd_3834, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1136 | §62 Tier別PF可視性の承認完成形 (cmd_3837, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1143 | §63 admin visibility「手動saveしたのに反映されない」偵察: folder非表示はSignals限定 (cmd_3838, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1152 | §63.1 admin visibility根治実装: folder非表示(L1.5)を全閲覧EPへ横展開 (cmd_3839, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1160 | §63.2 cmd_3839 AC3-5: 楽観ロック+FE未保存ガード+本番検証 (2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1168 | §64 Stage A timeout / vectorized非決定性の再設計 (cmd_3840, 2026-07-10) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1176 | §65 Tier/global可視性設定の孤児清掃 (cmd_3841, 2026-07-11) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1183 | §66 L5 zero-recompute Phase 3ローカル全量検証 (cmd_3835, 2026-07-11) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1191 | §67 TIMING SUMMARY Layer5(precompute_raw)欠落バグ根治 (cmd_3842, 2026-07-11) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1199 | §68 recalculate P1a run identity固定 (cmd_3844, 2026-07-11) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1206 | §69 TradePerformanceメモ化の全PFパリティFAILと反映中止 (cmd_3845, 2026-07-11) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1212 | §70 origin/main統合は完了・push/deployは重大発見により見送り (cmd_3860, 2026-07-12) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1220 | §71 cmd_3860残21件FAILの全件triage完了・全量FAIL0/SKIP0達成(commit未push) (cmd_3861, 2026-07-12) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1229 | §72 P4統合+live deploy完了(commit=34747ad1)・restore契約完成・速度実測-8.80% (v1.4.15, 2026-07-13) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1240 | §73 P4 AC2再挑戦方式確定: single-source immutable input bundle (v1.4.17, 2026-07-13, GA-238で反映) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1247 | §74 GS DB世代重複削除候補9件を実削除(cmd_3868, 2026-07-13) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1253 | §75 P4 writer fence運用契約の現状(cmd_3873/cmd_3881/cmd_3882, 2026-07-13) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1264 | §76 safe bundle v2運用契約 (cmd_3879, 2026-07-14) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1271 | §77 SIGNAL CHANGE 07-13/07-14偵察 (cmd_3903, 2026-07-14) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1275 | §78 ledger最新event決定性・確定域fail-closed (cmd_3907, 2026-07-14) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1282 | §79 P4 keeper同一connection run orchestration checkpoint (cmd_3902, 2026-07-14) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1288 | §80 07-14 holding_signal 161行復元 (cmd_3905, 2026-07-14) | `docs/research/dm-signal-ops-detail-01.md` |
| `context/dm-signal-ops.md` | 1294 | §81 新規Signal INSERTのledger drift監査契約 (cmd_3997, 2026-07-16) | `docs/research/dm-signal-ops-detail-02.md` |
| `context/dm-signal-ops.md` | 1301 | §81.1 pytest timing ledger運用 (2026-07-16) | `docs/research/dm-signal-ops-detail-02.md` |
| `context/dm-signal-ops.md` | 1308 | §82 確定域holding_signal correction event運用 (cmd_3908, 2026-07-15) | `docs/research/dm-signal-ops-detail-02.md` |
| `context/dm-signal-ops.md` | 1315 | §83 確定域ledger baseline freeze運用 (cmd_3947, 2026-07-15) | `docs/research/dm-signal-ops-detail-02.md` |
| `context/dm-signal-ops.md` | 1321 | §84 recalculate-sync同一logical_date再計測 (commit 3b9327f8, 2026-07-29) | `docs/research/dm-signal-ops-detail-02.md` |
| `context/training-cycle.md` | 2 | 修行サイクル設計書（殿直伝 2026-03-25） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 4 | §1 背景と原理 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 14 | §2 修行タスクの設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 16 | 目的 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 19 | BLOCKパターン一覧（gate_report_format.sh + gate_fire_log実績） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 36 | 修行レベル設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 58 | 配備方式 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 67 | 自動修行サイクル（将来的な自動化） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 80 | §3 計測 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 82 | 計測方法（殿指摘で修正 2026-03-25） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 88 | 修行完了基準（殿裁定 2026-03-25） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 93 | 計測指標 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 99 | §4 Level 1 第1回実績（2026-03-25）— gate_fire_logによる正確な計測 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 117 | §5 L1全ラウンド実績（2026-03-25〜26） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 128 | 各ラウンドの自動化ターゲットと効果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 135 | L1完了判定 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 139 | 核心教訓 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 145 | §6 L2 Round 1実績（2026-03-26） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 147 | L2設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 151 | L2 Round 1結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 164 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 173 | 副産物: 実バグ発見3件 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 180 | §7 L2 Round 2に向けた環境改善 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 182 | 自動化ターゲット: テンプレート末尾フッターチェックリスト | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 187 | §8 L2 Round 2実績（2026-03-26） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 200 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 208 | L2完了判定 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 212 | GP-110実装完了（軍師） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 216 | §9 L3 Round 1実績（2026-03-26） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 218 | L3設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 224 | L3 Round 1結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 237 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 243 | §10 全ラウンド横断サマリ | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 258 | 核心教訓（L1+L2+L3統合） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 268 | §12 L3 Round 2実績（2026-03-26） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 270 | 環境改善: sgc inline hint追加 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 274 | L3 Round 2結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 287 | L3 R2 lesson_candidate注目点 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 294 | L3完了判定 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 298 | §13 修行サイクル全体サマリ（L1→L2→L3） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 300 | 定量結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 308 | 発見された実バグ（修行中に修正済み） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 316 | 修行設計原理（実証済み） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 323 | §14 L4設計 — 総合（3AC・全BLOCKパターン複合） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 325 | L4の目的 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 330 | L4タスク設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 344 | L4の罠要素（FILL_THIS + 構造崩壊誘因） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 351 | L4 配備対象スクリプト候補 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 360 | L4 完了基準 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 364 | L4 予測 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 370 | §15 L4 Round 1実績（2026-04-01） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 372 | L4設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 378 | L4 Round 1結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 393 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 403 | 副産物: 実バグ発見5件（全修正済み） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 411 | §10 全ラウンド横断サマリ更新 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 424 | §16 L4 R2に向けた環境改善 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 426 | 自動化ターゲット | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 436 | §18 L4 Round 2実績（2026-04-01） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 438 | 環境改善（§16で設計） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 444 | L4 Round 2結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 459 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 468 | 環境改善の効果（忍者別） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 479 | 副産物: 実バグ発見6件（全修正済み） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 488 | §10 全ラウンド横断サマリ更新 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 503 | gate_report_format.sh偽陽性問題 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 510 | §19 L4 R3に向けた環境改善 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 512 | R2→100%未達の根因 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 526 | R3設計 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 532 | §20 L4 Round 3実績（2026-04-01） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 534 | 環境改善（§19で設計） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 540 | L4 Round 3結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 556 | 分析 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 571 | gate偽陽性の再発（2回目） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 575 | 副産物: 実バグ発見6件（全修正済み、L4通算17件） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 584 | §10 全ラウンド横断サマリ最終版 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 602 | L4完了判定 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 606 | §22 L4 Round 4実績（2026-04-01）— 品質監査継続 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 608 | 目的 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 612 | L4 Round 4結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 625 | 副産物: 実バグ発見6件（L4通算23件） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 634 | lesson_candidate 6件 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 645 | decision_candidate 1件 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 649 | 備考 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 654 | §23 L4 Round 5実績（2026-04-02）— 品質監査継続 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 656 | L4 Round 5結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 669 | 副産物: 実バグ発見6件（L4通算29件） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 678 | 特筆: 半蔵のreview_gate.sh発見 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 682 | lesson_candidate 6件 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 693 | 備考 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 699 | §21 修行サイクル全体サマリ（L1→L2→L3→L4） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 701 | 定量結果 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 710 | 累積実績 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 717 | 核心教訓（全レベル統合） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 727 | §24 L4 R7実績（2026-04-02）— mixed編成初修行 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 729 | 編成 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 739 | 配備方式: 手動(cat > task YAML)。deploy_task.sh非使用→報告テンプレートなし | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 741 | R7結果（モデル別） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 754 | §25 L4 R8実績（2026-04-02）— テンプレート付き検証 | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 756 | 配備方式: deploy_task.sh --direct。報告テンプレートあり（18フィールド+assumption_invalidation scaffold） | `docs/research/training-cycle-detail-01.md` |
| `context/training-cycle.md` | 758 | R8結果（モデル別） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 771 | R7→R8比較分析 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 786 | 環境改善履歴（mixed編成） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 798 | §26 R11-R12 テスト速度最適化（2026-04-02）— 殿指示ネタ変更 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 800 | 殿指示 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 804 | R11結果（Sonnet+Codex 4名） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 815 | R12結果（Sonnet+Codex 4名） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 824 | 新知見: bats固定コスト制約 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 828 | 家老配備品質の構造穴（家老自走Phase7で発見 LK029） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 833 | 修行並列配備の標準手順（R21で実証 LK032） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 843 | Codex(GPT-5.4) STALL傾向 — **N=1で結論を出すな（殿指摘で修正）** | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 847 | §27 hold-outテスト設計 — 修行汎化の検証 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 849 | 概念 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 862 | training set（L1-L4で明示的に訓練済み） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 876 | hold-out set（訓練タスクで未登場のパターン） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 889 | 計測方法 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 897 | 結果の解釈 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 905 | 自動追跡 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 910 | §25 CoDD修行実績(2026-05-15〜16) | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 912 | 完走20本(全5ステップ: extract/elicit/generate/validate/measure確認済み) | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 937 | 教訓(LK002/LK003) | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 942 | 成果物 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 946 | CoDD修行天井と解消(2026-05-16) | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 952 | §28 CoDD速度改善ラウンド（2026-05-19定義） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 954 | 目的 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 959 | 方式: brownfield限定（codd extract 逆生成） | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 969 | 発動条件 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 978 | 対象選定 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 989 | タスクACテンプレート | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 1001 | aliases候補提案ステップ | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 1015 | 完了基準 | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 1024 | 家老運用メモ | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 1032 | 因果リンク | `docs/research/training-cycle-detail-02.md` |
| `context/training-cycle.md` | 1057 | CoDD修行サイクル実績(2026-05-16 L4ラウンド) | `docs/research/training-cycle-detail-02.md` |
| `context/dm-signal-research.md` | 1 | DM-signal 研究コンテキスト | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 16 | §19. 月次リターン傾き分析 (cmd_270/271/272) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 29 | エッジ検知 C1-C4 (cmd_273/274) + 外部データ(cmd_282) + 日次(cmd_281) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 49 | §20. ルックアヘッドバイアス検証 (cmd_276) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 58 | §21. 過剰最適化検証 (cmd_277) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 78 | §22. 外部データ統合エッジ検知 (cmd_282) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 87 | §23. 日次粒度エッジ検知 (cmd_281) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 96 | §24. 四つ目(yotsume) フルGSチャンピオン選出 (cmd_284) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 117 | 研究関連教訓索引 (projects/dm-signal/lessons.yaml) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 119 | 影響算定/再現性 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 130 | GS結果/パラメータ | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 182 | パリティ検証 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 235 | SPA/過剰最適化 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 243 | エッジ検知 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 255 | 外部データ | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 263 | 弱体化確率(P_det) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 273 | パフォーマンス持続性（cmd_860/861） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 304 | §25. trade-rule/business_rules突合（2026-03-11 殿確定6裁定） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 323 | §26. 万全偵察: DM-signal改善候補（cmd_761+762, 2026-03-11） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 329 | 水平偵察(cmd_761) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 338 | 垂直偵察(cmd_762, GSD式) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 347 | 統合: 最高ROI改善策（家老統合AC5） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 360 | §27. シン四神 v2 設計（2026-03-19 殿・将軍合同検討） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 375 | §28-§35. 前処理研究・ALM設計（2026-04-01〜2026-04-22） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 384 | §36. 金融ML知識辞書 2026-04-30 追加9件（cmd_2426〜cmd_2434） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 408 | §DMS-TVP レイヤー別動的選出 研究進捗 (2026-04-30) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 413 | lookback 5帯域(殿裁定確定) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 418 | バックテスト結果 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 427 | Aveシリーズ(殿発案) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 442 | 2026-05 追記 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 448 | §37. 用語辞書・投資知識リンク 2026-05更新 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 458 | §38. サイズ調整研究 (cmd_3218/3220/3224, 2026-06-08) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 462 | cmd_3218: 危険度スコアによるサイズ調整バックテスト (78体) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 476 | cmd_3220: 7戦略サイズ調整(100%/80%)バックテスト | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 490 | cmd_3224: V8_T25_MA50 過適合検証(OOS+サブ期間+ローリング3年窓) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 505 | §38教訓（cmd_3215〜3220系） | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 514 | §39. レイヤー別V8 + マネージドボラ研究 (cmd_3225, 2026-06-11) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 530 | §40. MTD Daily Returns UX / 速報行 (cmd_3332, 2026-06-12) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 549 | §41. 相関レジーム研究 (cmd_3425-3431, 2026-06-17) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 567 | §42. 75体+SPY堅牢性全量検証 (cmd_3515, 2026-06-23) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 575 | cmd_3517/3518: α6 robustness全6項目化 (2026-06-23) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 583 | §43. Continuity-risk metrics (cmd_3524/3525, 2026-06-25) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 599 | §44. fullrecalculate冪等性証明 (cmd_3546, 2026-06-26) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 605 | §45. 2026-06-27 source freshness照合 | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 610 | §46. L1+ BB直列拡張実験 (cmd_3490/3493, 2026-06-22) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 632 | §47. Lighthouse mobile周回計測原票 (cmd_3653, 2026-07-02) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 643 | §48. 全忍法GS少数実行・既存SQLiteパリティ確認 (cmd_3694, 2026-07-06) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 656 | §49. GS目的関数相関分析 (cmd_3713-3716, 2026-07-07) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 667 | §50. L0/シン方式チャンピオン比較・本番採用逆算 (cmd_3755-3767, 2026-07-08) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 676 | §51. 新L0-L3チャンピオン群 α6堅牢性検証 (cmd_3780, 2026-07-08) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 683 | §52. GA-206分類注記: PF入替執行ログは運用ドメイン (cmd_3783-3785, 2026-07-09) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 688 | §53. Monthly Trade matched_weight=0.5再分類 (cmd_3808-3809, 2026-07-10) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 694 | §54. Stage A/vectorized経路再設計 v1.1 (cmd_3840, 2026-07-11) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 705 | §55. P4 shadow反復exact GREEN、CI GREEN後のAC2再開はlive確認待ち (cmd_3859/cmd_3861, 2026-07-12) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 713 | §56. origin統合完了・実CI初回全量実行で21件pre-existing failure発覚、push/deploy意図的見送り (cmd_3860, 2026-07-12) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 726 | §57. P4統合+live deploy完了(commit=34747ad1)・restore契約完成・速度実測-8.80% (v1.4.15, 2026-07-13) | `docs/research/dm-signal-research-detail-01.md` |
| `context/dm-signal-research.md` | 736 | 因果リンク | `docs/research/dm-signal-research-detail-01.md` |
| `context/l3-robustness.md` | 1 | L3堅牢性検証 — 知見と方針の永久保存 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 10 | 1. 概要 — L3検証とは何か | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 27 | 2. 当初アプローチ（WF合議 — cmd_176） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 29 | 2.1 合議の概要 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 33 | 2.2 Q0分析: WHY/WHAT（殿の第二指示で全面再設計） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 98 | 2.3 Round 1設計（WF窓パラメータ — 家老統合案） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 111 | 2.4 合格基準（Round 1案 — 後に棄却） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 132 | 3. 方針転換の理由 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 134 | 3.1 殿の哲学との不整合 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 142 | 3.2 全員一致の問題（合議の失敗） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 146 | 3.3 殿裁定: 方針転換 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 156 | 4. 最終方針 — 4シンプル独立検証 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 160 | 4.1 cmd_177: CAGR vs MaxDD散布図 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 176 | 4.2 cmd_178: 95%信頼区間比較 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 193 | 4.3 cmd_179: Calmarレシオ・ヒストグラム | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 210 | 4.4 cmd_180: 月次リターン・ボックスプロット | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 226 | 4.5 総合判定 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 241 | 5. 次のhow — 実行計画 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 243 | 5.1 cmd_185: 上流CSV修正 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 252 | 5.2 cmd_186: 忍法別L3判定 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 260 | 5.3 cmd_175: L2忍法FoF本番登録 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 269 | 5.4 今後のL3知見蓄積方針 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 280 | 6. L3秘奥義 — 選出ルールと構成 (2026-04-17確定) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 282 | 6.1 選出プロセス | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 314 | 6.2 秘奥義6体の構成 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 325 | 6.3 本番登録 (cmd_2025) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 332 | 6.4 データソース | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 340 | 7. ASSS — L3 ASS忍法FoF構想 (2026-04-20殿指示) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 342 | 7.1 定義 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 347 | 7.2 構造 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 357 | 7.3 実行パイプライン | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 366 | 7.4 道具磨き(完了) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 371 | 7.5 状態 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 382 | 8. WF四神 — L1 WF選別構想 (2026-04-20殿指示) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 384 | 8.1 背景 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 390 | 8.1.1 シン四神 vs ALM四神 — 同じGS CSV、選出方法が違う (2026-04-20確認) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 405 | 8.2 命名規則（既存との区別） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 412 | 8.3 WFα3パターン | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 426 | 8.4 全層WFパイプライン (殿指示 2026-04-20) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 469 | 8.4.1 L2 GS配備ルール（OOM実証+殿裁定 2026-04-20, LS058） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 517 | 8.4.2 CoDDメモリ削減計画 (2026-04-20, 殿承認) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 565 | 8.5 必要スクリプト — 全14本CoDD済み (2026-04-20確認) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 584 | 8.6 WF L0結果 (cmd_2167, 2026-04-20) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 602 | 8.7 WF L1進捗 (2026-04-20) — 完了 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 616 | 8.8 infra改善(本セッション cmd_2164-2173) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 631 | 8.9 WF L1結果 — 従来L1 vs WF L1 比較 (2026-04-20) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 636 | 従来L1 vs WF-SS L1（選出目的OOSαでの比較） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 656 | WF-SS vs WF-AS比較（cmd_2175 AC4） | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 666 | 分析 | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 680 | 8.10 WF L1事後選出結果 (cmd_2176/2177, 2026-04-20) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 691 | 8.11 WF L2進捗 (2026-04-20) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 704 | 8.12 状態 (2026-04-21 09:13更新) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 741 | 8.13 WF四神 本番登録計画 (2026-04-21 殿裁定) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 756 | 8.14 WFシン四神 ロバストネス検証結果 (cmd_2214 GATE CLEAR) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 765 | 8.15 WF ALM四神 α6指標top安定性 (cmd_2215 GATE CLEAR) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 774 | 8.16 長期ロバストネス検証カタログ (cmd_2216 GATE CLEAR) | `docs/research/l3-robustness-detail-01.md` |
| `context/l3-robustness.md` | 779 | 8.17 L1ロバストネス横断比較 (cmd_2217-2220 進行中) | `docs/research/l3-robustness-detail-01.md` |
| `context/dm-signal-core.md` | 1 | DM-signal コアコンテキスト | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 9 | 0. 研究レイヤー構造 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 35 | 1. システム全体像 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 57 | §1.5 Phase間クリティカルデータフロー（OPT変更時必読） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 75 | 2. DB地図 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 83 | SSOT 3層階層（殿確定 2026-03-11 §25） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 104 | 3. 四神（しじん）構成 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 142 | 旧四神(v1: cmd_246時代 — FoF構成) ⚠ ディスコン | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 158 | シン四神v2（cmd_1018-1080: L1 standard PF）— 現行 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 169 | 命名規則（殿裁定 2026-02-20） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 183 | L2忍法チャンピオン（cmd_246完了 — 全12体 0.00bp PASS） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 206 | ポートフォリオ一覧 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 220 | 4. ビルディングブロック | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 226 | BB種別分類（cmd_247） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 246 | tiebreakルール（cmd_217, L086/L092） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 257 | GS-本番パリティ統一原則（cmd_229: PD-011/012/013） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 264 | SVMF/MVMFバグ修正（cmd_235 + cmd_244） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 273 | 新忍法候補（2026-02-22 偵察開始） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 281 | パイプライン実行・シグナル | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 304 | 4.5 GS用語定義（混同厳禁） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 315 | 5. ローカル分析関数 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 326 | §5.5 Robustness / Continuity Metrics (2026-06-25) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 337 | 8. APIエンドポイント概要 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 359 | §8.5 Deterioration Benchmark Layer (2026-06-25) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 363 | §8.6 Compare Returns / MTD SSOT (2026-06-27) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 371 | §8.7 Fusion API (2026-06-28) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 375 | §8.8 Rolling Returns API/Table (2026-07-01) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 381 | 10. ディレクトリ構成 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 387 | 11. Lookback標準グリッド（恒久ルール） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 402 | 13. StockData API | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 408 | 15. 殿の個人PF保護リスト（絶対ルール — cmd_198） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 419 | 18. backend `folder_id` 実態（cmd_269, 2026-02-23） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 429 | 19. 教訓索引（Lesson Index） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 432 | 19.1 DB関連 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 447 | 19.2 BB仕様・バグ修正 | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 477 | 19.3 GS-本番パリティ | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 491 | 19.4 FoF登録フロー | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 505 | 19.5 GS運用・config | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 514 | 19.6 追加統合（cmd_322） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 536 | 19.7 trade-rule突合・SSOT（cmd_766-770） | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 543 | 20. Deterioration色丸(ColorDot)マッピング | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 554 | 指標別→Label変換ロジック | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 564 | GSL1正規パス (cmd_2393, 2026-04-29) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 568 | GSL2正規パス / L2奥義登録 (cmd_2422-2424, 2026-04-30) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 573 | §20.5 WP削除後のbackend正本 (2026-06-12) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 584 | PortfolioEditor UI ↔ pipeline_config 同期欠落 (cmd_3079偵察, 2026-05-28) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 594 | §21 FoF表示・監査系 2026-05更新 (cmd_2451〜2455) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 613 | §22 CI/テスト基盤 2026-05更新 (cmd_2652〜2660) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 622 | §23 P4統合期のbackend変更 (cmd_karo_hotfix_p4_restore_core_integrator/cmd_3858/cmd_3861, 2026-07-12、GA-238で反映) | `docs/research/dm-signal-core-detail-01.md` |
| `context/dm-signal-core.md` | 635 | 因果リンク | `docs/research/dm-signal-core-detail-01.md` |
