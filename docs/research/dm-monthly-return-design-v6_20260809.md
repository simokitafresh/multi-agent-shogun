<!-- gist-master: d23c8d202b0e99b0007ef77a2d14d39a dm-monthly-return-design-v6_20260809.md -->
# DM-Signal 月次リターン設計書 v6.0 — 基本原理再構築版(6層分離)

> **位置づけ**: 殿最優先下知2026-08-09 03:43(原文=`docs/research/dm-monthly-return-first-principles-original_20260809.md`・改変禁止)に基づく再構築版設計書。**旧v5.22(`docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md`)は保持され一切変更しない** — 事故対応の全証跡・WBS・棄却表・改訂履歴約90版の正本であり続ける。本書は「月次リターンの計算仕様」を通常運用と修復・監査から分離して再定義するもの。前提知識ゼロのLLMが本書だけで§1-§3の通常モデルを理解できることを設計要件とする。
> **状態**: 設計案(殿裁可待ち)。**実装・実装起票・deployは殿の別途下知まで禁止**。
> **形式規約**: スナップショット型(v5.22 v5.00規約を継承)。各節は現在の真実のみを書く。経緯は§6と旧設計書が持つ。
> **検討資料**: 批判的レビューR1-R11+設計チームQ1-Q10回答=`docs/research/dm-monthly-return-first-principles-design-v0_20260809.md`(v0.4)。現物調査=`docs/research/cmd_4246_monthly_return_principles_recon_20260809.md`。

> **★冒頭明記(momentum分離・下知■10)**: モメンタム計算と月次リターンは**別系統**である。Standard PFのモメンタム判定は月末等の確定価格の窓を用い(現行実装=殿裁定と一致・変更不要)、本書の月次リターン境界と独立。月次リターン修正のためにmomentum windowを変更してはならない。FoFのsignal変化があり得るのは「momentum algorithmの変更」ではなく「momentum inputである子PF月次系列が是正されることによる二次効果」である。

## §0 現在地(2026-08-09 09:30 スナップショット)

- 本番: run232(full)完走で全履歴復旧済み(102PF・16,976行・2003-09〜2026-08、事前baseline完全一致=家老readonly実測04:16)。stale ledgerバグ修正deploy済み(run224)。PUBLICABLE=YES
- §3のpending→confirmed lifecycleは**未実装**(本書が設計する対象)
- 旧v5.22の是正残工程(D/E系=本番浄化・三面一致、全体75%)は**本書により無効化されない** — §4の台帳として続行
- 暫定運用: fullrecalculateは**mode='full'のみ**(殿裁定2026-08-09 03:03: 実装ゼロの知識層チェックリストが正・機構化しない)。理由=§4.4
- cmd_4245(履歴上書きガード初回実装)=FAIL-close(§4.4に顛末)

---

## §1 不変の基本原理(9原則・5概念)

1. **Return(M) = EndValue(M) / StartValue(M) − 1**。それ以上の数学はない。
2. **StartValue(M)** = 月次境界日boundary(M)におけるPF評価額。**EndValue(M)** = boundary(M+1)におけるPF評価額。評価は当該期間に効力を持つ保有構成(ticker×weight、FoFは子PF再帰展開)で行う。
3. **boundary(M)**: 全ての暦月に必ず1つ存在する。保有切替がある月=**切替が実際に効力を持った日**(市場の月内初営業日と同一視しない。実例: 2022-04は4/1が営業日だが効力発生=4/4、ゆえに4/1-4/4は3月に属する)。切替がない月=**当月の初回取引日**(RULE06月次ウェイトリセットの効力日。リセットは意図的な確定ルール=殿裁定2026-08-03 02:14、driftへの変更は行わない)。※これは境界の**定義**である。歴史データからの**導出方法**は§4.1。
4. **系列分離**: Close系列=境界日のclose同士、Open系列=境界日のopen同士。混在禁止(RULE09)。
5. **空白ゼロ**: 連続月は境界点を1点共有する(前月の終点価格=当月の起点価格)。端点はPF実運用開始日とas_ofの2つのみ。
6. **momentum分離**: 冒頭明記の通り。終点=月の最終営業日終値、始点=ルックバック依存、全て営業日ベース。
7. **一次データ不可侵**: 市場価格(prices)は事実のみを保持。存在しない営業日・価格の行を作らない(下知■6)。仮計算値と仮の市場価格は別物である。
8. **正常な未到着(pending)と異常な欠損(ERROR)は別物**(下知■8)。前者は表示を止めず(§3)、後者はfail-visible(fallback禁止: holding_signal欠損・weights空を0や代用値で握りつぶさない)。
9. **シグナル遡及原則**(殿裁定2026-08-03 02:34): price遡及由来のsignal差=維持(guard)。計算ルール是正由来の差=正しいシグナルを受け入れ本番も修正する。

