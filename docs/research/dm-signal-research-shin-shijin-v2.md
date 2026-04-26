## §27. シン四神 v2 設計（2026-03-19 殿・将軍合同検討）
<!-- last_updated: 2026-03-19 v2全面再設計: DNA事前制約+データ駆動lookback確定 -->

### 設計方針（v2 — 旧方式を全面廃止）

**旧方式(v1)**: 広く探索(191,796)→CPCV→Triple-E→脱相関K体→32ユニット。DNA理解が甘くパラメータが幅広すぎた。
**新方式(v2)**: DNA理解→パラメータ事前制約→既存GS結果でlookbackデータ分析→3モードチャンピオン直接選出→**12体**。

4ファミリー × 3モード(CAGR/MaxDD/NewHigh)。重複吸収(激攻>常勝>鉄壁)で**10体**。
朱雀・玄武は激攻=常勝が同一変種→常勝消滅。シン忍法はこの10体を材料として構築。
- L415: CPCV(Phase 3)はDM×FoFに構造的不適合として廃止(殿裁定 2026-03-19)。FoF材料は一瞬のきらめきで十分（cmd_1078）
- L494: 将軍予備分析と忍者独立検証で数値が乖離。独立実装間の差異は想定内（cmd_1411）
- L495: 将軍先行分析とのCAGR差異は独立実装間の想定差（cmd_1411）
- L498: ローリングSharpe選抜は遅行指標でWardクラスタ構造選抜に劣後する（cmd_1417）
- L514: Ward Two-Stage EW(k=5,lookback=36mo)のクラスタが141リバランス日(12年)完全固定。1/N EWとの差+0.25%。パフォーマンスに寄与していない定量的証拠（cmd_1570）
- Ward固定化根因(cmd_1578): 相関距離の構造的狭さ(separability=0.33<0.5全期間全k、全ペア距離mean=0.61)。シンv2は旧より高相関(距離26%狭)でWardさらに不安定(ARI安定性45.5%vs旧63.6%)
- K=5/LB=36 vs K=4/LB=24比較(cmd_1576): Sharpe差0.1%未満(2.0801 vs 2.0793)で実質同等。R19(99セルGS)真最適はK=4/LB=30。後方伝播検証不在が根因だがパラメータズレは軽微
- **R28 Ward Cluster Selection(cmd_1579): Ward改善不可の最終根拠**。クラスタ内momentum top1選出+K体EW保有→全K(3,4,5)で現行Ward FoF(全員保有)に全指標劣後。ClSel(K=5) Sharpe1.77<1/N EW1.78。超越条件3つ全FAIL(CAGR:60.6%vs80.6%/Calmar:2.72vs4.18)。**ウェイト変更でもselection変更でもWard改善不可能**
- **R28-シン ClSel逆転(cmd_1581): シン素材で有効に逆転**。シンClSel_K3がCAGR74.6%/Sharpe1.75/Calmar4.60/MaxDD-16.2%/UWP3mで全方式中最良。超越条件B(Calmar4.60>3.90×0.95)PASS+C(UWP3m<5m)PASS。旧忍法では全FAIL→シンで逆転=素材依存性が明確。集中投資リスク(20体中3体)が残課題。cmd_1578(ARI45.5%=クラスタが動く)と整合
- **R28-OOS 過適合なし(cmd_1580): WF-OOS 7窓で旧忍法Ward ClSel過適合フラグなし**。劣化率<30%全K。Ward K=4がOOS最良(CAGR74.0%/Sharpe2.02/Calmar3.57)。Ward vs Simple Momentum: 全KでWard優位(Sharpe差+0.28〜0.49)。Ward vs 1/N EW: K=4,5がEW(Sharpe1.89)上回る。**OOSでクラスタリング付加価値確認**
- R28-K2端点検証(cmd_1584): K=2は全K中CAGR最高(旧61.3%/シン75.8%)だがMaxDD最悪(旧-32.2%/シン-20.4%)。旧は超越条件全FAIL。シンは条件Bのみ辛うじてPASS(Calmar3.72≥3.705)。**K=2は集中リスク許容範囲外。K=3-5が最適帯域**
- R28-指標感度分析(cmd_1582): 4指標(Momentum/Sharpe/Calmar/Sortino)×K=3,4,5=12パターン全てWardFoF全員保有(Sharpe1.85)に劣後。Sharpe選抜K=5が1.80で最高。Sortino-Momentum間ランク相関0.49で最も独立。**指標空間でもWard改善不可**
- **PD-004裁定(2026-03-31殿裁定): Ward FoFはkeep(継続)**。R28-R30研究で付加価値ほぼゼロ+β調整後超越条件全FAIL確定だが、殿判断で維持
- R28-Momentum持続性(cmd_1583): 個別自己相関は全lag非有意。クロスセクショナルhit rateはK=3,4で高度有意(短期1ヶ月)だが長期lookbackで減衰。**R28のmomentum前提は弱い。12ヶ月lookbackの理論的根拠は薄い**
- **R28-シンOOS(cmd_1585): K=3 Calmar41.6%劣化=OVERFIT**。K=4はCalmar28.1%劣化でOK。CAGR劣化は全K7%以内。Ward vs SimpleMom付加価値は旧忍法比半減。**cmd_1581のK=3超越条件B+C PASSはOOSで過適合の可能性。シンでもK=4がOOS最良**。L516登録
- R28-シン指標感度(cmd_1586): シンClSel 4指標(Momentum/Sharpe/Calmar/Sortino)×K=3,4,5=12パターン完了。Sortino K=3がCAGR75.3%/Sharpe1.81/Calmar5.29/MaxDD-14.2%で全方式最高。**超越条件ではmomentum最優(2/3 PASS)。Sortino1/3(Bのみ)、Sharpe/Calmar0/3**。momentumはUWP3m(最短)で条件C PASS。指標変更で超越条件改善せず
- R28-回転率(cmd_1587): ClSel K=3は低回転率。シン平均入替0.77体/月(26%/月)、全入替(3体全交代)は0.9%。入替月vs非入替月リターン差は非有意(p=0.91)。**ローテーション自体はリターンに寄与していない。取引コストは限定的**。シン加速R-激攻が最頻選出(44.7%)
- R28-耐性(cmd_1588): ClSel K=3下落月(EW<-5%,11回)平均-9.76%でEW(-9.52%)微劣後だが最悪月-15.37%はEW(-18.67%)より3.3pp浅。**MaxDD-16.22%は3手法最浅**(EW-22.74%/Ward-20.78%)。COVID暴落2ヶ月底→翌月回復(計3ヶ月)。集中投資リスクは上昇月超過リターン(+0.69pp vs EW)で補完
- **R28-統合(cmd_1589): 全26方式統合比較+推奨**。CAGR TOP3: シンK2_Mom(75.8%)>K3_Sortino(75.3%)>K3_Mom(74.6%)。Calmar TOP3: K3_Sortino(5.29)>K3_Mom(4.60)>K3_Sharpe(4.49)。**3条件全PASS(超越+OOS劣化<30%+Turnover)はシンClSel K=4 Momentumのみ**。K=3 MomはCalmar劣化41.6%FAIL(CAGR劣化7.2%は閾値内)。K=3 SortinoはOOS未検証。**素材効果(シン>旧)が方式選択より支配的。旧ではClSel<FoF<EWだがシンではClSel>EW>FoF(逆転)** → `outputs/analysis/nested_fof/r28_unified_comparison.md`
- **⚠️R28-β分離(cmd_1591): ClSel K=3のCAGR向上95.8%はβ由来、α寄与わずか4.2%**。選出PF平均β=1.105 vs全体1.000(spread+0.105,p<0.0001)。β調整後: CAGR3.14%/Sharpe0.34/Calmar0.15/MaxDD-20.5%/UWP24m。**β調整後超越条件A/B/C全FAIL**。momentum選出は構造的に高βPFを掴む(最頻:シン加速R-激攻β1.233)。OOS: α寄与6.1%だが6窓中2窓でα負。**cmd_1581/1586の超越条件PASSはβ露出込み=αとしての付加価値は確認できない**(assumption_invalidation)。L517登録
- R28-SortinoOOS(cmd_1590): Sortino選出WF-OOS(8窓90m)。K=3: CAGR70.1%/MaxDD-29.0%(full-sample-14.2%から倍増)/Calmar劣化54.4%=**OVERFIT**。K=4: Calmar劣化31.1%=OVERFIT。K=5: 全指標30%未満OK。CAGR/Sharpe劣化率はSortino<Momentum(信頼性高)だがMaxDD劣化はSortino>Momentum(K=3: -103.9% vs -58.7%)。**OOS超越条件は全K全FAIL(0/3)**。**full-sampleのMaxDD優位はIS全体の選出バイアスでOOS消滅**(assumption_invalidation cmd_1586)。L518登録
- **R28-OOS超越(cmd_1592): OOS同士比較で超越条件全方式FAIL**。OOS個体ベスト>full-sample(CAGR96.8%vs92.2%、Calmar4.71vs3.90)。Momentum K=3/4/5全0/3FAIL、**Sortino K=3/4/5全0/3FAIL**、1/N EWのみ条件C PASS(1/3)。原因: (1)OOS個体ベスト上昇で閾値上昇 (2)ClSel OOS性能劣化の二重効果。**選出指標(momentum/Sortino)に関わらずOOSで超越条件未達**。L519登録
- **R28-IS感度(cmd_1593): IS長は結論を変えない。OVERFIT確定**。IS=36/48/60全てCalmar劣化>30%(46.4%/42.6%/41.6%)。MaxDD=-25.7%は全IS長で同一。CAGR/Sharpe劣化7-15%。Cross-metric CV=1-4%。**CLUSTER_LOOKBACK=36が律速**: IS≥36では末尾36ヶ月のみ使用されるためIS長を変えても銘柄選択は変化しない。最適IS=60(最小劣化)。L520登録
- **⚠️R28-4指標β調整(cmd_1596): 全4指標でβ調整後超越条件全FAIL(12判定全FAIL)**。α ranking: Sortino(10.0%)>Sharpe(8.5%)>Calmar(7.9%)>Momentum(4.2%)。βプロファイル: Momentum=高β(1.105,p<0.0001)、Sharpe=低β(0.938,p=0.0003)、Calmar/Sortino=中立(~1.0)。β調整後水準: 最良Sortino(adj CAGR7.5%/Sharpe0.73)でもUWP24m。**ClSel K=3のCAGR向上は全指標でβ露出に依存、αとしての付加価値(超越条件)は確認不能**。L521登録
- R28-Sortino β分離+OOS補完(cmd_1595): **Sortino選出はlow-β(avg β=0.98,市場中立)でα2.4倍**(α share10.0% vs momentum4.2%)。momentum=高β(1.11)は構造的。**選出指標の数学的性質がβプロファイルを構造的に決定**。OOS超越条件はSortino全K0/3 FAIL(momentum同様)。L522登録
- **R28-LB感度(cmd_1594): 最適LB=2ヶ月**。旧忍法K3 t=4.04、シンK4 t=3.75でLB=2が全K一貫最大。標準12M(旧t=2.75/シンt=1.48)は最適でない。**4-5m/10-11mピーク仮説否定**。Spearman rank相関は全LB非有意(ランキング全体の連続相関なし)。assumption_invalidation: cmd_1579/1583。L523登録
- **R28-K値β検証(cmd_1597): K=2-5全水準でβ調整後超越条件全FAIL(16判定全FAIL)**。α share: K=2(6.5%)→K=3(4.2%)→K=4(1.3%)→K=5(1.0%)。**K増加でα効率単調減少**。K=4の3条件唯一PASSはβ主導(assumption_invalidation: cmd_1589)。L525登録
- **R28-統合v2(cmd_1598): 全19cmd最終統合レポート** → `outputs/analysis/nested_fof/r28_final_unified_comparison.md`。β調整後超越12/12 FAIL、OOS全方式FAIL、IS感度OVERFIT確定。3選択肢: (A)ClSel不採用(α不在、EWで十分) (B)Sortino+短期LBで改良版検証 (C)ClSel概念保持+別α源泉探索
- **R28-短期LB BT(cmd_1599): LB=2mは全K全指標でLB=12mに劣後。R28結論覆らず**。β緩和あり(K=3: 1.105→1.021)でα share4.2%→9.2%倍増だがraw CAGR/Sharpe/Calmar/MaxDD(-29.3%)全悪化。**超越条件0/3**。LB短縮で持続性(t統計量)は改善してもBTパフォーマンスは低下。L526登録
- **⚠️R28-短期LB OOS(cmd_1600): LB=2mでOOS劇的改善。Calmar劣化41.5%→逆転-23.5%**。K=3: OOS CAGR82.6%/Sharpe1.78/Calmar3.11/MaxDD-26.6%。LB=12m OOS(K=3 Calmar劣化41.6%=OVERFIT)が**LB=2mで解消**。α寄与7.5%。**full-sampleではLB=12m優位だがOOSではLB=2m優位** — 過適合に強い

