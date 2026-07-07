# GS実行速度・最適化 設計書 — 種類・実測・見込み時間・残課題

作成: 将軍 2026-07-08 03:22(殿指示03:10「各種GSの種類(L0、7忍法)と実行速度、見込み時間、最適化も道具磨きをこの前やったはずだ。最新情報に基づき再構築」+03:14「別設計書に分離」)
親計画: `gs-recalibration-plan.md` v2.2 Phase T | 先行設計: `gunshi_gs_speed_design_l0_l3_20260706.md`(軍師) | version: **v1.1**(2026-07-08 03:34 — 殿指摘: エンジン同一コードパス共有はcmd_1199で棄却済み。T1をGS独自実装+PI-009パリティ検証へ修正)

## §0 大原則 — GSと本番エンジンの分離とパリティ(殿指摘03:30で再確認した歴史)

| 経緯 | 事実 |
|------|------|
| cmd_1199 (a137593e) | PI-009準拠のためsimulate_patternをPipelineEngine(本番エンジン)経由に差替え |
| サイレント性能劣化 | import 4.5s+75.7MB/プロセス、6 forkワーカーで454MB追加、per-pattern 2.71→3.49ms(**1.29倍悪化**)。発見も殿の問い「12体と20体の間でコード改変があったはずだ」 |
| 帰結 | 本番経路からPipelineEngine排除(lazy化)。**GS=独自高速実装(ベクトル化/@njit/SHM)、本番=PipelineEngine の分離が確定** |
| 代償=PI-009 | 「GSは本番と**同一の結果**を出さなければならない。全期間holding_signal完全一致(必須)+monthly_return 1e-6以内」— エンジンを分離したからこそ、**結果のパリティ検証が必須**(verify-gs-parity-pi009系の様式) |

**原則: コードは共有しない。結果を一致させる。** バンド組込み(T1)もこの原則に従う。

## §1 GSの種類 — 全量マップ

| GS | スクリプト | 対象 | パターン数 | 構造 |
|----|-----------|------|-----------|------|
| L0四神 | `shin_shijin_l1_gs.py`(963行) | 4DM系直列 | **191,796** = DM2 76,680 + DM3 38,340 + DM6 76,680 + DM7+ 96 | 2段DNAキャッシュ(Phase1=ユニークDNAごとmomentum計算→Phase2=safe_haven×rebalance展開)。phase0bでProcessPool化 |
| 忍法GS | `run_077_*.py` **8本**: bunshin(分身)/oikaze(追風)/kasoku_diff(加速D)/kasoku_ratio(加速R)/kawarimi(変わり身)/nukimi(抜き身)/yotsume(四つ目)/weighted_yotsume(重四つ目) | universe差替えで使用。**本番実測(2026-07-08): L1=7忍法×3モード=21体(新四つ目なし)、L2=8忍法×3モード=24体(新四つ目含む)、L3=7忍法×3モード+直下モードFoF 4体=25体** — レイヤーごとに忍法セットが異なる点に注意 | bunshin 7,525 / oikaze 270,900 / kasoku_diff・ratio 各**1,151,325**(最大) / kawarimi・nukimi・yotsume系=**未棚卸し** | ProcessPool+SHM実装済み |

共通基盤: **prefetch方式**(Supabase→ローカルSQLiteダンプ1回→以降ネットワークゼロ。phase0b実装、daily_prices=89,715行+monthly_returns=16,464行で全量作成実績)。入出力ともローカルSQLite(殿裁定2026-07-06 06:55: 全レイヤーlocal_sqlite統一)。

## §2 道具磨き実績(2026-07-06 E系cmd群、全て報告YAML実測値)

### L0四神 — 33分timeout→246秒(8倍改善・5分達成)

| 段階 | 施策 | 実測 |
|------|------|------|
| ベースライン | (cmd_3692) | DM2単独(76,680p)で**33分timeout**(exit124, RSS 722MB) |
| phase0b | prefetch SQLite入口+DM2 DNAグループProcessPool並列化 | p1/p20/p100完全一致確認 |
| E2 | Phase1信号履歴抽出を`signal_history_only`早期return化 | p100 family grid 1.2s→0.7s |
| E3 | `--benchmark-mode`追加(既定動作不変) | p1000 wall 215.07s→22.71s |
| E4 | pattern_limitを生成時適用 | p1000 22.71s→8.5s |
| E5 | monthly SQLite writeをmelt経由→matrix直接insert | p1000通常write 112s→43.2s |
| E6 | metrics計算を月次行列ベクトル一括化 | DM2 p1000通常経路13.3s |
| **E7** | full確認(コード変更なし) | **全量191,796p = wall 246.09s、exit0**(5分目標を実測達成) |

### 忍法GS(L3=21体universe実測) — 加速系も5分達成

