<!-- gist-master: 1e0cab30de1efc851d4048858e8ece6d dm-fof-tiebreak-determinism-asis-tobe_20260817.md -->
# FoF子PF選択の決定性 AsIs/ToBe — 浮動小数点ノイズで確定履歴が動く穴を「同値帯ε+根拠あるtie-break」で閉じる

## 原則（親文書と同じ。殿裁定 2026-08-15 / 2026-08-17 01:42）

- ToBeは構造的に不可能でない限り妥協しない。AsIsは現実のコードそのもの。変更履歴は書かない（見出し=版+タイムスタンプ、粒度は末尾注釈）。
- 裁定は「事実→制約→判断→効果」の因果で記す。
- **実装は殿の指示まで行わない**（2026-08-17 12:35 殿「決定ではなくチャットとして会話しよう」／12:39「今は情報待ちだね」）。情報待ち=cmd_4330(read-only偵察: 現行の比較キー・同値時の順序決定・価格取込み精度・修正3案の影響範囲)。

発端: 2026-08-17 10:47 JST SIGNAL CHANGE ALERT 6,477件/35 FoF PF/2014-06〜2026-06 → 三段確認(cmd_4329)で「価格は変わった、ただし浮動小数点ノイズ級」「cronとfullは一致」「35 FoF全体に広域連鎖(子PF選択の入替)」が確定。
関連: `dm-production-code-rollback-plan_20260813.md` §-1(復帰点・cron注意)、`dm-monthly-trade-pending-simplify-asis-tobe_20260817.md`(ledgerの将来=廃止方向)。

## AsIs **v0.9** — 2026-08-17 12:45+09:00（事実はcmd_4329確定・機構はcmd_4330偵察中のため仮説）

| 項目 | 事実(一次) | 出典 |
|---|---|---|
| 価格差の実態 | 旧DB(08-16世代) vs 新DB(08-17世代): 13銘柄74,977行×2、key欠損0。**11銘柄30,003行/120,012 OHLCセルに差**、GLD/^VIX/volumeは差0。相対差 **min 5.96e-08 / p50 1.52e-07 / p95 5.66e-07 / max 1.88e-06**(LQD 2010-07-19 close 60.84331130981445→60.843196868896484)。配当/分割調整の桁ではない=**浮動小数点表現の揺れ** | cmd_4329 AC1(影丸・12:13) |
| 価格取込み | `sync_layers.py:62 sync_prices` は毎日 FULL_HISTORY_START から全期間再取得、`etl/loader.py:17-42 save_prices` が同一PKのclose等を上書き。source=stockdata_api。price_history表なし(過去世代は旧DBにしか残らない) | cmd_4328 AC3 / cmd_4329 |
| 外部ソースの履歴版 | StockData API=履歴版なし(open/high/low/close/volume/source/last_updated のみ)。EODHD/Tiingo=raw+adjustedの**現行**系列は取得可、過去as-of版なし | cmd_4329 AC1(実レスポンス) |
| cron vs full | run400(full)後もsignalsは sync-fof値と6,477/6,477一致(old一致0)=両経路の計算は同じ。monthly_returns/fof_component_weightsは世代snapshotが無く差分unknown | cmd_4329 AC2 |
| 変化の中身 | 35 FoF全体・2014-06〜2026-06に広域。差分銘柄関連4,807/非関連1,670。中身は**子PF選択の入替**(GSシン加速R-激攻: シン玄武-激攻→なし249、なし→激攻229、常勝→激攻186、激攻→常勝147 …) | cmd_4329 AC3 |
| 標準PF | 変化0行(alertなし) | cmd_4328/4329 |
| **仮説(cmd_4330で確定待ち)** | 子PFは保有が重なる月にリターンが**完全同値**になる(同じETF・同じ比率)。FoFの子選択の比較値が同値のとき、順序が浮動小数の最下位ビット(=価格ノイズ)で決まっている。標準PF(ETF同士)は同値が起きにくいので反転しない | 将軍推定 |
| 過去の対処=ledger | cmd_3706/3711で`signal_decision_ledger`(確定月凍結・DRIFT BLOCK)を導入=**出力を凍結して症状を止めた**。fullが再生成しない行を作り(08-16原則と衝突)、PITR切替で消え(現在0行)、バンド期再構築で正しい再計算を止めた前科(cmd_3817/3827) | context/dm-signal-ops.md §81系 |