- R28-Sortino LB=2m BT(cmd_1601): **Sortino×LB=2mは全K全指標でLB=12mに劣後。α share3.4%**(LB=12m α10%の1/3)。β=0.951(low-β)で鉄壁/常勝モードに偏向。信号安定性STABLE(CV1.58<2.0)だが6m/12mより大幅不安定。momentum LB=2m(α9.2%)よりα低い。**Sortino×短期LBの組み合わせはα効率を悪化させる**
- **R28-LB=2m OOS超越(cmd_1602): raw超越条件C PASS(1/3)**。K=3/K=4ともUWP≤5でC PASS。**LB=2mが唯一ClSelでOOS超越条件Cを通す方式**。ただし**β調整後は0/3 FAIL**。LB=12m ClSel全方式0/3 FAILとの明確な差
- R28-Sortino LB=2m OOS(cmd_1603): **Calmar劣化56.9%=OVERFIT**(LB=12m54.4%と同水準)。momentum LB=2m(-23.5%)とは対照的。**Sortino過適合はLBでなく指標特性(下方偏差推定不安定性)に起因**。momentum LB=2mが最もα効率の高い方式(α7.5%)。L527登録

### R28 研究教訓（cmd_1579-1603）

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L516 | WF-OOS Calmar劣化はMaxDD悪化とCAGR劣化を分離評価すべし | cmd_1585 |
| L517 | momentum選出は高β構造バイアス(p<0.0001)。CAGR向上の95.8%はβ由来 | cmd_1591 |
| L518 | Sortino選出はfull-sample MaxDD優位がOOSで倍増し消滅する | cmd_1590 |
| L519 | OOS個体ベスト≠full-sample。超越条件の閾値はOOS固有値で再計算必須 | cmd_1592 |
| L520 | CLUSTER_LOOKBACK=IS長のときIS増加は選択に影響しない | cmd_1593 |
| L521 | β中立指標(Sortino/Calmar)のα効率はmomentumの2倍以上だが超越条件は不十分 | cmd_1596 |
| L522 | Sortino選出はlow-β PFを選びα成分2.4倍。選出指標がβプロファイルを構造的に決定 | cmd_1595 |
| L523 | overlapping-window mechanical correlation trap。LB>1でt統計量が桁違いに膨れる | cmd_1594 |
| L525 | ClSel K値増加でα効率単調減少(K=2:6.5%→K=5:1.0%)。分散はβ希釈+α希釈 | cmd_1597 |
| L526 | 短LB momentum選出はβ緩和するがリスク指標(MaxDD/UWP)を大幅悪化 | cmd_1599 |
| L527 | Sortino過適合はLB短縮で解消しない。指標特性(下方偏差推定不安定)に起因 | cmd_1603 |
| L529 | NewHigh/UWP選出指標はLB短区間(1-4m)で差別化力が弱い | cmd_1608 |