| 忍法 | 段階 | 実測 |
|------|------|------|
| kasoku_diff | ベース: phased benchmark 436s **FAIL** → E2: monthly_blob生成の明示skip+params/metrics挿入高速化 | **full 191.4s完走** |
| kasoku_ratio | E2: 支配要因特定(Phase3=SQLite出力+md5が全体の78-90%)→file_md5チャンク+monthly_blob対策 → E3: MP_WORKERS 1→6(Phase1 3.42x=12.5s→3.7s、RSSむしろ減 1185MB→726MB)、全workers mismatch_count=0 | **full 1,151,325p = 266.95s / 298.09s(2回完走、5分内)** |
| bunshin | (既磨き) | 全量7,525p = **21s** |
| oikaze | 3p実測17.83s(cmd_3694)のみ | **全量270,900p未実測** |
| kawarimi/nukimi/yotsume/weighted_yotsume | — | **パターン数・全量とも未棚卸し・未実測** |

検証様式(全E系cmd共通): `compare_gs_sqlite_monthly.py`でbefore/after出力のmismatch_count=0を確認(速度化による計算結果の変化ゼロを毎段保証)。

## §3 見込み時間の再構築(v1計画「16-26時間」を置換)

| 工程 | 実測/見込み | 根拠 |
|------|------------|------|
| L0四神 full | **~4.1分(実測246s)** | E7 |
| L3 kasoku_diff | **~3.2分(実測191s)** | E2後 |
| L3 kasoku_ratio | **~4.5-5分(実測267-298s)** | E3後 |
| L3 bunshin | **~21s(実測)** | 既磨き |
| L3 oikaze | 見込み~2-4分(kasoku比1/4のパターン数、同型構造) | **Phase Tで実測** |
| L3 kawarimi/nukimi/yotsume系4本 | 見込み各~5分以内(5分超過なら同型最適化を適用) | **Phase Tで実測** |
| L1/L2の8忍法 | L3(21体)より小さいか同等universe(12体/21体)→L3実測が上限の目安 | Phase Tで代表実測 |

**総GS計算時間の見込み: L0 ~4分 + (8忍法×~5分)×3レイヤー ≈ 2.1時間上限**(直列実行でも)。v1計画の16-26時間から**約1桁圧縮**。ボトルネックはGS計算からチャンピオン選出・本番更新・パリティ検証・レビューサイクル側に移った。

注意: 上記はバンド組込み**前**の実測。三状態判定の追加でper-pattern計算が増える — Phase Tで組込み後に再計測し、5分超過なら道具磨きへ戻る(殿厳命の順序: 磨いてから全量)。

## §4 残課題(Phase Tの実装対象)

| # | 課題 | 内容 |
|---|------|------|
| T1 | **バンド三状態のGS組込み**(v1.1修正) | 全GS(L0+run_077系8本)の月次判定パスにthreshold_band三状態(合格/バンド内半々/失格)を**GS独自の高速実装(ベクトル化)として実装**する。~~本番エンジンと同一コードパス共有~~は**禁止** — cmd_1199(a137593e)でPipelineEngine経由化を試み、import 4.5s+75.7MB/プロセス・6ワーカー454MB追加・per-pattern 1.29倍悪化のサイレント性能劣化で棄却済み(殿指摘2026-07-08 03:30で再確認)。二重実装の乖離は**PI-009様式のパリティ検証で保証**: GS出力 vs 本番エンジン(cmd_3707)出力で全期間holding_signal完全一致+monthly_return 1e-6以内を、バンド発火ケース(cmd_3705の7月反転10ケース等)を含む代表PFで先に通してから全量GSへ進む |
| T2 | 未実測忍法の全量ベンチ | oikaze/kawarimi/nukimi/yotsume/weighted_yotsumeのパターン数棚卸し+全量実測(バンド組込み後)。5分超過はE2/E3系技法(出力最適化・MP workers・blob skip)を同型適用 |
| T3 | 選出後処理の速度 | 14指標算出(cmd_3714/3716実装流用)+2基準選別のパイプライン化。GS出力SQLite→選別まで人手ゼロ |
| T4 | L1/L2 universe差替えの動作確認 | run_077系にL0/L1新チャンピオンuniverseを入力する経路の確認(前回はL2/L3で使用実績あり) |

## §5 不変の原則(殿厳命2026-07-06 01:08)

1. **1PF×1パターン**で計算パスを最速化(プロファイリング→hot path)
2. **5分以上かかる計算は許すな** — 5分以内を確認してから次へ
3. パターン数を段階的に増やして再計測
4. 全パターンでも5分以内を達成してからGS本番実行
**いきなり全計測するな。** パラメータ空間の縮小は禁止(2026-04-04)— 遅ければ空間を削るのではなく道具を磨く。

## 因果リンク

- [[殿厳命20260706_0108_道具磨きの順序]] -> [[E2-E7+L3系cmd群]] -> [[L0_246s+加速R_267s実測]]
- [[gunshi_gs_speed_design_l0_l3_20260706]] — 軍師の初期設計(§1計測表はcmd_3694の3p実測。本書§2が全量実測で置換)
- [[gs-recalibration-plan_v2.2]] — 親計画Phase T
- [[cmd_3707_バンドエンジン実装]] -> [[GS未組込み+本番config未設定(102PF実測20260708)]] -> [[T1_同一コードパス共有]]