## AsIs **v1.0** — 2026-08-17 12:50+09:00（cmd_4330 read-only偵察・影丸・GATE CLEAR 12:43。機構が現物で確定）

| 項目 | 現物 | 出典 |
|---|---|---|
| FoFの子PF選択 | `ComponentPriceBlock`が子PFの`MonthlyReturn.cumulative_return`をprice_dataへ注入し、pipeline_config `selection=[MomentumAccelerationFilter(top_n=1, method=ratio, numerator_period=10D, denominator_period=63D)]`, `terminal=EqualWeight`。月次データでは10D→1ヶ月・63D→3ヶ月に変換し **score = (close/close[-1]−1) / (close/close[-3]−1)**(1ヶ月リターン÷3ヶ月リターンの比) | cmd_4330 AC1 |
| 同値時の順序決定 | `momentum_acceleration_filter.py:135-142`: scoreだけで降順sortし **cutoff以上を全採用**。二次key(PF ID等)は**存在しない**。exact tieなら同率候補を**全部selected**(top_n=1でも2体保有になる) | cmd_4330 AC1 |
| 反転の実態(GSシン加速R-激攻・候補4子PF) | 2013-09: old 玄武-常勝5.079373775712119 vs 玄武-激攻5.079373775712077(差4.2e-14)→new でも同差で順位維持／**2015-04: old 激攻−0.187830685322682 vs 常勝−0.187830685322683(差1.1e-15)→new は完全同値でexact tie→両方selected**／**2016-12: old 激攻0.971402849738493 vs 常勝0.971402849738493(差1.1e-16、激攻rank1)→new 常勝0.971402849738497 vs 激攻…488(差8.9e-15、常勝rank1)=1位が入替**。他候補(青龍/朱雀)は桁違いに離れている | cmd_4330 AC2(新旧DB readonly再計算) |
| 仮説の修正 | 候補の**cumulative_return自体の差は0.0485〜0.1230**で価格ノイズ級ではない(旧仮説否定)。同値になるのは**ratio score**(1M/3M)であり、同じ保有区間を持つ2子PFが同じ比を出す。差1e-14〜1e-16=**float演算の丸めだけの差**で、価格の最下位ビットが揺れると順位が入替わる | cmd_4330 AC2 |
| 取込み経路 | `client.py:89-140` PriceEntry float → prices float8、`data_fetcher.py:35-102` 全期間再取得、`etl/loader.py:17-42` (symbol,date)全列上書きUPSERT | cmd_4330 AC3 |
| 修正3案の5要件表 | 報告YAML `queue/reports/kagemaru_report_cmd_4330.yaml` AC3 | 同 |

**確定した機構**: 比較値=ratio score(1M/3M)、同値判定=浮動小数の完全一致のみ、tie-break=なし(同率は全採用)。∴ 1e-14級の差で「単独保有⇄2体等分保有⇄逆の単独保有」が揺れる。**標準PFが動かないのはETF同士のscoreがこの精度で並ばないから**。