### 確定パラメータ（殿裁定 2026-03-19）

| パラメータ | DM2(青龍) | DM3(朱雀) | DM6(白虎) | DM7+(玄武) |
|---|---|---|---|---|
| **DNA** | 降りない | 債券方向スイッチ | VIX mean reversion | 構造的逆張り |
| absolute | LQD | TMF | ^VIX | SPXL |
| relative | TQQQ,TECL | TECL,TQQQ | TQQQ,TECL | XLU |
| safe_haven | **XLU固定** | TMV | **GLD固定** | TQQQ |
| top_n | 1, 2 | 1, 2 | 1, 2 | 1 |
| rebalance | **Mのみ** | **Bo, Beのみ** | **Qj, Qf, Qmのみ** | **Mのみ** |
| lookback | **10D〜12M** | **10D〜3M** | **10D〜6M** | **15M〜24M** |
| composite | 3-term許可 | **単一のみ** | 3-term許可 | **単一のみ** |

### DNA制約の根拠

| ファミリー | rebalance根拠 | safe_haven根拠 | lookback根拠（データ実証） |
|---|---|---|---|
| DM2 | 「降りない」は月次行動 | XLU=退避しても株の中に留まる。GLD不適 | 長期+短期composite +14pp。短期はノイズではない |
| DM3 | 3xレバwhipsaw防止 | TMV=債券正逆ペア必須 | short帯(1M-3M)が圧倒。long lookbackは無価値 |
| DM6 | VIXノイズ除去（年4回行動） | GLD=第三軸。XLUは株でありVIXとの独立性不足 | medium(4-6M)+短期compositeが全3指標1位。VIX mean reversionサイクル全体を捕捉 |
| DM7+ | 信号は鈍く月次で十分 | TQQQ=攻守逆転の意図的設計 | 15M=CAGR最大、24M=MaxDD最小。12M削除（劣後） |

### 旧方式(v1)からの変更点

- CPCV(Phase 3)廃止（FoF材料に完成品基準を当てていた）
- Triple-E事前フィルタ廃止 → CAGR/MaxDD/NHFで直接チャンピオン選出
- 脱相関K体選出廃止 → 各ファミリー3モード×1体
- safe_haven選択肢を1つに固定（DM2: GLD削除、DM6: XLU削除）
- rebalanceをDNA準拠で制約（全6種→1〜3種）
- lookbackをデータ分析に基づき制約（全18点共通→ファミリー別範囲）
- 32ユニット → 10体に簡素化（重複吸収: 激攻>常勝>鉄壁。朱雀・玄武で常勝消滅）
- （L413→§24, L414→§21, L415→§27に振り分け済 2026-03-28）

### データ分析サマリー（既存191,796パターンGS結果から抽出）

データ: `outputs/grid_search/shin_shijin_l1/metrics_DM*.csv`（cmd_1018、本番パリティ100%検証済み）

**DM2** DNA filter後 6,390パターン:
- 3-term composite (CAGR med 38.3%) > 2-term (37.2%) > 1-term (35.9%)
- CAGR 1位: `11M:60|5M:20|20D:20` (+53.7%) — long+medium+ultra_short
- MaxDD 1位: `5M:40|2M:40|15D:20` (-27.7%) — medium+short+ultra_short (※DM6で発見)

**DM3** DNA filter後 12,780パターン:
- short+ultra_short (CAGR med 25.4%) >> long (14.6%)
- CAGR 1位: `1M:80|15D:20` (+35.9%)
- MaxDD 1位: `5M:80|20D:20` (-47.7%)

**DM6** DNA filter後 19,170パターン:
- medium+short+ultra_short composite (MaxDD best -27.7%) がultra_short単独を大幅に上回る
- CAGR 1位: `4M:50|1M:50` (+46.6%, MaxDD -29.4%)
- MaxDD 1位: `5M:40|2M:40|15D:20` (-27.7%)
- 当初想定(ultra_short 10D-20Dのみ)をデータが否定 → 10D-6M compositeに拡大

**DM7+** DNA filter後 8パターン:
- 15M: CAGR +37.9%, MaxDD -45.6%
- 24M: CAGR +30.9%, MaxDD -26.1%
- 12M削除（全指標で15Mに劣後）

→ 設計書: `outputs/analysis/shin_shijin_design.md` §11
→ シン忍法v2結果: `outputs/analysis/shin_ninpo_v2_champions.csv`（21体確定、吸収0）
→ v1記録(参考): Phase 2分析 `shin_shijin_phase2_metrics_analysis.md`, Triple-E `cmd_1022_family_triple_e.md`

### シン忍法v2 GS結果（cmd_1080）

10体 × 7忍法 × 375 subsets = 173,625パターン。全21体ユニーク(吸収0)。
最強: 加速D-激攻 CAGR 86.6%。最堅: 加速D-鉄壁 MaxDD -13.6%。最高NHF: 変わり身-常勝 3.37。

本番登録: L0=L1 standard 10体 + L2 FoF 21体 = **31体**。手順書v2更新必要。

→ チャンピオン一覧: `outputs/analysis/shin_ninpo_v2_champions.csv`
→ 32体ユニバースGS: `outputs/analysis/shin_shijin_phase5_champions.md`（cmd_1075, 733,392パターン）

### Phase 5 全量GSチャンピオン（cmd_1075）

32体ユニバース × 7忍法 = 733,392パターン全量GS完走。

| 指標 | Best忍法 | 値 | ファミリー |
|------|---------|-----|----------|
| Best CAGR | kasoku_ratio | 63.17% | DM2(青龍) |
| Best Calmar | kasoku_ratio | 1.510 | DM6(白虎) |

- Best CAGR: 全7忍法でDM2(青龍)ファミリーがチャンピオン。top_n=1, rebalance=monthly統一
- Best Calmar: 5/7忍法でDM6(白虎)ファミリー。3-4体構成が多い(分散効果)

→ 詳細: `outputs/analysis/shin_shijin_phase5_champions.md`

### GS高速化（cmd_1029-1064）

| マイルストーン | 時間 | 手法 |
|-------------|------|------|
| 初期ベースライン | 23h | 逐次実行 |
| PPE導入(cmd_1031) | 2.8h | Preprocessed Execution全忍法適用 |
| T3 picks vectorize(cmd_1048) | 42min | ctx_buildボトルネック直撃 |
| 並列実行(8忍者) | **12min** | チャンク分割8並列 |
| numpy momentum cube(cmd_1064) | さらに改善 | pandas→numpy slice一括 |

本番パリティ完全一致が全高速化の絶対条件。→ `context/gs-speedup-knowledge.md`

### GS高速化第2世代（cmd_1827-1834）— 150min→1.9min(79x)

BATCH_CHUNK(30x) + 横展開(14x) + gs_runner並列(12x)の三重効果。WFメモリOOM解消(10.2GB→3.68GB)。lazy import(-79.6MB/worker)。gs-bench-gate WARN自動化。CSV I/O: numpy savetxt(float32)置換で270s→4.47s(60x)実装完了(cmd_1836)。BytesIO中継+年月プレフィックス追記パターン(L598)。→ `docs/research/gunshi_research_pipeline_meta_20260410.md` / `docs/research/gunshi_wf_engine_memory_fix_design_20260410.md`

### 奥義-シン忍法（cmd_1822/1840/1844）

**定義**: シン忍法20体を構成PFとしたL2 FoF。3目的(CAGR/NHF/MaxDD)×7忍法=21体。

**2つの方式の違い（殿指摘 2026-04-10）**:

| | シン忍法方式（正） | ALM方式（誤適用） |
|--|-------------------|-------------------|
| **選出方法** | GS全期間結果から事後的に最強パターンを選出 | WFエンジンでIS窓を毎月動的に切替えOOS検証 |
| **パラメータ** | 固定（全期間ベスト1つ） | 動的（毎月変わる） |
| **道具** | GS CSV直接読込み | l1_alm_wf_engine.py |
| **用途** | シン四神/シン忍法/奥義-シン忍法 | ALM四神/ALM忍法 |