**概念数は5つ**: 境界日・保有構成・価格系列・単一エンジン・入力確定度。これ以外の概念(ledger resolver・anchor・oracle・checkpoint等)は§4/§5の隔離レイヤーに属し、通常計算の理解に不要。

### §1.1 前提知識(自己完結)

- **DM-Signal**: 投資PFシグナル配信アプリ。repo=`/mnt/c/Python_app/DM-signal`(Python/FastAPI+PostgreSQL、Render稼働)
- **PFの2型**: `portfolios.type='standard'`(ticker×weight直接構成) / `'fof'`(他PF組合せ。holding_signalは子PF UUID。入れ子あり)。層: L0=standard、L1-L3=FoF入れ子。下位層が誤れば上位層は必ず誤る
- **主要テーブル**: `signals`(holding_signal=確定保有。生signalでの代用禁止) / `monthly_returns`(PF×year_month。Close/Open両列) / `trade_performance`(境界イベント記録) / `prices`(配当調整済み) / `signal_decision_ledger`(保有決定のappend-only正本)
- **営業日=pricesに価格が存在する日**(基準symbol=SPY)。独自カレンダー禁止。**配当調整=stock data API側の責務**。独自調整禁止
- **取引費用=0**(システムに費用概念なし)

---

## §2 通常リアル運用(単一エンジン)

### §2.1 エンジンは一つ

```
calculate_return(start_input, end_input, holdings) = end_value / start_value − 1
  start_input = (日付, その日の価格系列値)   # 通常はboundary(M)。PF初月のみ実運用開始日
  end_input   = (日付, その日の価格系列値)   # 確定時はboundary(M+1)。未確定時はprovisional(§3)
  holdings    = 当該期間に効力を持つ確定保有(signals→再帰展開)
```

- **pending用の別計算式を作らない**(下知■4)。provisional calculator/MTD calculator/historical calculatorという分岐は禁止。違いは入力の確定度タグのみ。
- **旧・月の四分類との対応(概念の簡約)**: Normal=「全入力confirmed」/ MTD・月替わり直後=「end_input=provisional」/ Partial=「start_input=実運用開始日」(初月の入力差であり別エンジンではない)/ 未開始=行を生成しない(エンジン外の対象選別)。月クラスという概念は**行のstatusフィールドへ置換**する。
- 現物根拠(cmd_4246): 現行MTDは既に同一`calculate_monthly_return`で動的再計算しており、単一エンジン原則の実装距離は近い。

### §2.2 通常経路の分岐の全量(機械判定基準)

許される分岐は **系列(Close/Open) × end_inputの確定度(confirmed/provisional)** の直積のみ。これで説明できない分岐が通常経路に現れたら、それは§4/§5からの漏出であり削除対象(下知■12「なぜ必要か説明できない分岐を消す」の判定基準)。

### §2.3 記録レイヤー(エンジン外)