## AsIs **v1.1** — 2026-08-17 14:50+09:00（cmd_4331 read-only偵察・影丸・GATE CLEAR 13:55。全FoF棚卸し+6段キー乾式適用）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| FoF母集団 | 74 PF(`portfolios.type='fof'`)。selection block有=57(MomentumAcceleration 18／Momentum 9／MultiView 9／SingleView 9／TrendReversal 9／WeightedMultiView 3)、**無=17**(Ave-X・裏Ave-X・New Fund of Funds×4・劇薬DM×2・分身×9)。terminalは全てEqualWeight | cmd_4331 AC1 |
| 選択層の位置 | 共通dispatchは`backend/app/services/pipeline/engine.py:109-142` `PipelineEngine.execute_pipeline()`だが**ranking/cutoff/tie-breakは所有しない**。各block(`momentum_filter.py:141-147`／`momentum_acceleration_filter.py:135-142`／`multi_view_momentum_filter.py:203-210`／`single_view_momentum_filter.py:167-174`／`weighted_multi_view_momentum_filter.py:205-211`／`trend_reversal_filter.py:154-163`)が個別にsort・cutoff(`>=cutoff`全採用)・union/voteを実装。**共通top-N/tie-break helperは存在しない** | cmd_4331 AC1 |
| GS共有 | run_077_kasoku_ratio.py:858-860,1447-1449／run_077_oikaze.py:8-16／run_l1plus_backtest.py:32-66 がproduction blockをparity referenceとして参照するが、**vectorized fast pathは独自にscore/cutoffを計算**(併存) | cmd_4331 AC1 |
| score gap分布(scalar filter 45PF) | rank1/rank2の7,077観測: 相対<1e-9=982、exact同値=888、現行の同率全採用(expansion)=792月。MAF 18PFが754/697/697で大半 | cmd_4331 AC2 |
| 標準PF対照 | 24 PF(全てMomentumFilter)4,178観測: 相対<1e-9=**0**、exact=**0** → **ε=相対1e-9の本番データ根拠** | cmd_4331 AC2 |
| 6段キー乾式適用 | scalar 36PF: 変化837月(現行expansion 792月)。**全74 FoF: 適用月9,141・評価15,910・変化949月**(MAF722／Momentum55／MultiView30／SingleView60／Trend82／Weighted0／no-block 0)。段別解決: ②12M 4,511／③設定来CAGR 668／④MaxDD 0／⑤現保有 7／⑥設定来早い方 7、②skip(12M未満)264 | cmd_4331 AC3 |
| データ充足 | 12M・設定来CAGR・MaxDDは子PF`monthly_returns.cumulative_return`からpoint-in-timeで計算可(未来行不要)。no-block 17 PFは選択スコアの対象外で、実装カバレッジ74/74を主張する前に別途整理が要る | cmd_4331 AC3 |
| 既存テスト | test_momentum_acceleration_filter／test_pipeline_engine／test_grid_search_consistency／test_multi_view_momentum_filter／test_single_view_momentum_filter 等が拡張対象(本cmdではテスト未作成) | cmd_4331 AC3 |

**確定した設計制約**: (1)tie-breakは**共通選択層**として置く必要があり、各filterがscored candidatesを露出→共通層で6段比較→multi-view union/vote・TrendReversal top/bottomの意味は明示的に保つ。(2)GS fast pathは同じ共通層を通すか、parity testで同一結果を強制する。(3)導入時の組み替え規模=949月/74PF(scalar 837月)。根拠正本: `docs/research/cmd_4331_fof_tiebreak_dryrun_20260817.md`(DM-Signal repo `6b3537fd`)、`queue/reports/kagemaru_report_cmd_4331.yaml`。

## ToBe **v0.3** — 2026-08-17 13:05+09:00（殿チャット12:51-12:59で確定した6段キー。実装は殿合図まで）

### 方針: 出力を凍結するのではなく、関数を決定的にする
- 「同一入力→同一出力」(復帰点契約)を、**入力の最下位ビットの揺れ**にも耐える形へ拡張する。手段はledger(出力凍結)ではなく、**比較そのものに同値帯εと根拠あるtie-breakを持たせる**。
- **①は「そのPFのpipeline_configが定める選択スコア」であり、加速(1M/3M比)はGSシン加速R系の一例にすぎない**(殿13:08「たまたま加速で著名なだけで他のどのパターンでも出る」)。同値問題は選択スコアの種類に依らず、同じ保有履歴を持つ子PF同士なら**どの選択フィルタでも**起きる。∴ tie-break(②〜⑥)は特定フィルタの中ではなく、**FoFの子PF選択(top_n採用)を行う共通層**に置き、全フィルタ(Momentum/MomentumAcceleration/その他)で同じ規則が効くようにする。
- ②以降は時間軸が中期→長期→痛み→慣性と並ぶ: 中期モメンタム(12M)→長期実績(設定来CAGR)→MaxDD→現保有維持。tie-breakは後付け規則ではなく「強さの定義の解像度を一段ずつ下げる」形。