**経緯**:
1. **cmd_1822 AC1**: GS新規実行（run_077_*.py --universe okugi_shin_ninpo_20.yaml）→ 7 CSV生成。これは正しい
2. **cmd_1840**: GS CSVにWFエンジン(l1_alm_wf_engine.py)を適用しチャンピオン選出 → **ALM方式を誤適用**。結果は参考データとして保持（破棄しない）
3. **cmd_1844**: GS CSVから事後的に3目的チャンピオンを直接選出 → **正しいシン忍法方式**

**殿指摘(2026-04-10)**: 「シン忍法にALM忍法をしていないか？」→ 奥義-シン忍法は シン忍法と同じ事後選出方式で作るべきところ、将軍がALM方式(WFエンジン)で作った。 「結果は破棄するなよ。それはそれで役に立つ」→ cmd_1840の結果は保持。 「しかし今回やろうとしていたものとは違う」→ cmd_1844で事後選出方式にて再実行。

**データ**:
- GS CSV: `outputs/grid_search/okugi_shin_ninpo_20body/cmd_1822_okugi_shin_ninpo_20body_{忍法}_grid_monthly_20260409.csv`（7本）
- ALM方式結果(参考): `queue/archive/reports/tobisaru_report_cmd_1840_20260410.yaml`
- シン忍法方式結果: `queue/archive/reports/hanzo_report_cmd_1844_20260410.yaml`（PASS。195万パターン→21チャンピオン選出。直列事後計算、OOMなし）

**cmd_1844結果（GS事後方式、正しいシン忍法方式）**: hanzoが7 GS CSV全量(2,859,025パターン。報告の1,958,050は合算ミス)からCAGR/NHF/MaxDDを直接事後計算。7忍法×3目的=21チャンピオン。吸収候補なし。cmd_1840(ALM方式)との比較でGS事後方式のCAGR優位(kawarimi+12.2%, yotsume+8.8%)。MaxDD目的はcmd_1840に選出方向の不整合発見(最悪値選出の疑い→decision_candidate)。

**OOM事故(cmd_1843)と教訓**: wf_runner.py並列ランナー(workers=2)でOOM Killer発動→エージェント死亡。殿裁定: 並列不要、直列1本ずつが正解。cmd_1843クローズ。→ `docs/research/gunshi_wf_oom_prevention_design_20260410.md`

**知見(2026-04-10検証済み)**: ALM方式(WF動的選択)とGS事後方式(全期間最強固定)の激攻・常勝チャンピオン14体中10体が同一pattern_id。全期間最強パターンはALM動的選択でも選ばれる傾向がある。差が出たケース: kawarimi CAGR(GS事後93.0% vs ALM 84.4% = +8.6pp), yotsume CAGR(88.4% vs 81.3% = +7.1pp)。鉄壁(MaxDD目的)はALM方式が最悪値を選出しており比較不能。GS CSV直接計算で独立検証済み(bunshin N2_0072: 両方式78.6%完全一致, kawarimi全222,300パターン中1位=N3_0771_24M 93.0%でcmd_1844と一致)。

- L601: cmd_1840 maximum_drawdown目的は最悪値を選出（GS事後とは逆方向）（cmd_1844）→ **修正済み(86f2e6ae)**: METRIC_DIRECTIONテーブル導入+MINIMIZE_SETから除去+MaxDD=0→NaN選出マスク。→ `docs/research/gunshi_maxdd_direction_bug_design_20260412.md`
- L602: oikaze MaxDD champion ID誤記 N2→N4（cmd_1845）
- L604: IS前半チャンピオンは全期間チャンピオンと完全に異なる(0/21一致)（cmd_1848）
- L605: CAGRチャンピオン系は構造的に過適合リスクが高い: 全忍法でMEDIUM以上、NHF/MaxDD系は全てLOW（cmd_1847）
- L620: L2奥義2×2因子分析でL1傾向継続だが縮小。GS固定の2種混在(DB vs champion)が一因（cmd_1878）

**道具磨き成果（副産物）**:
- OOM対策: load_data() numpy直読み化(cmd_1841)+GS側.npy同時出力(cmd_1842)。WF CSV読込OOM根絶。WF並列実行は禁止(LG025)
- **champion_selector.py**(2026-04-11軍師作成): GS CSV/.npyから3目的チャンピオンを直列選出。NaN-safe+float64+チャンク+方向テーブル+NHF NaN除外。195万パターン→25秒/1GB。cmd_1844と21/21完全一致。→ `docs/research/gunshi_champion_selector_design_20260411.md`
- **MaxDD方向バグ+ゼロバグ修正**(2026-04-12軍師修正, commit 86f2e6ae+2df25f6d): l1_alm_wf_engine.pyにMETRIC_DIRECTIONテーブル(champion_selectorパターン横展開, Level 5)導入。MaxDD負値×argmin=最悪選出→argmax=最浅選出に修正。ゼロバグ: MaxDD=0.0+UWP=0.0(NaN→0由来の偽ゼロ)→NaNマスクで偽チャンピオン防止。ALM四神全6 objective検証済み(argmax方向4つはゼロバグ不発生)。recalculate_fast.pyも予防修正。12テスト全PASS。→ `docs/research/gunshi_maxdd_direction_bug_design_20260412.md`
- **cpcv_analyzer設計**(2026-04-11軍師設計): CPCV(N=8,28fold)6メトリクス一括算出。パーティション事前計算で30倍高速化(kasoku_diff: 7.4秒/758MB)。→ `docs/research/gunshi_cpcv_analyzer_design_20260411.md`

**NaN-safe計算の必須知見(LG025)**: cumprodはNaN伝播で真チャンピオンが消失する(kasoku_diff CAGR実証)。prod方式+有効月数年率化+NaN月NHF除外+float64が正解。全事後計算ツールに埋込み済み

### パリティ検証（cmd_1097-1116）

| cmd | 対象 | 結果 | 教訓 |
|-----|------|------|------|
| cmd_1097 | L1シグナル突合 | GS関数にシグナル直接出力が必要(L422) | リターン逆推定では不十分 |
| cmd_1098 | L1リターン突合 | monthly_return_open列使用必須(L420/PI-008) | GS=Open-to-Open方式 |
| cmd_1106 | v2パリティ分析 | 不一致95%はRC4解像度差異(L425) | partial/MTD仮説は1.5%のみ(L424) |
| cmd_1115 | v2パリティ100% | Signal 1815/1815, Return 1815/1815一致 | resample月末修正(L427)+valid_start_date修正(L428) |
| cmd_1116 | 追加検証 | 非決定的順序+partial-month初月(L429) | — |
| L461 | oikaze batch | precomputed momentum_cube picks vs 本番MomentumFilterBlock選出に乖離(cmd_1200) | batch側のpick計算パスが本番と異なる |
| L473 | ^VIX/DTB3 cache汚染 | price_data_cacheに非市場ティッカーを含めると日付インデックスリサンプルでpct_change参照ズレ(cmd_1243) | **[PI-010]** |
| L479 | selection FoF init月検証不可 | selection付きFoFのinit月はholding_signal=Noneで独立検証不可(cmd_1270) | — |
| L480 | selection FoF初月holding_signal=NULL | selection-based FoF初月のmonthly_returns.holding_signal=NULL問題(cmd_1271) | — |
| L482 | selection-block FoF本番検証可 | selection-block FoFは本番holding_signalベースで検証可。Cash月はスキップ(cmd_1269) | — |

→ パリティ修正詳細: `context/dm-signal-core.md` §4 L419/L427/L428