- `monthly_returns`: エンジン出力の保存先。status/as_of/provenanceの持ち方は§3.5(未決)。
- `trade_performance`: 境界イベントの記録。正規形=月次境界日/trigger eventごとに1行・隣接行はend=次行start・gap/overlap 0・型はrebalance_trigger由来に統一(Signal型廃止)・暫定値/非取引日付の行禁止(殿裁定2026-08-03 02:25)。**月次リターン計算はtrade_performanceを読まない**(signal変更の正本はsignals/ledger)。
- `signals`/`ledger`: 保有の正本。通常運用では確定holdingsとして消費するのみ。ledgerからの境界導出の複雑性は§4.1。

---

## §3 pending→confirmed lifecycle(第一級概念・本書の新設計)

### §3.1 三状態(下知■8)

| status | 意味 | 例 | 扱い |
|---|---|---|---|
| **PENDING_EXPECTED** | 正式計算に必要な入力が**まだ世界に存在しない**(未来データ未到着) | 月替わり直後の前月End価格未到着、進行月のas_of評価 | 表示を止めない。provisionalで仮計算し追跡フィールドを付す |
| **CONFIRMED** | 全入力確定 | 境界価格・保有とも確定した過去月 | 確定値として保存 |
| **ERROR** | **存在すべきデータの欠損**・構成異常 | holding_signal欠損、weights空、必須過去価格欠落、config破損 | fail-visible。pendingで握りつぶさない |

- **calendar rolloverとmarket data availabilityは別物**(下知■5): 暦月が変わっても新月の境界価格が未到着の状態は**正常**であり、異常扱いしない。
- pendingをERROR扱いしない(実証: hotfix 9a27eb4fの未初期化行savepoint全rollback、L5 failed群蓄積=この区別の不在が原因)。ERRORをpendingで隠さない(fallback禁止は不変)。

### §3.2 実例タイムライン(7/31金market close → 8/1土 → 8/3月が8月初回取引)

- **8/1・8/2**: 7月のend_input(8月境界の価格)は存在しない → 7月=`PENDING_EXPECTED`、値=provisional end(as_ofで利用可能な最新確定価格=7/31 close)による仮計算。8月=境界未形成につき期間未開始。表示は「開始待ちpending」であり、NULL・表示消失・ERRORのいずれでもない。
- **8/3市場後**: 8月境界形成+境界価格到着 → 7月のend_inputをprovisional→正式値へ**置換し、同一エンジンで再計算** → 7月=CONFIRMED。8月=進行月としてPENDING_EXPECTED(end=as_of)開始。
- 差し替わるのは**入力だけ**。計算方式は切り替わらない(下知■3)。再計算は既存の定期再計算サイクルに乗せる(新規の自動発火機構は作らない=殿裁定2026-08-09 03:01/03:04)。

### §3.3 provisional source(下知■7 — 設計案として提示・裁定待ち)

| 候補 | 内容 | 評価 |
|---|---|---|
| A | latest available market valuation | Cと実質同義だが「valuation」の定義が曖昧になりがち |
| B | 前市場日の確定Close | 明確・一次データのみ。「前市場日」解決が営業日判定に依存 |
| **C(推奨)** | **as_of時点で利用可能な最新確定価格(直近close)** | Bと通常一致し休日連続でも自明。pricesの一次データのみ(捏造ゼロ)。現行`PriceCache`のbackward解決(対象日以前の最近傍営業日のClose/Open同時取得)が取得機構として実装済み(cmd_4246 §5) |
| D | 現行UI意味論と整合する他の値 | 現行の近縁実装=`/api/mtd`のOpen系列限定`is_preliminary=true`行のみ(cmd_4246 §3.2) |

必須追跡フィールド: `provisional_source` / `provisional_as_of` / `missing_requirement`(何が到着すればconfirmedになるか)。「とりあえずfallback」の暗黙実装は禁止。

### §3.4 UI/API/DBの現状と非対称(cmd_4246現物確定)