### 比較の6段キー(確定案・殿12:59「モメンタムを取り入れたい。12ヶ月トータルリターン→設定来CAGR→以下同じ」)
| 段 | キー | 同値帯 | 根拠 |
|---|---|---|---|
| ① | **そのPFのpipeline_configが定める選択スコア**(config依存。例: GSシン加速R系はMomentumAcceleration ratio=1M/3M、他のFoFはそれぞれの選択フィルタ) | ε(相対1e-9級) | 現行の設計思想をそのまま主キーに。cmd_4330実測(加速R系の例): 同値側の差1e-16〜1e-14、非同値側≥1e-1 |
| ② | **12ヶ月トータルリターン**(=同一期間ならCAGRと同順位)。**両者とも12ヶ月以上の履歴がある時だけ**使う。どちらかが満たなければこのキーはスキップ | ε | 標準的な中期モメンタム窓。12M vs 11Mのような不公平比較をしない |
| ③ | **設定来(inception以来)CAGR**(殿裁定12:51) | ε | 長期実績。全期間なので必ず比較可能。同値=設定来ずっと同じ履歴のみ |
| ④ | **MaxDD が小さい方** | ε | 同じ強さなら痛みが少ない方(=Calmar)。履歴が完全同一でない限り決着 |
| ⑤ | **現保有を維持**(前月に持っていた方) | — | 区別不能なら動かない。取引コスト0・履歴の連続性 |
| ⑥ | 初月(前保有なし)のみ: **設定来が早い方**(実績が長い方) | — | ⑤が効かない唯一の場面の最終規則。ID順は使わない |

- 全キーは **point-in-time**(その月末まで・未来を見ない)。as-ofは主スコアと同じ。
- 実装位置: 特定フィルタ(momentum_acceleration_filter.py)ではなく、**選択結果をtop_nへ絞る共通層**(全選択フィルタが通る箇所)。フィルタごとに二次keyを持たせない(重複実装と不整合の元)。
- **同値=同率全採用ではなく、次のキーで1体に絞る**(top_n=1の契約を守る。現行の「同率を全部selected」は廃止)。
- **価格は丸めない・取込みは触らない**(殿裁定12:51「シンプルに比較側で十分」)。εは比較値側にだけ置く。

### 期待効果と副作用
- 効果: 価格の浮動小数点ノイズで確定履歴が動かなくなる。復帰点の「full 1回で収束」が入力ノイズにも成立。ledgerなしで整合が保てる。
- 副作用: 導入時に一度、確定履歴が決定的に組み替わる(alertが1回出る)。以後は安定。
- 注意: εを大きくしすぎるとCAGRが実質主キーになりFoFの設計思想(直近の強さ)を変える。ε=ノイズを吸う最小に留め、cmd_4330 AC2の候補間差分布で決める。

### 副作用と対策・ロールバック契約 — 2026-08-17 15:15+09:00（殿14:55「副作用は起きないか？ロールバック地点と復旧方法は明確か？」／14:59「計算方法が違う。うまくいかなければrollback計画書のやり方でいく」／15:00「副作用は設計書に記載し、先に対策を明確に」）

**原理**: 手①②は「配線を1本にまとめる」だけで**副作用ゼロを設計目標**にし、手③で**1回だけ意図して**計算方法を切り替える。副作用は「起きない」ではなく「起きる場所と回数を固定し、検知と戻し方を先に決める」。