### CPCV/相関/パターン分析（cmd_1019-1026）

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L351 | CPCV群分割で割り切れない場合のnp.array_split+サイズ差ログ標準化 | cmd_1020 |
| L352 | CPCVでlower-is-betterメトリクス使用時はスコア反転必要 | cmd_1020 |
| L354 | L1フルデータ(191K変種)では全ペア相関が時間的に不安定 | cmd_1019 |
| L355 | DM7+ファミリーPASS候補全4体がGLD系でXLU系全滅 | cmd_1024 |
| L356 | 32体ユニバースのパターン爆発はsize4が86.8%支配。加速が全体の66.1% | cmd_1026 |

⚠ 登録進捗管理はチェックリストに移行済み→`context/checklist-shin-v2-registration.md`

### ネステッドFoF Phase1 (cmd_1410)

→ 成果物: `outputs/analysis/nested_fof/` (CSV3+YAML1+PNG1+PY1)
→ スクリプト: `scripts/analysis/nested_fof/phase1_fof_baseline.py`

| 指標 | R1(EW21) | 5体精鋭 | 最強個別(加速D-激攻) |
|------|----------|---------|---------------------|
| CAGR | 58.6% | 67.2% | 88.0% |
| MaxDD | -20.4% | -15.4% | -26.5% |
| Sharpe | 1.76 | 2.03 | — |
| NHF | 62.9% | — | — |

- 21体平均ペア相関0.682（高）。同一ファミリー内0.74-0.99、クロスファミリー0.22-0.59
- 少数精鋭(5体): 加速D-激攻/四つ目-鉄壁/加速D-鉄壁/分身/四つ目-激攻。Greedy低相関選択
- ⚠ 四つ目-激攻CAGR差異0.226 (GS=0.714 vs calc=0.488)。MultiView4窓union+タイミング要調査 (L493)

#### 将軍独立分析 — R2設計核心 (cmd_1410事後)

→ 詳細: `docs/research/nested-fof-preliminary-analysis.md`

| 手法 | CAGR | MaxDD | Sharpe | 備考 |
|------|------|-------|--------|------|
| R1(EW21) | 58.6% | -20.4% | 1.76 | 全22戦略中最高Sharpe |
| Greedy Best4 EW | 76.4% | — | — | 事後選択（OOS不明） |
| ★Ward4クラスタ→各最強1体→EW | 73.2% | -13.0% | 2.06 | 理論ベース。パラメータ0 |
| Ward4クラスタ OOS(前半選抜→後半テスト) | 92.5% | — | — | 網羅探索77.7%を+14.8%上回る |

- **R2最有力**: クラスタベースEW（パラメータ0）。理論ベース低相関>統計ベース
- **構造的核**: 加速D-激攻（最高CAGR88%+最低平均相関0.48）。全手法・全期間で選出

#### ウォークフォワード確定結果 (131ヶ月OOS 2015-03〜2026-01)

| 手法 | CAGR | MaxDD | Sharpe | パラメータ |
|------|------|-------|--------|-----------|
| R1 (EW21) | 63.8% | -20.4% | 1.79 | 0 |
| 4cl-AllEW (選抜なし) | 75.2% | -17.3% | 2.08 | 0 |
| **R2 (WF-Cluster BestCAGR EW)** | **80.8%** | **-18.6%** | **2.02** | 0 |
| R5候補 (Cluster+6M Momentum) | 83.3% | -23.1% | 2.05 | 1 |
| InvVol | 79.6% | -17.1% | 2.07 | 0 |

- クラスタ数頑健性: 3-10全てR1超え。4がスムーズなCAGR/Sharpeピーク
- クラスタ安定性: T=144-167で同一4体に収束（加速D-激攻+抜き身-激攻+加速R-鉄壁+追い風-激攻）
- ~~R4(Half-Kelly): 将軍予備分析94.0%~~ → **WF実装(cmd_1412): CAGR69.9%, MaxDD-29.6%, Sharpe1.79。R2に全指標劣後=FAIL**
- 予備94%→実装70%の乖離=Kellyのμ/Σ推定が小標本(N=4)で不安定。DeMiguel(2009)N<50 EW優位と整合
- R4キャップ感度(cmd_1412 AC4): cap0.15-0.50の6パターン全てR2未達。cap0.50でSharpe1.91(R2に漸近=EW化)
- ~~R6_ext(R2+外部レジーム cmd_1412 AC3): CAGR72.7%, Sharpe2.16~~ → **ルックアヘッドバイアス確定(軍師検証)**
  - レジーム: VIX>80pctl AND SPY<10M SMA → 3段階(risk_on97M/caution21M/risk_off13M)
  - **lag-1補正後(前月末データ使用=Faber2007準拠)**: CAGR61.2%, MaxDD-20.7%, Sharpe1.87 → R2にもR1にも劣後
  - 131ヶ月中43ヶ月(32.8%)でレジーム判定変動。バイアス影響は「限定的」ではなく構造的
  - r6_ext_regime.py L153: external_df.loc[t](当月末)使用が原因
- **R7(逆ボラ加重 cmd_1413 AC1)**: CAGR73.4%, Sharpe1.933, MaxDD-20.4%。SharpeとMaxDDでR2超え。**最有望補完候補**
  - R2損失月8/10月で改善(平均+0.60%)。2020-03(COVID): R2=-13.0%→R7=-8.2%(+4.8pp)
  - 弱点: 2022-12 R2=-18.3%→R7=-20.4% — 低ボラ体集中が裏目
- **R8(絶対モメンタム cmd_1413 AC1)**: CAGR73.7%, Sharpe1.896, MaxDD-21.5%。R2と実質同一(BestCAGR戦略は常に正モメンタム→フィルタ不発)
- **R9(VIX連続スケーリング lag-1 cmd_1413 AC2)**: CAGR54.9%, Sharpe1.950。cash60/131月(45.8%)でCAGR壊滅。Sharpe微改善のみ
- **R6lag1(離散レジーム lag-1 cmd_1413 AC2)**: CAGR61.2%, Sharpe2.00(最高), MaxDD-20.7%。CAGR犠牲大
- **ドロップ確定**: R3(HRP/InvVol改善微小), R4(EWに劣後), R5+R4(逆効果), **R6_ext(ルックアヘッドバイアス)**, R8(R2と同一), R9(CAGR壊滅)
- **★CHAMPION確定: R2(Ward4cl EW)** — CAGR74.5%, Sharpe1.92, MaxDD-21.5%。パラメータ0。全ルール中唯一R1を全指標で上回る
- **補完候補**: R7(逆ボラ)はSharpe+MaxDDでR2を上回り損失月も改善。ブレンド検討の余地あり
- 分散分解: R2の優位はσ²低減ではなくμ上昇(+0.126)が支配。効率的フロンティア上方移動
- → 詳細: `docs/research/nested-fof-preliminary-analysis.md`

### R10-R14: 手法拡張+ローリング検証 (cmd_1417-1422)

→ 成果物: `outputs/analysis/nested_fof/r10_*` 〜 `r14_*`