- 価格未到着の新月に対し、**Monthly Trade APIは`is_pending=true`を動的生成**(monthly_returnsへ保存せず、return=null+Pending badge表示)する一方、**Monthly Returns APIは当月row不在でpendingを生成せず、全row不在なら404**を返す — 三者(UI/API/DB)でlifecycleが不一致。
- `monthly_returns` schemaに`status`/`as_of`/`provenance`列はない。型レベルの`is_mtd`/`is_pending`はDB行に持たない。
- ToBe: **Monthly ReturnsにもMonthly Tradeと同じpending/confirmed明示を返し、三者の意味論を統一**する。「UIに常に値が必要だからconfirmedを偽装する」方式は禁止(下知■11)。

### §3.5 未決事項(殿裁定待ち)

1. **provisional source採用**: 推奨=案C(§3.3)。
2. **pending値のDB永続化方式**: (a)runtime計算のみ(DBはconfirmedのみ。pendingはAPI層で都度計算) / (b)同一行にstatus/as_of/version列 / (c)pending専用キャッシュ層。現行は(a)に最も近い(Monthly Tradeの動的pending)。**将軍暫定推奨=案(a)+API統一**(schema変更最小・confirmed偽装が構造的に不可能)。precomputed_raw cacheとの整合を含め裁可事項。
3. **境界未形成月の表示形**(値なしpending vs 0%等)。

---

## §4 historical repair(隔離レイヤー — 通常計算に持ち込まない)

今回事故で必要になった複雑性は全てここに住む。**正本・全証跡=旧v5.22**(本節は要点と現在の真実のみ)。

### §4.1 historical boundary resolver

歴史データから境界日を**導出**する機構(§1-3の定義とは別物): verification付き導出式=`boundary(month) = verified(ledger.effective_start_date == expanded実切替日) ? ledger値 : expanded実切替日`。無条件ledger優先・単純COALESCE禁止・root holding日付不採用(2022-04実証)。理由=歴史15,212行のledger backfill値が全件decision日の複写で信頼できないため。**将来月は切替時に効力日を直接記録すれば本resolverは不要になる**(現行書込みの実態確認は今後の設計課題。cmd_4246: `historical_backfill`のeventを読み側resolverがevent_type区別なく通常候補に入れる混入も確認済み→source/provenance分離が必要)。

### §4.2 stale ledger失効(修正済み)