| 手 | 内容 | 起こり得る副作用 | 対策(事前) | 検知(二値) | 戻し方 |
|---|---|---|---|---|---|
| ① | 共通選択関数を新設し、加速フィルタ1本だけをそこへ差替(中身は現行=同率全採用のまま) | 差替ミスで採用子PFが変わる／multi-view・trendの前に触らないので意味変化なし | 関数の入出力を「候補+score→採用集合」に固定。現行blockのsort・cutoff・`>=`全採用をそのまま移す。関数単体テストで現行blockと同一出力を全FoF×全月で突合(cmd_4331の乾式frameを再利用) | push→deploy→full 1回→**4表md5がrollback計画書§-1 15:10 baselineと完全一致** | `git revert`→push→deploy→full 1回→md5一致。DB PITR不要 |
| ② | 残り5フィルタを1体ずつ差替 | **最大の落とし穴**: 四つ目/新四つ目(4視点→union/vote)・変わり身(top+bottom枝)は「並べて取る」が視点/枝ごとに走る。共通関数を「合成後」に当てると意味が変わる | 各フィルタで「視点/枝ごとに共通関数→既存の合成」を明示(cmd_4331 AC1の行番号が対象)。1体1層・都度full | 同上md5一致(各手) | 同上(その手だけrevert) |
| ③ | 共通関数の中身を6段キー(ε相対1e-9→12M→設定来CAGR→MaxDD→現保有→設定来早い方、同率全採用廃止)へ切替 | **意図した副作用**: FoF 74PFの確定履歴が乾式949月(scalar 837月)組み替わる→SIGNAL CHANGE ALERT 1回、メンバー画面の過去保有・monthly_returns・signals・fof_component_weights・metricsが再生成。標準PF24は変化0(near-tie 0)。no-block 17PFは影響なし。12M/CAGR/MaxDDの計算追加でfull時間が伸びる可能性 | 殿12:51受容済み(1回組み替え・メンバー納得)。切替は**単一commit・単一flag相当**にし部分適用を作らない。事前にcmd_4331の乾式結果(PF別変化月)を「期待差分」として保存 | (a)変化件数=乾式949月と一致(PF別) (b)同一入力でfull 2回目md5一致(収束) (c)標準PF変化0 (d)full所要時間が復帰点の2倍以内 | `git revert`→push→deploy→full 1回→md5がbaselineへ戻る(決定的関数なので戻りも決定的)。SIGNAL CHANGE ALERTがもう1回出るのは受容 |
| ④ | GS高速版(run_077/l1 fast path)を共通関数へ | ③〜④の間はGS結果と本番が不一致(GSは研究用・本番出力ではない) | ④まで一気通貫でなく、③後にGS parityテストを先に赤にしてから④で緑にする | parityテストPASS | revert |
| 共通 | — | 取込み(prices)不変・DBスキーマ不変・frontend不変・API契約不変。cron sync-fofは共通関数を経由するので手③後は新規則で動く | 触らない範囲を明記(スコープ外) | `git diff --stat -- frontend backend/app/etl` = 0 | — |

**ロールバック地点と復旧(正本=rollback計画書§-1・15:10版)**: 地点=各手のpush直前origin/main(手①前=backend `46a1f213`/frontend `55b81b43`/DB run400世代 baseline md5 monthly `c3331388`・signals `e03c0a2c`・weights `dab5148e`・metrics `cda1b38a`)。復旧=コードrevert→push→deploy→full 1回→baseline SQLで一致。新規コード禁止・PITR不要(派生表はfullが全再生成)。実行者は将軍単独、家老・忍者は止める。

### ledgerとの比較(殿12:39「ledgerより今回の方向性の方が筋が良いと思う。どう思う？」→ 同意)
| 観点 | ledger(出力凍結) | 同値帯ε+tie-break(関数の決定化) |
|---|---|---|
| 何を直すか | 症状(確定月が動く)を止める | 原因(比較がノイズ依存)を消す |
| fullとの関係 | fullが再生成しない行を作る(08-16原則と衝突)、バックフィル運用が要る | fullの内側で完結、再生成で同じ答え |
| 復旧・切替耐性 | PITR切替で消える(今回0行)、再構築で正しい再計算を止めた前科 | 何もしなくても同じ |
| 説明可能性 | 「その時そう決めた」を保存 | 「なぜその子か」を規則で説明できる |
| 残る用途 | 監査ログとしてはsignal_change_logで足りる | — |

