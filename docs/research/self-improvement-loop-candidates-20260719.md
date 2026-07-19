# 自立改善ループ候補カタログ（2026-07-19起草）

殿指示(2026-07-19 17:35-17:38): 「慌ててやる必要はない。まずはドキュメントにして、やりたいときに思い出せればいい。他の候補も探してくれ、家老や軍師、忍者にも偵察させてもいいな。他リポジトリも含めてだ」

## §0 ループ成立の3条件（適用判定基準）

1. **一次計器がある** — ledger/log/gateで数値が自動記録される（なければ計器づくりが先行タスク）
2. **修正が可逆** — revert/restore可能。可逆なら裁可待ち不要で自走可（殿裁定2026-07-10）
3. **検証可能** — gate/軍師レビュー/再計測でbefore→afterを二値確認できる

ループの型: 計測→支配的要因の特定→根治配備(karo-direct)→GATE CLEAR→再計測→数値記録→次要因。
実証: 2026-07-19のidle改善サイクル（report alias SSOT・idle cooldown・inbox parser境界・finalize内訳、いずれも起票→CLEAR 5〜16分）。

## §1 multi-agent-shogunシステム内の候補

| # | 対象 | 計器(既設) | 状態 | 備考 |
|---|------|-----------|------|------|
| S1 | finalize段短縮 | loop_ledger段階別中央値(finalize 403s) | **稼働中** | 内訳=report→notify 82.4s+SG7→review 74.1sで61.8% → `finalize-stage-breakdown-20260719.md` |
| S2 | 検知器の粒度・FP根治 | defense_overhead.jsonl(1,730件)+detector_fp_rate.yaml | 計器完備・未ループ化 | skill refs 12回/24分→0の型(LS096)を全検知器へ横展開。人手確認時間を直接削る |
| S3 | テスト実行時間・test資産淘汰 | test_suite_timing_ledger.tsv等+default-delete政策(殿裁定2026-07-19 02:09) | **稼働中**(殿裁定2026-07-20 00:05開始+PD-132解除) | 設計正本→`s3-test-speed-asis-tobe-5w1h_20260720.md`。A=スクリプト速度修行multi-round自走/B=在庫sweep |
| S4 | deploy/work段overhead | loop_ledger(deploy 60s/work 311s) | S1の次弾 | 注入蓄積(deploy_task 1s→140s問題)の系譜 |
| S5 | startup gate実行時間 | TIMING 59項目(最大check=loop_ledger 15.5s) | 計器あり・未ループ化 | 起動毎24s。全エージェント×毎セッションで複利 |
| S6 | insight滞留在庫 | promotion消化路+aging計測 | 半自動 | batch消化のみ→消化速度の計測・改善 |
| S7 | inbox/掲示板通知の重複・遅延 | inbox archive+bulletin log | 未計器化 | 本日parser境界根治の続き。通知round-trip時間の計測から |

## §2 DM-Signal

| # | 対象 | 計器 | 状態 | 備考 |
|---|------|------|------|------|
| D1 | パリティ・ドリフト監視修復 | parity_check.sh+signal_change_log+ledger被覆100% | freeze CLOSED後の維持ループに最適 | 逸脱検知→述語導出→修復の型はcmd_3905で実証(LS-A09(37)) |
| D2 | FE体感(Lighthouse) | mobile_lighthouse_round.py(mobile+CPU4x強制) | 計器完備 | 体感主導デプロイ§19.1と併用。体感クローズ済み領域は再燃条件のみ監視 |
| D3 | fullrecalculate速度(precompute L5) | 実測497s/目標30s | 再開条件達成済み | 規模大=自走ループより計画レーン向き(gist 549122da) |
| D4 | ETL cron安定性 | cron実行ログ+価格データ多重化 | 未ループ化 | 失敗検知→自己修復→再実行の型 |

## §3 他リポジトリ・他PJ（2026-07-19実地偵察済み）

| # | 対象 | 計器（現物） | 状態 | 着手前提 |
|---|------|--------------|------|----------|
| P1 | google-classroom | scrape JSON log + Playwright + Render内蔵cron | 半備 | log schema固定→selector失敗分類→成功率台帳 |
| P2 | clinic-expense-tracker | `/health`のみ（test/CI 0） | 計器先行 | CSV件数・重複・金額総和・未突合数の台帳 |
| P3 | dividend-tracker | build/lintのみ（test/CI 0） | 計器先行 | 配当fixture集計contract→CI |
| P4 | database（株式DB） | Render cron 2件+`/healthz`+36 tests | 即候補 | cron成功率・鮮度・欠損率を台帳化 |
| P5 | kj-role-count | daily backup cron+`backup.py`+health+8 tests | 即候補 | 定期restoreで件数一致と所要時間を記録 |
| P6 | Simple-OCR | backup/restore test+17 tests+OCR log DB | 即候補 | 復元成功率・件数一致・所要時間を台帳化 |
| P7 | rebalancer | CI+6 tests+health+Playwright | 即候補 | Alpaca IEXは18/18購読可、無料枠30 symbols/connection、31で405。push表示+EODHD確定値の二層化候補 → `docs/research/cmd_4087_rebalancer_realtime_recon.md` |
| P8 | dm-fusion/mcas/milk | build/lintまたは計器なし | 計器先行 | 隔離fixture+最小contract+CI |
| P9 | auto-ops/kj-partshift/kj-toilet | 8/13/9 tracked tests | 候補 | 業務結果の件数・重複・遅延台帳を先行 |

全15 PJの3条件、根拠、計器先行タスク案（対象・波及・test・edge・順序） → `docs/research/cmd_4086_loop_candidate_recon.md`

## §4 運用

- 本カタログは**思い出すための索引**。着手は殿の指示またはidle資源の空きで、慌てない。
- 追加候補は本ファイルへ追記(家老・軍師・忍者の偵察報告から)。
- 着手時: §0の3条件を判定→計器不足なら計器cmdが先→ループ開始後はkaro-direct自走(auto_loop_order 2026-07-19 17:25の型)。
- 各ループのbefore/after数値は掲示板+本ファイルの状態列へ還流。

## 因果リンク

- ← [[殿質問_スループット数値_20260719_1651]] → [[finalize中央値403秒が最大税]] → [[自立改善ループ横展開構想]]
- → [[throughput-first-asis-tobe-5w1h_20260708]] スループット第一原則
- → [[finalize-stage-breakdown-20260719]] S1の一次実測