| 手法 | CAGR | Sharpe | MaxDD | Calmar | 備考 |
|------|------|--------|-------|--------|------|
| **R10(Rolling Top4-Sharpe EW, cmd_1417)** | 67.9% | 1.82 | — | — | R2に-6.5%劣後。ローリングSharpe選抜 |
| **R11 M4(GreedyMinCorr K=4, cmd_1419)** | 82.8% | 2.17 | -11.5% | 7.19 | 5手法中Sharpe/Calmar最良。R2と4体中3体共通 |
| **R12 K感度(cmd_1420)** | — | — | — | — | Ward最適K*=5(Sharpe1.97WF)。K=4次善。K3→6脱落なし安定構造 |
| **R13 GreedyK5統合(cmd_1421)** | 85.6% | 2.19 | -12.7% | 6.72 | 4手法事後版Sharpe最良。5体目=抜き身-激攻 |
| **R14 Rolling Ward K=5(cmd_1422)** | 91.3% | 2.18 | -15.1% | 6.06 | ローリング最良。事後版減衰-2.7%=実運用可能 |
| **R15 K感度(cmd_1423)** | 91.3% | 2.18 | — | — | K*=5(最適)。K5/K6プラトー。事後K=5と一致 |
| **R16 LB感度(cmd_1424)** | — | 2.18 | — | 6.06 | LB*=36ヶ月(最適)。broad peak=頑健。[24,36,60]近傍良好 |
| **R17 2Dグリッド(cmd_1425)** | — | 2.13 | — | — | (K*,LB*)=(5,36)=最適。peak_ratio=1.073=頑健。共通期間 |
| **R19 拡張2D(cmd_1427)** | — | 2.19 | — | — | 99通り。最適(K=4,LB=30)。K=5,LB=36=97.5%。peak_ratio=1.12 |
| **R20 時間安定性(cmd_1428)** | — | — | — | — | 48窓×3メトリクス。Sharpe:K=4-5最適54%。3メトリクスK一致0% |
| **R21 因果切り分け(cmd_1429)** | — | 2.13 | — | — | Ward寄与97.2%,モメンタム2.8%。ランダム100回mean=2.07。Sortino:Ward106.1% |
| **R22 3方式統一比較(cmd_1430)** | — | 2.12 | -13.5% | 6.44 | 二段EW=BestCAGRの99.5%。MaxDD/Calmarは二段EW優位。体数不均衡比率avg6.55 |
| **R23 行動メトリクス(cmd_1431)** | — | — | — | — | 48窓ローリング。二段EWとBestCAGRは46-48/48窓同値。連敗全窓同値。行動面でもほぼ同等 |
| **R24 二段EW2Dグリッド(cmd_1432)** | — | — | — | — | 99通り。最適(K=4,LB=30)=BestCAGRと同一。Sharpe73/99優位、MaxDD86/99優位。peak_ratio=1.09 |
| **R25 四神12体2Dグリッド(cmd_1434)** | — | 1.48 | — | — | 90通り。最適(K=3,LB=24)。TwoStageEW優位83.3%(Sharpe)。R24(73.7%)より高優位率。12体でもロバスト |
| **R26 全PF65体2Dグリッド(cmd_1435)** | — | 1.49 | — | — | 171通り。最適(K=6,LB=18)。Sharpe優位70.8%,MaxDD優位95.9%。peak_ratio=1.064。65体でもロバスト |