## 未決（殿裁定待ち・cmd_4330の結果後）
1. ~~比較キーの正体と現行の同値時挙動~~ → **確定(cmd_4330)**: ratio score(1M/3M)、同率は全採用(2体保有化)、二次keyなし。
2. ~~εの値~~ → **裁定(殿12:51)**: 相対1e-9級の同値帯で可(比較値に帯・価格は丸めない)。
3. ~~CAGRの定義~~ → **裁定(殿12:51)**: **inception以来**のCAGR(point-in-time=その月末まで)。
4. ~~最終キー~~ → **裁定(殿12:59)**: 12ヶ月トータルリターン→設定来CAGR→MaxDD小→現保有維持→初月は設定来が早い方(6段キー・ToBe v0.3)。
5. ~~価格取込み側~~ → **裁定(殿12:51)**: シンプルに比較側のみ。取込みは触らない。
6. ~~導入時の1回組み替え~~ → **裁定(殿12:51)**: 受容。メンバーも株価自体が遡及で変動することに納得済み。

## 裁定の因果連鎖 — 2026-08-17 12:45+09:00

| # | 殿の意見(時刻) | 事実 | 制約 | 判断 | 効果 | Obsidian |
|---|---|---|---|---|---|---|
| 1 | 浮動小数点程度の価格差は実際にあり、その影響で保有シグナルが変わる(12:35) | cmd_4329: 相対差1e-7級で6,477件反転 | 外部APIに履歴版なし・取込みは同一PK上書き | 事実として受容し、対処は関数側 | 現実に合った前提 | `[[cmd_4329]] -> [[価格差はfloatノイズ級]]` |
| 2 | 丸め=何桁？丸めるとtieが発生する(12:35) | 丸め境界の両側に必ず値が落ちる | 「変わらない桁」は原理的に存在しない | 価格を丸めず、比較値に同値帯εを置く | ノイズを吸いつつ情報を削らない | `[[丸めはtieを作る]] -> [[同値帯ε]]` |
| 3 | tie-breakには根拠が要る。PF順は理屈でない。強いもの=過去CAGRが高い方(12:35) | 子PFは保有重複月に完全同値 | 並び順/IDは並べ替えで整合が壊れる | 2段目=point-in-time共通期間CAGR、3段目=現保有維持 | 説明可能・決定的 | `[[殿意見_強いもの_過去CAGR_20260817]] -> [[3段キー]]` |
| 5 | 2はε案でよい／3のCAGRは設定来／5は比較側で十分／6は受容。メンバーも株価の遡及変動に納得(12:51) | cmd_4330で比較キー・同値差が確定 | 二重対策は複雑さを増やす | ε=相対1e-9級、CAGR=設定来、取込みは触らない、導入時1回の組み替えは受容 | 実装が比較関数1か所で閉じる | `[[殿裁定_未決2356_20260817]]` |
| 6 | せっかくなのでモメンタムを取り入れたい。12ヶ月トータルリターン(CAGRでも同じ)→設定来CAGR→以下同じ(12:59) | 主スコアが1M/3Mの加速 | tie-breakも同じ思想で並べるべき。12M未満の子は比較不能 | ②12M(両者12M以上ある時のみ)を挿入、時間軸短→長で6段 | 後付け規則ではなく思想の解像度を下げる形。IDに一度も頼らない | `[[殿裁定_12Mモメンタム挿入_20260817]] -> [[6段キー]]` |
| 7 | 現行主スコアはたまたま加速で著名なだけで、他のどのパターンでも出る。加速がデフォルトに見える表現は良くない(13:08) | 同値問題は選択スコアの種類に依らず起きる(同じ保有履歴の子PF同士) | 特定フィルタに二次keyを埋めると他フィルタで再発・不整合 | ①=config依存の選択スコアと一般化、tie-breakは共通層へ | 全FoF・全フィルタで同じ決定性 | `[[殿指摘_加速はデフォルトでない_20260817]] -> [[tie-breakは共通層]]` |
| 4 | 以前はledgerを設定したが今回の方向性の方が筋が良い(12:39) | ledgerは出力凍結・再生成外・PITRで消失・前科あり | 08-16原則「fullが再生成しない行を作らない」 | ledgerではなく関数の決定化 | 復帰点契約と整合、ledger廃止方向と一致 | `[[殿意見_ledgerより関数決定化_20260817]] -> [[ledger廃止方向]]` |