effective_end=NULLの古いledger無期限適用が月初切替を上書きするバグ(異常25PF)は修正deploy済み(run224完走・境界テスト121件PASS。v5.22 §2.1#8)。

### §4.3 修復・検証装置(v5.22正本)

24行anchor検証・78PF checkpoint・B4a-e段階実験・実行順序7段・backupファースト+PF単位transactional restore・レーンS dual replay三分類(guard1,249/apply72)・是正工程WBS(D/E系残、全体75%)。**これらは本書により無効化されず、v5.22の台帳のまま続行する。**

### §4.4 confirmed履歴の保全ガード(cmd_4245顛末と配置条件)

- 初回実装(c469ba6f)はrun231でFAIL確定: mode=portfolio全PF実行時、**Phase0一括cleanupがガード到達前に全PF履歴をDELETE**するため、ガードはexisting_min/max=NULLを見て狭い結果を素通し(16,976行→3,248行/102PF→98PFの退行が実発生)。revert 4d81c32+run232 fullで本番復旧済み。cmd_4245はFAIL-close。
- **配置条件(アーキテクチャ契約)**: 保全ガードは履歴を消し得る全操作(Phase0一括cleanup含む)の**上流**で効かなければ無意味。保護と破壊の順序は実装詳細ではなく契約である。
- **真因の設計層表現**: 「全消し→全再構築(full rebuild semantics)」が通常のportfolio経路に常駐していること。ToBe=通常経路は該当期間の置換のみ、全消し再構築は本レイヤーの明示操作に限定。後継ガードはこの分離とセットで設計する(実装は殿の別途下知)。それまでの暫定防御=mode='full'のみ運用(§0)。

---

## §5 verification / migration(隔離レイヤー)

- **確定仕様オラクル**: primitive入力からの独立再帰計算で本番値を審判する(入力SSOT・証拠行番号=v5.22 §0.6オラクル節)。**数値意味論**: 本番と同一のfloat64展開・本番実装が行う正規化のみ適用・独自Decimal化/中間丸め禁止・比較は保存前round規約(round(x,10)=round-half-even)量子化後のexact一致のみ(殿裁定=v5.22 §0.6-8)。
- **検証者規約4問**(不一致を誤りと断定する前に): ①実運用開始日以降か(未開始とPartialを混同しない) ②確定済み月か(進行中は歴史突合対象外) ③境界を§1-3の月次境界日で解決したか(誤り方2種: 暦日1日固定/初営業日固定) ④リターン境界とモメンタム窓を混同していないか。
- **遡及原則の実装**: recalc invocationへ明示mode(price_retro=guard維持 / rule_correction=適用+ledger再基線 / 未知=fail-closed)。差分から原因を推測しない(v5.22 B2e・敵対fixture3種)。
- **常設監視は最小の2つ**: 正規形違反INSERT拒否gate(B5型)+月次1サイクル自然検証(E2型)。
- **migration(pending導入時)**: schema/API変更・既存行のstatus付与・precomputed_raw cache整合は、§3.5裁定後に本節の移行計画として設計する(バックアップファースト+可逆で実行。実装は別途下知)。

---

## §6 incident history(ポインタ)

- **事故の全経緯・棄却済み仮説(5件・再調査禁止)・WBS44工程・改訂履歴約90版** = 旧v5.22本文(保持・無変更)+`dm-monthly-trade-bug-genko-chain-archive_20260803.md`+gist 8cbc86a5
- 事故サマリ: 殿指摘2026-08-02「複数PFで極端にCAGR低下」→ 真因=月次境界仕様未明文+月初固定実装(執行ずれ月の空白脱落)→ §0.6裁定確定 → 是正レーン進行中に0行消失・stale ledger・run231退行の各事故 → いずれも復旧済み(§0)
- 本書の成立: 殿下知2026-08-09 03:43(基本原理からの再整理)→ 設計チームQ1-Q10回答3/3収束 → cmd_4246現物調査 → 本書v6.0
- 関連: run231退行の因果=§4.4 / compare系N/A事案=cmd_4244偵察正本 / 月次境界の運用診断則=`context/dm-signal-ops.md` §89-§91

### §0.6全条項の収容対応表(裁定の逸失ゼロ証明)

| v5.22 §0.6条項 | v6.0の所在 |
|---|---|
| 1 境界日定義+導出優先順位 | 定義=§1-3 / 導出式=§4.1 |
| 2 空白ゼロ構造保証 | §1-5 |
| 3 系列分離 | §1-4 |
| 4 モメンタム窓 | 冒頭+§1-6 |
| 5 月の四分類 | §2.1(statusタグへ簡約・対応明記) |
| 6 取引費用0 | §1.1 |
| 7 fallback禁止・fail-visible | §1-8+§3.1 |
| 8 数値意味論 | §5 |
| trade_performance正規形 | §2.3 |
| シグナル遡及原則 | §1-9+§5 |
| 検証者規約4問 | §5 |

### 因果リンク

`[[殿下知_月次リターン基本原理再整理_20260809]] -> [[dm-monthly-trade-bug-asis-tobe-5w1h_20260802]](保持) -> [[dm-monthly-return-design-v6_20260809]] -> [[pending_confirmed_lifecycle]] + [[migration_incident_recovery_layer]]分離`

## 改訂履歴

- v6.0 (2026-08-09 09:3x): 新規作成(将軍直轄)。殿下知■12の6層構造(基本原理/通常運用/pending lifecycle/historical repair/verification・migration/incident history)へ再構築。旧v5.22は保持・無変更。cmd_4246現物調査+Q1-Q10回答3/3+run231/232顛末を反映。未決3件(§3.5)は殿裁定待ち
