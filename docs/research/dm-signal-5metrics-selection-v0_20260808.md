# DM-Signal 新規5指標(RRR/DDA/ACS/RRS/ECR) 実装設計書 v0.1

- 作成: shogun 2026-08-08
- 仕様正本(殿原文・改変禁止): `docs/research/dm-signal-5metrics-v0-original_20260808.md`
- 本書の位置づけ: 殿v0仕様を正とし、DM-Signalへの実装工程・AC・検証契約を定義する。**仕様の変更は殿裁定のみ**。本書はHOWの工程分解であり、指標定義の解釈が原文と食い違う場合は常に原文が勝つ。

## §1. 5W1H

| 項 | 内容 |
|----|------|
| Why | 102PFからのPortfolio Selection問題。過去Performanceの別表現ではなく「将来もEdgeが残るPFをPoint-in-Timeで識別できるか」の検証 |
| What | 新規5指標: RRR(開始時点頑健性)/DDA(DD経路負担)/ACS(Alpha時間一貫性)/RRS(Regime頑健性)/ECR(複利変換効率) + PIT Selection実験基盤 |
| Where | `/mnt/c/Python_app/DM-signal`。計算層は既存metrics engine系(現物特定はPhase 0偵察)。実験出力は`outputs/`研究層。**研究出力を本番に流さない(LS-A15)** |
| Who | 将軍=設計書+cmd起票 / 家老=分解配備 / 忍者=実装・実験 / 軍師=レビュー(特にPIT契約) |
| When | Phase 0偵察→P1計算実装→P2 PIT時系列生成→P3評価。各Phase完了時に殿へ結果報告、次Phaseは結果を見てから |
| How | 定義固定・最適化禁止・全PF同一適用(原文§1.2)。実験ファースト: 設計書完璧化に回らずP0偵察から即回す(LS115) |

## §2. AsIs / ToBe

- **AsIs**: 102PF・既存30指標弱は「過去の記述」。t時点順位→将来品質の関係を検証する仕組みが存在しない。選択基準が定義されていない。
- **ToBe**: 各月末t・102PF全量の5指標PIT値+Cross-sectional Rankが出力Schema(原文§15)で保存され、Forward Evaluation(§9.4)・Benchmark Rules比較(§10)・評価7項目(§11)・冗長性RankCorr(§12)が機械再現可能なスクリプトで出力される。

## §3. 実装契約(原文からの絶対制約)

1. **PIT絶対**(原文§13): t月末指標はt以前データのみ。禁止6項(full-history逆流/future regime/future window/full-period normalization・percentile/全期間Rank逆流)は自動Quality Check(原文§16)でFAILさせる。
2. **最適化禁止**(§1.2/§18): Weight合成・パラメータ探索・Layer別定義・Threshold探索・Best Lookback/Horizon選択を実装しない。コードに最適化フックを作らない。
3. **NULL契約**: MAD=0→NULL(RRR/ACS)、mu<=0→NULL(ECR)、history<36M→NULL。特殊値・Infinity・符号反転Raw値を作らない。
4. **方向統一はRank層のみ**(§1.3): Raw値は元の意味を保持。DDAはRank時ascending。
5. **既存定義の再利用**(§4.2/§5.1): Benchmark・Risk-Free・Regime分類・Active Returnは既存実装と完全同一仕様。**新定義を作らない**。Phase 0で既存実装の現物(関数・テーブル)を特定し、5指標コードはそれを呼ぶ。
6. **パラメータ空間縮小禁止**(殿厳命2026-04-04): 102PF全量・利用可能全月・Forward horizonはt+1/t+3/t+6/t+12全量(t+1先行は許可されるが残りを切り捨てない。Multiple Horizonは別Experimentとして明示=原文§9.4)。
7. **Sample Count併記**(§14/§5.7): window_count・regime n_*を必ず出力し、恣意的Minimum Count Filterを置かない。

## §4. 工程表(Phase分解)

| Phase | 内容 | 完了条件(二値) | 起票cmd(起票時に実番号記入=予約禁止LS-A04(46)) |
|-------|------|----------------|------|
| P0 | **偵察**: (1)既存Rolling Return/Alpha(OLS+RF)/Regime Active Return/Arithmetic・Geometric Mean実装の関数名・ファイル・行番号 (2)月次return・NAVデータ取得経路とPIT可用性 (3)102PF・layerの列挙元 (4)出力先候補(テーブル/parquet) (5)偵察5要件(変更対象/波及先/テスト/エッジケース/依存順序) | 偵察報告YAMLに5要件全記載+既存定義の現物引用あり | (未起票) |
| P1 | **計算実装**: 5指標計算モジュール+出力Schema(原文§15全列)+Quality Check(§16)の自動テスト。単一時点tでの102PF計算が通る | §15全列出力+§16全チェックPASS+既存指標との突合(Alpha/VDrag等は既存値再現)一致 | (未起票) |
| P2 | **PIT時系列生成**: 各月末t×102PFの5指標を全履歴分生成。lookahead検査(t時点値がt+1以降データ変更で不変であること)をサンプル月で機械検証 | 全月×102PF出力存在+lookahead検査PASS+NULL契約通りのNULL分布記録 | (未起票) |
| P3 | **評価**: §9.4 Forward Evaluation(t+1先行、t+3/6/12は同一ランナーで継続)+§10 Benchmark Rules(A-F vs G-K)+§11評価7項目+§12冗長性RankCorr表 | §11の7出力+§12の12ペアRankCorr表が再現可能スクリプトで生成 | (未起票) |

- P0-P1は直列。P2はP1完了後。P3はP2出力に対する読み取り専用。
- 各Phase=1cmd原則(1道具1CMD)。P0は偵察cmd、P1-P3は実装cmd。
- DB書込みが発生する場合は直列配備(DB排他)+バックアップファースト。ただしv0は研究層出力(outputs/)を基本とし本番テーブルへ書かない。本番metrics層への昇格は殿裁定後の別工程。

## §5. 実験成功条件(原文§17転記)

固定Thresholdなし。観察: Forward RankCorr方向/正月率/Top-Bottom Spread/前半後半一貫性/Layer横断一貫性/既存Metricsとの差別化。核心=「過去Performanceとの相関が低いのにForward Qualityとの関係があるか」。CAGR/Sharpeと同じPFしか選ばない指標は不要と判定する。

## §6. リスク・伏兵

- 既存Regime分類・Active ReturnがPIT再計算可能な形で保存されていない可能性(full-period定義の場合、RRSのPIT化には「t時点までのregime分類」が必要)。→ P0偵察の最重要確認事項。full-periodでしか取れない場合は殿へ報告し裁定を仰ぐ(勝手にRegime定義を作らない=§3-5)。
- 既存3Y Rollingデータ(原文§2.2)の粒度・保存範囲が不足する場合は5指標側で月次returnから再計算(定義は既存と同一に)。
- 102PFのinception分散によりRRR/ACSのNULL期間が長いPFが出る→NULL契約通り出力し、実験側でSample Count併記(除外Filterは置かない)。

## §7. 進捗台帳

| 日時 | 事象 |
|------|------|
| 2026-08-08 | 殿原文受領・全文保存(`dm-signal-5metrics-v0-original_20260808.md`)。本設計書v0.1作成 |