- R13結論: GreedyK5 > GreedyK4(Sharpe) > WardK4(=R2) > WardK5(静的)。5体目: Greedy=抜き身-激攻、Ward=抜き身-鉄壁(異なる)
- R14結論: ローリングWard K=5が最良。GreedyK5は事後版減衰-17.1%で不安定。全手法R1(Sharpe1.87)を大幅超過
- R15結論: ローリング版K*=5(Sharpe2.1756)。事後版K=5と一致→データスヌーピングバイアスなし。K5/K6プラトー(2.1756 vs 2.1608)。gradual peak=中程度パラメータ感度。選抜安定性: K増でtop1選出率59%→95%、TO低下(22.5%→13.2%)
- R16結論: LB*=36ヶ月(Sharpe2.1756)=cmd_1422完全一致。broad peak=頑健(LB24:2.11, LB60:2.13も良好)。LB48だけやや低下(1.99)。TO: LB増で低下(24%→12%)。Calmar: LB36(6.06)最良
- R17結論: 2次元グリッド30通り。最適(K*,LB*)=(5,36) Sharpe=2.133(共通期間)。peak_ratio=1.073(<1.3)=緩やかな山=頑健。Sharpe std=0.0756(変動極小)。交互作用: LB短→K=4最適、LB中→K=5最適。K=5,LB=36は最適そのもの(100% of peak)
- R19結論: 拡張99通り(K=2-12×LB=12-60)。最適**(K=4, LB=30)** Sharpe=2.1869に移動。K=5,LB=36=97.5%(2.5%差)でプラトー内。peak_ratio=1.12=頑健。Sharpe std=0.1064。LB=30付近にスイートスポット(K=4-6高Sharpe帯)。K≥9やLB≥48は性能低下。K=2は常に最低域
- R20結論: 時間安定性テスト(48窓×3メトリクス)。**Sharpe: K=3-6最適68.8%, K=4-5最適54.2%, LB=18-36最適93.8%**。K=4,LB=30平均ランク11.5/99(上位12%)。**3メトリクス間K一致度0%**(Sharpe→K=4-5, CAGR→K=2, MaxDD→K=3)。K=5,LB=36: Sharpeランク14.4, CAGRランク27.0, MaxDDランク32.2。**R15-R20統合結論: Sharpeベースの最適帯K=4-5,LB=30-36はrobust。ただしCAGR/MaxDDでは最適Kが異なる(メトリクス依存性あり)。殿がヒートマップ+数値で最終判断**
- R21結論: BestCAGR vs ランダム×100因果切り分け(K=5,LB=36固定)。**Ward寄与率97.2%(Sharpe)**、モメンタム効果わずか2.8%。BestCAGR Sharpe=2.1333、ランダム平均=2.0735(std=0.0948)。WorstCAGR=2.0689(ランダム70パーセンタイル)。**Sortino: Ward効果=3.6205、モメンタム効果=-0.2079(微負)**→Ward構造が支配的価値源泉。BestCAGR選択の付加価値は統計的にわずか
- R22結論: 3方式統一比較(K=5,LB=36固定)。**二段EW Sharpe=2.1228=BestCAGR(2.1333)の99.5%**。モメンタム仮定ゼロでもWard構造だけで高パフォーマンス維持。**MaxDD: 二段EW-13.5%<BestCAGR-14.9%。Calmar: 二段EW6.44>BestCAGR6.19**=リスク面で二段EW優位。クラスタ間体数不均衡比率avg6.55(min3.50,max11.00)。ランダム平均=2.0735(R21完全一致)
- R23結論: 3方式行動メトリクスローリング(W=24ヶ月×48窓)。**二段EWとBestCAGRは46-48/48窓で同値**。最大連敗は全窓同値。BestCAGRが微差で優位(NHF:-0.4%, underwater:+0.4%)。ランダム平均は両方式より劣位。**純粋構造(二段EW)は行動面でもBestCAGRとほぼ同等**
- R24結論: 二段EW2Dグリッド99通り(K=2-12×LB=12-60)。**最適(K*,LB*)=(4,30)=BestCAGR(R19)と同一(移動なし)**。Sharpe73/99セル(73.7%)で二段EW優位。**MaxDD86/99セル(86.9%)で二段EW優位(浅いDD)**。ただしCAGR34/99(34.3%)で二段EW劣後。peak_ratio=1.09=頑健。**二段EWはSharpe/リスク面で広範に優位、リターン(CAGR)ではBestCAGR優位**
- R25結論: シン四神v2 12体2Dグリッド90通り(K=2-11×LB=12-60)。**最適(K*,LB*)=(3,24) Sharpe=1.4785**。BestCAGR最適(K=11,LB=36) Sharpe=1.4705。**最適点移動あり(R24:K=4,LB=30→R25:K=3,LB=24)**。TwoStageEW優位83.3%(Sharpe)>R24(73.7%)。共通期間=2017-04~2026-02(107ヶ月)。**12体でも二段EW構造はロバスト、かつ優位率がR24(21体)より向上**
- R29f-shin結論(cmd_1606): **シン忍法v2 20体 LB×4指標2Dグリッド ClSel WF-OOS**。48セル全実行。**BEST: LB=6 Momentum CAGR=88.5%, Calmar劣化=-5.1%(OOS>FS)**。R28ベスト(LB=2 Mom 82.6%)を+5.9pp上回る。EW20(72.3%)を+16.2pp上回る。殿基準全PASS=2/48(MaxDD>SPYがボトルネック)。Calmar劣化<30%=33/48。Momentum指標がCAGRトップ3独占 → `queue/reports/tobisaru_report_cmd_1606.yaml`
- R29f-kyu結論(cmd_1607): **旧忍法15体 LB×4指標2Dグリッド ClSel WF-OOS**。48セル全実行。**BEST: LB=2 Calmar CAGR=77.4%, 劣化9.2%**。殿基準PASS=38/48。Calmar劣化<30%=48/48(全セル、過適合なし)。Momentum列がCAGR最高値独占(LB5:71.9%,LB2:71.3%)。**旧忍法は殿基準PASS率が大幅に高い(38/48 vs shin 2/48)=MaxDDが浅い** → `queue/reports/kotaro_report_cmd_1607.yaml`
- R29g-shin結論(cmd_1608): **シン忍法v2 20体 NewHigh+UWP追加2指標×12LB=24セルWF-OOS**。殿基準20/24 PASS。6指標統合BEST=LB6 Momentum(CAGR 88.5%, Degrad -5.1%)が依然最強。**NewHigh/UWPはLB1-4で同一体を選出(差別化不可)、LB5+で分岐**。NewHigh LB=11最高CAGR(71.6%)、UWP安定64-69% CAGR。既存4指標より低CAGRだが低MaxDD(-20~-23%)/低UWP(3-7m)で安定性優位 → `queue/reports/hayate_report_cmd_1608.yaml`
- R29g-kyu結論(cmd_1609): **旧忍法15体 NewHigh+UWP追加24セルWF-OOS**。殿基準14/24 PASS。6指標統合最適LB=2 Calmar(CAGR 77.4%, 劣化9.2%)。**R29f-kyu(4指標48セル)とマージして6指標統合ヒートマップ出力** → `queue/reports/kagemaru_report_cmd_1609.yaml`
- R30-OPTICS denoise(cmd_1623): **MP法denoised相関+OPTICS密度ベースClSel vs Ward K=3(raw)**。9LB値比較。Ward 7/9 LB値でSharpe/CAGR/MaxDD優位。OPTICS LB>=24でxi抽出が単一クラスタに退化(N=20小集団でreachability同一化)。LB=18: OPTICS Sharpe=1.836微優位だがMaxDD-0.27(Ward-0.21)劣位。β調整: 両手法ともalpha負。**密度ベースClSelはN>=50以上で有効。小集団にはWard K指定が適切(L530)** → `outputs/analysis/nested_fof/r30_denoised_optics_vs_ward.yaml`
- R30-shin結論(cmd_1604): **20体全個体WF-OOS(IS=60m,OOS=12m,step=12m,8窓)+buy&holdベンチマーク**。面: CAGR>TQQQ&TECL=20/20、過適合SUSTAIN=20/OVERFIT=0(全体OOS≥FS)。殿基準ALL_PASS=7/21(**MaxDD>SPYがボトルネック**: 6/20のみ)。点: CAGR1位=加速D-常勝(96.8%)、alpha>0=8/20。**ClSel K=3 LB=2m: CAGR75th(rank6/20)/Sharpe95th(rank2/20)**。EW20 OOS: CAGR72.3%/Sharpe1.77/Calmar3.18 → `queue/reports/hanzo_report_cmd_1604.yaml`
- R26結論: 全PF65体2Dグリッド171通り(K=2-20×LB=12-60)。**最適(K*,LB*)=(6,18) Sharpe=1.492**。**Sharpe優位70.8%(121/171)、CAGR優位67.3%、MaxDD優位95.9%(164/171)**。mean Sharpe=1.402, std=0.048, peak_ratio=1.064=頑健。R24(21体)overlap99セルでR26全敗(65体=分散でSharpe水準低下。構造は頑健)。**最適K: R24=4→R25=3→R26=6（体数増でK増加傾向）。LB: R24=30→R25=24→R26=18（体数増でLB短縮傾向）。三段階(12→21→65体)全てで二段EWのSharpe/MaxDD優位構造は一貫**
- R11 M4とR2の差分: 追い風-鉄壁(M4) vs 追い風-激攻(R2)のみ。MaxDD大差(-11.5% vs -16.7%)
- TO(月次入替率): Ward K=5=19.6%, Greedy K=4=22.6%。Ward低回転で実運用有利
- R27結論(cmd_1436): **WardTwoStageEWビルディングブロック実装**。R1-R26研究結論を汎用モジュール化(`scripts/analysis/nested_fof/building_block.py`)。内部K×LBグリッドサーチで最適パラメータ自動決定。R24/R25/R26の3データセット(21体/12体/65体)で既知最適(K*,LB*)再現確認+Sharpe 1e-4以内一致。コールドスタート(データ不足時1/N EW)・k_max自動クランプ実装済み
- R27-旧PF結論(cmd_1441): **旧忍法15体+旧四神12体のWard+TwoStageEW 2Dグリッド分析**。旧忍法: K*=4,LB*=24,Sharpe=2.01,TwoStageEW優位率49.6%。旧四神: K*=4,LB*=12,Sharpe=1.55,TwoStageEW優位率76.7%。合計27体: K*=12,LB*=24,Sharpe=1.75。R25(12体,1.48)/R26(65体,1.49)より高Sharpe → `queue/archive/reports/hayate_report_cmd_1441_20260330.yaml`
- ネオ五神偵察(cmd_1442): **GLD/USO/TIPの既存4absolute資産との相関偵察**。候補-既存max|r|: GLD=0.343(最有力), USO=0.378(次点), TIP=0.769(LQD冗長→不適)。危機時: GLD=利上げ時独立(全<0.17)、USO=COVID時VIX連動(0.719)、TIP=両危機でLQD完全連動。GLD独自ドライバー(中銀/地政学/インフレ) → `queue/archive/reports/hanzo_report_cmd_1442_20260330.yaml`
- **Standard PF前処理研究日誌**: 思考・判断・結果の時系列記録。候補8手法の選別経緯、本命2つ(Gerber+LW)の研究設計、結果記入欄 → `docs/research/standard-pf-preprocessing-journal.md`
- **前処理研究の全思考過程（殿との対話記録）**: FoF天井→Standard PF転換→EMA+112%/L1+383%→overfit警告→OOS検証。殿の全転換点含む → `memory/dialogue_preprocessing_research_20260331.md`（経験的知識。圧縮禁止。過程が本体）
- BB前処理偵察(cmd_1627): **モメンタム系3BB+全7BB前処理不在確認+注入ポイント特定**。全BB共通基盤=calculate_composite_momentum_vectorized、生close直接pct_change(前処理なし)。注入ポイント5箇所: (A)ブロック内price取得後(副作用小・推奨), (B)base.py load_ticker_prices共通層, (C)vectorized_momentum.py計算基盤層, (D)ティッカー選出ロジック内(Gerber相関), (E)新規SelectionBlock(Gerber独立BB)。加速BBは短期/長期ratio/diffで平滑化と構造的に重複しない(組合せ可)。MonthlyReturnMomentumFilterはDB直接読込で独立。recalculate_fast.py Phase2 momentum_cache生成パスは前処理導入時に整合要件あり。研究仮説3件: H1-EWMA平滑化SNR改善, H2-Gerber閾値低相関選出, H3-対数リターン頑健性 → `queue/reports/hanzo_report_cmd_1627.yaml` / `queue/reports/kagemaru_report_cmd_1627.yaml`
- EMA平滑化研究(cmd_1629): **5PF×5span(0/5/10/21/42)=25条件。close→EMA(span)→pct_change→momentum**。**DM3 span=42でCAGR2倍(0.11→0.23)/Sharpe45%改善**が注目結果。DM7+(504D lookback)はEMA影響ほぼなし。DM6(15D短期lookback)はEMA劣化(遅延が有害)。**EMA効果はlookback依存: 短期PFに恩恵、超短期に有害、長期に不変**。span=0 baseline誤差2-8%(リバランスタイミング簡易実装差) → `queue/archive/reports/hayate_report_cmd_1629_20260331.yaml`
- Gerber gate-level threshold研究(cmd_1628): **65PF×5k(0.0/0.25/0.5/0.75/1.0)=325件。gate判定: diff=mom(asset)-mom(DTB3)>k*σ(diff)→BUY**。k=0.0=本番一致(match率85-97%、リバランス簡易実装差)。才蔵return-level GS1(FAIL)→半蔵gate-level修正。L532: cmd仕様の適用レベル(gate vs return)を実装前にコード注入ポイントと照合確認すべし → `queue/archive/reports/hanzo_report_cmd_1628_20260331.yaml`
- LW shrinkage研究(cmd_1630): **65PF×8config(baseline+ApproachA/B/C×5閾値)=520 walkforward runs**。3アプローチ比較: A(リスク調整momentum/σ)=多ticker PFで最大乖離、B(shrinkage α*mean+(1-α)*momentum)=α小で効果微小、C(z-score threshold gate)=**threshold≥0.5で有意差、≥1.0で顕著**。単一ticker PFでは全アプローチ同一(共分散shrink対象なし)。sklearn LedoitWolf使用 → `queue/reports/kagemaru_report_cmd_1630.yaml` / `outputs/analysis/standard_pf_preprocessing/ledoit_wolf_study_results.yaml`
- FFD研究(cmd_1631): **5PF×5variant(baseline/d_opt/0.3/0.5/0.7)。結論: FFD×AbsoluteMomentumは構造的に非機能**。FFD値にprice level成分が残存→stock FFD>>DTB3 FFD→AbsMom判定が常時通過→Whipsaw=0で全期間ロング固定。FFDは入力前処理としてMomentumFilterランキングには影響するが、AbsMomゲートとしては原理的に無効。d_opt: TQQQ/TECL/XLU=0.25, GLD/LQD/SPXL=0.20, TMF=0.15, TMV=0.05, VIX=0.00(既定常), DTB3=1.00 → `queue/archive/reports/tobisaru_report_cmd_1631_20260331.yaml`
- EMA 65PF全数評価(cmd_1632): **65PF×5span(0/5/10/21/42)=325件walkforward**。cmd_1629(5PFのみ)を65PF全数に拡張。pipeline_configからreference_assetモードstandard PFを自動検出。シン四神12体含む全PFに5指標(CAGR/Sharpe/MaxDD/whipsaw_count/match_rate_vs_span0)算出。ema_smoothing_results_full.yaml出力。commit bd88221d → `outputs/analysis/standard_pf_preprocessing/ema_smoothing_results_full.yaml`
- Kalman Filter研究(cmd_1634): **65PF×4mode(auto_EM/fixed_qr0.01/0.1/1.0)=260件walkforward**。1D random walk+noise KF。auto EM推定(B3)平均CAGR=0.3386、fixed最良qr_0.1(B1)=0.3516。**auto推定はbest fixedより-0.013(やや劣る)**。auto推定のQ/R比は大半4-7に収束(高応答=軽い平滑化)。Benhamou(2018)準拠。半蔵impl → `outputs/analysis/standard_pf_preprocessing/kalman_filter_results.yaml`
- L1 Trend Filter研究(cmd_1633): **65PF×5lambda(0/1/10/100/1000)=325件walkforward**。cvxpy凸最適化でL1区分線形トレンド抽出。**ユニバーサル最良lambda=10(mean CAGR=34.62%)**。per-PF best分布: lam0=14,lam1=17,lam10=8,lam100=12,lam1000=14(均等→overfitリスク)。**22/65PF(34%)に>5pp neighbor gapのoverfit警告**。影丸impl → `outputs/analysis/standard_pf_preprocessing/l1_trend_filter_results.yaml`
- DM6.5 VIXレジーム×中期lookback研究(cmd_1681): **6仮想PF(lookback={42,63,126}×rebalance={M,Q})×4条件=24件walkforward**。DM6構成固定でlookbackを中期に変更。**Q42 Kalman(auto) CAGR 0.524 > DM6 15D baseline 0.504**。「DM6系は前処理で常に劣化」は15D固定条件限定の仮説→中期lookbackでは反例あり。才蔵impl → `outputs/analysis/standard_pf_preprocessing/dm6_5_study_results.yaml`
- DM6.5拡張 全12lookback研究(cmd_1684): **9 lookback(1M~12M)×72条件walkforward + cmd_1681統合12 lookback横比較テーブル**。Q rebalance>M全域。Q_105D(5M)+EMA CAGR=0.468、Q_84D(4M)+L1 CAGR=0.437が有望。7M+はCAGR低下。殿予想の4M/5M確認。注意: cmd_1681=kalman_auto、cmd_1684=ema_span_21で第4条件不一致(L535)。小太郎impl → `outputs/analysis/standard_pf_preprocessing/dm6_5_extended_results.yaml`
- **研究WF共通エンジン(cmd_1691+R31-R37)**: research_engine.py完成。14関数+Strategy Pattern+SSA/FoF/FDA統合。**196s→1.58s(124x)+config 707x**。R31-R34: 高速化。R35: SSA統合。R36: FoF共通関数統合。R37: FDA統合。全研究スクリプトがresearch_engineをimport → `scripts/analysis/standard_pf_preprocessing/research_engine.py`
- シグナル相関変化分析(cmd_1701): **65PF×2条件 相関行列+尖り削減量×FoF Δcagr回帰**。r=-0.199→尖り削減≠FoF悪化主因。depth増幅(L538)が支配変数。L539教訓。小太郎impl → `outputs/analysis/standard_pf_preprocessing/signal_correlation_analysis.yaml`
- FoF全59体EMA間接波及(cmd_1700): **59 FoF×2条件=118WF**。avg_Δcagr=-0.087。改善11/59。**ネスト深度増幅発見**: depth=1(四神)正効果→depth=2(旧忍法)損失増幅→depth=3(Ward)最大損失Δ=-0.182。L538教訓。影丸impl → `outputs/analysis/standard_pf_preprocessing/fof_all59_ema_results.yaml`
- FoF momentum実態監査(cmd_1707): **active 59 FoF = EW 17 / momentum 19 / nested 23**。terminalは58/59が`EqualWeight`だが、**selection_block=0は17/59のみ**。FoF momentum実行経路は `component cumulative returns -> selection block(if any) -> terminal`。cmd_1700スクリプトの「all 59 FoFs are EqualWeight(selection_block=0)」前提は不正確で、L0前処理は42体の選抜結果にも波及しうる → `docs/research/cmd_1707_fof_momentum_audit.md`
- Layer3最終出力前処理研究(cmd_1687): **Ave-X/裏Ave-X × 2条件(baseline/L0 EMA span=5) = 4 WF**。三層研究完結。EMA span=5間接波及→最終出力: Ave-X CAGR+2.2pp(0.359→0.381)/Sharpe+0.064、裏Ave-X CAGR+1.3pp(0.423→0.436)/Sharpe+0.037。MaxDD不変。本番投入でユーザー体験改善確定。半蔵impl → `outputs/analysis/standard_pf_preprocessing/layer3_final_output_results.yaml`
- FoF第二層前処理研究(cmd_1683): **6 FoF(四神+Ave-X+裏Ave-X)×3条件(baseline/間接波及/直接適用)=18件walkforward**。L0 EMA間接波及: 朱雀+0.11 CAGR(最大)。直接適用(C-B)=全FoFで0.0(EW FoFのためL1 momentum pathなし)。疾風impl → `outputs/analysis/standard_pf_preprocessing/fof_layer2_preprocessing_results.yaml`
- PE gate研究(cmd_1635): **65PF×16configs(4window[12,24,36,48M]×4threshold[no_gate,0.7,0.8,0.9])=1040件walkforward**。Bandt&Pompe(2002)準拠PE(m=5,τ=1)。**m=5ではPE値が低くgate大部分未発火**。window=12/24はPE<全閾値(ベースラインと同一)。window=36/t=0.7のみ発火(CAGR win率21.5%)。window=48/t=0.7発火(win率7.7%)。**PE gateは月次リターンのm=5では実用的に無効**。L533: m=5は120パターンの疎分布→低閾値(0.3-0.5)検討要。疾風impl(才蔵・小太郎FAIL→3回目) → `outputs/analysis/standard_pf_preprocessing/entropy_gate_pe_results.yaml`