## チャット記録（殿×将軍・要旨）— 2026-08-17 12:45+09:00
- 10:47 殿ntfy SIGNAL CHANGE ALERT 6,477件 → 将軍: sync-fof cron停止+full run400(誤診) → 11:03 訂正: 真因はsync-pricesの全履歴upsert、cron再開
- 11:33 殿「まず本当に価格が変わったか、cronとfullの差分、どのPFがどう変わり連鎖したか、特定PF特定タイミングか」→ cmd_4329
- 11:37 殿「price historyはStockData/EODHD等でも調べられるか調査」→ cmd_4329 AC1へ追加
- 12:13 cmd_4329結果: ノイズ級の価格差で広域反転。将軍: tie-breakのノイズ依存を示唆 → cmd_4330(機構偵察)起票
- 12:35 殿「浮動小数点程度の価格差は実際にあり保有シグナルが変わる。丸め=何桁？丸めるとtieが発生。tie-breakには根拠が要る。PF順は理屈でない。強いもの=過去CAGRが高い方はどうか。決定ではなくチャット」
- 12:37 将軍: 丸めは価格でなく比較値に同値帯ε／FoFだけ反転する理由=子PFの完全同値／CAGR tie-breakに賛成+条件3つ(point-in-time・共通期間・最終キー=現保有維持)／εは最小に
- 12:39 殿「artifactにまとめよ。今は情報待ち。ledgerより今回の方向性の方が筋が良い。どう思う？」→ 本書+同意(上表)+artifact 58f94a75
- 12:51 殿「2はその案でいい。3のCAGRはinception以来。4の最終キーに他のアイデアは？5はシンプルに比較側で十分。6は受容。メンバーも株価の遡及変動には納得」→ 未決2/3/5/6裁定、4は議論継続
- 12:55 将軍: 最終キー候補6案(現保有維持/長い実績/低DD/単純さ/等分/ID)を比較、推薦=MaxDD小→現保有維持→初月は設定来早い方
- 12:59 殿「せっかくなのでモメンタムを取り入れたい。過去12ヶ月のトータルリターン(CAGRでも同じ)→設定来CAGR→以下同じ」→ 将軍賛成+詰め3点(12M未満は両者12M以上の時のみ／各キーにε／point-in-time)→6段キー確定案
- 13:01 殿「まず設計書とartifactに落とそう」→ ToBe v0.3
- 13:08 殿「現行主スコアはたまたま加速で著名なだけで他のどのパターンでも出る。加速がデフォルトに見える表現は良くない」→ ①を『pipeline_configが定める選択スコア(config依存)』へ一般化、tie-breakは全フィルタ共通層に置くと明記
- 12:43 cmd_4330 GATE CLEAR → AsIs v1.0(ratio score/同率全採用/二次keyなし、2015-04 exact tie両選択・2016-12 1位入替の実測)、ToBe v0.2(ε=相対1e-9級提案)
- 13:04-13:23 cmd_4331起票→DOC_LANE_ROUTING偽陽性BLOCK→殿13:19「偽陽性は即時根治」→根治(caac794c)→再委任。13:55 GATE CLEAR → AsIs v1.1(全74 FoF棚卸し・共通helper不在・標準PF near-tie 0・6段乾式949月変化)。14:45 殿「まずはartifact,設計書、gistをアップデート」→ 本版

## 注釈 — 2026-08-17 12:45+09:00
- AsIs v0.9はcmd_4330で機構が確定したらv1.0へ。ToBe v0.1はε・比較キー・CAGR定義が決まったらv0.2へ。
- AsIs v1.1(14:50)=cmd_4331の全FoF棚卸し・乾式適用。ToBe v0.3は不変(共通選択層の要請がAsIsで裏付けられた)。実装は殿合図で1体1層。
