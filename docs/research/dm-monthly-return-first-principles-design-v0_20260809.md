# DM-Signal 月次リターン再設計 — 基本原理からの再整理 v0.4 (設計案)

> **位置づけ**: 殿最優先下知2026-08-09 03:43(原文=`docs/research/dm-monthly-return-first-principles-original_20260809.md`・改変禁止)への回答。v5.22(`docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md`)の批判的レビュー+6層再分類案。**実装・実装起票・deployは殿の別途下知まで禁止**。本書は設計案であり、殿裁可後にv5.22の再分類を実行して正本化する。
> **証跡保持**: v5.22の証跡・裁定・WBSは一切削除しない。本書は「行き先の地図」であり、移設実行は裁可後。
> **現物調査**: cmd_4246完了(成果物=`docs/research/cmd_4246_monthly_return_principles_recon_20260809.md`、8系統接続マップ+schema境界+月替わり直後の三経路挙動)。v0.4で本書へ統合済み。※偵察は04:00時点のworking tree(revert 4d81c32前)に基づくため、replacement guard記述は失敗版c469ba6fを含む — 本番はrevert済みである点に注意。
> **冒頭明記(下知■10)**: モメンタム計算と月次リターンは別系統である。Standard PFのモメンタム判定は月末等の確定価格の窓を使い、月次リターン境界とは独立。月次リターン修正でmomentum windowを変更してはならない。FoFのsignal変化があり得るのは「momentum algorithmの変更」ではなく「momentum inputである子PF月次系列が修正されることによる二次効果」である(v5.22 §2-6と整合)。

---

## Part 0: v5.22批判レビュー — 不要な複雑性・概念混同・migration漏出の列挙

v5.22は事故対応文書として正しく機能したが、「月次リターン計算仕様」と「障害修復・移行・監査」が一体化している。列挙:

| # | 種別 | v5.22の箇所 | 内容 | 行き先レイヤー |
|---|---|---|---|---|
| R1 | **漏出** | §0.6-1 verification付き導出式(検証済ledger優先/expanded fallback/単純COALESCE禁止) | 境界日の**定義**(効力日)と、**歴史データから境界日を復元する方法**(ledger backfill値が信頼できないための照合式)が同じ条項に同居。後者はhistorical resolverの複雑性であり、通常計算の境界定義ではない | 定義→Part 1、導出式→Part 4 [D] |
| R2 | **概念過多** | §0.6-5 月の四分類(Normal/MTD/Partial/未開始) | 4つの月クラス+各専用オラクル(A0-2p/A4)は計算エンジンの分岐を生む。実体は「入力の確定度」の違いだけ: Normal=全入力確定、MTD=end未確定、Partial=start=実運用開始日(入力差)、未開始=行を作らない(月分類ですらない) | Part 2で2状態+1フラグへ簡約 |
| R3 | **混同** | hotfix 9a27eb4f(Missing holding_signal before first usable lookback→savepoint全rollback)、L5 failed群(rolling_returns builder None) | 「正常な未到着・未初期化」をERROR/rollbackとして扱った実証事例。pending(PENDING_EXPECTED)概念の不在が全rollback・failed蓄積・fail-visible過剰発火を生んだ | Part 3の三状態意味論 |
| R4 | **漏出** | 24anchor・checkpoint・B4a-e段階実験・7段実行順序・backup/restore | 全て今回事故の修復・検証装置。通常計算仕様に不要 | Part 4/5 |
| R5 | **漏出** | レーンS dual replay三分類(guard1,249/apply72)・シグナル遡及原則の実装(mode化B2e) | 是正時の一回性影響評価+遡及ポリシー。通常runの月次計算には現れない | Part 5(遡及原則自体は不変原理としてPart 1に1行残す) |
| R6 | **概念過多** | trade_performance正規形・producer一本化・Signal型廃止 | 記録レイヤーの仕様。月次リターン計算はtrade_performanceを読まない(読んではならない)。同一文書に同居して「月次リターン仕様」を太らせた | Part 2の記録節(engine外)へ分離 |
| R7 | **漏出** | §0.6-8 数値意味論・オラクル入力SSOT・検証者規約4問 | 監査・検証層の規約。engine仕様ではない | Part 5 |
| R8 | **複雑性** | §2.5 WBS44工程・§2.4 Wave表・§0.1進捗・§7改訂履歴約90版 | 事故対応の工程管理。設計原理と無関係に本文の8割を占める | Part 6(履歴)+残工程はPart 4/5の台帳として存続 |
| R9 | **不在** | — | 「暦月が変わったが新月の境界価格が未到着」の期間の表示意味論が未定義。四分類はこの期間を扱えない(v4.35で「境界未形成→未開始再分類候補」の分類難航として顕在化) | Part 3が新設 |
| R10 | **不在** | — | provisional source(未確定時に何で仮評価するか)の明文化なし。現行実装が暗黙に何かをしている可能性【要現物確認=cmd_4246 AC2】 | Part 3 |
| R11 | **漏出(コード実証)** | recalculate_fast.py Phase0一括cleanup(precompute_tables全DELETE→再計算。家老git show一次確認2026-08-09 04:09) | **全消し→全再構築(full rebuild semantics)が通常のmode=portfolio経路に常駐**している実証。cmd_4245ガード(狭い結果の上書き拒否)は呼ばれるが、Phase0で全PF履歴が既に空になった後に到達するためexisting_min/max=NULLで素通し=**保護層が破壊層より下流**。run231失敗の因果確定(復旧run232) | 全消し再構築→Part 4(historical repair専用の明示操作)。通常経路は該当期間の置換のみ。保全ガードは破壊操作の上流に置く |

**結論**: §0.6の裁定内容(境界=効力日、空白ゼロ、系列分離、RULE06、momentum分離、fallback禁止)は**全て正しく、保持する**。問題は(a)歴史復元の複雑性が定義に漏出(R1)、(b)月クラス4分類がエンジン分岐を誘発(R2)、(c)pending概念の不在(R3/R9/R10)、(d)full rebuild semanticsの通常経路常駐(R11)の4点。R11はrun231で「設計上の懸念」から「本番障害の因果」へ昇格した — 通常経路とhistorical repairの分離は美学ではなく履歴保全の必要条件である。

**cmd_4246現物確定(v0.4統合)**: R1=現物確定 — `historical_backfill`のledger eventを読み側`resolve_ledger_decisions_bulk()`がevent_type区別なく通常候補集合へ入れる(偵察§3.1)。R9=現物確定 — 価格未到着の新月に対し**Monthly Trade APIは`is_pending=true`を動的生成する一方、Monthly Returns APIは当月row不在でpendingを生成せず(全row不在なら404)** — UI/API/DBの三者でlifecycleが不一致(偵察§3.2)。R10=現物確定 — `/api/mtd`のOpen系列限定`is_preliminary=true`行が現行唯一のprovisional実装で、Close確定行への契約はない(偵察§3.2)。**朗報も2つ**: (1)MTDは既に同一`calculate_monthly_return`で動的再計算しており、単一エンジン原則の実装距離は近い (2)`PriceCache`のbackward解決(対象日以前の最近傍営業日のClose/Open同時取得)が存在し、provisional source案Cの取得機構は実装済み(偵察§5-2)。

---

## Part 1: 不変の基本原理(これだけで月次リターンを説明できる形)

1. **Return(M) = EndValue(M) / StartValue(M) − 1**。それ以上の数学はない。
2. **StartValue(M)** = 月次境界日boundary(M)におけるPF評価額。**EndValue(M)** = boundary(M+1)におけるPF評価額。評価は当該期間に効力を持つ保有構成(ticker×weight、FoFは子PF再帰展開)で行う。
3. **boundary(M)**: 全ての暦月に必ず1つ存在する。保有切替がある月=**切替が実際に効力を持った日**。切替がない月=**当月の初回取引日**(RULE06月次リセットの効力日)。(v5.22 §0.6-1の定義部を継承。歴史データからの導出方法はPart 4)
4. **系列分離**: Close系列=境界日のclose同士、Open系列=境界日のopen同士。混在禁止(RULE09)。
5. **空白ゼロ**: 連続月は境界点を1点共有する(前月の終点=当月の起点)。端点はPF実運用開始日とas_ofの2つのみ。
6. **momentum分離**: モメンタム判定(月末確定価格の窓)は別系統。本設計はmomentumを変更しない。
7. **一次データ不可侵**: 市場価格は事実のみを保持。存在しない日付・価格の行を作らない(下知■6)。
8. **正常な未到着(pending)と異常な欠損(ERROR)は別物**(下知■8)。前者は表示を止めず、後者はfail-visible。
9. **遡及原則**(殿裁定2026-08-03 02:34、不変): price遡及由来のsignal差=維持(guard)、計算ルール是正由来の差=受容し本番修正。

概念数: **境界日・保有構成・価格系列・エンジン・入力確定度** の5つ。

---

## Part 2: 通常リアル運用(単一エンジン)

### 2.1 エンジンは一つ

```
calculate_return(start_input, end_input, holdings) = end_value/start_value − 1
  start_input = (日付, その日の価格系列値)   ← 通常はboundary(M)、初月のみ実運用開始日
  end_input   = (日付, その日の価格系列値)   ← 確定時はboundary(M+1)、未確定時はprovisional
  holdings    = 当該期間に効力を持つ確定保有(signals.holding_signal→再帰展開)
```

- **pending用の別計算式は存在しない**(下知■4)。provisional calculator/MTD calculator/historical calculatorという分岐を作らない。違いは入力の確定度タグのみ。
- 旧四分類との対応: Normal=「全入力confirmed」/ MTD・月替わり直後=「end_input=provisional」/ Partial=「start_input=実運用開始日」(初月の入力差であり別エンジンではない)/ 未開始=行を生成しない(エンジン外の対象選別)。**月クラスという概念は廃止し、行のstatusフィールドに置き換える**。

### 2.2 通常経路の分岐の全量

許される分岐は次の直積のみ: **系列(Close/Open) × end_inputの確定度(confirmed/provisional)**。これで説明できない分岐が通常経路に現れたら、それはPart 4/5からの漏出であり削除対象(下知■12「説明できない分岐を消す」の機械的判定基準)。

### 2.3 記録レイヤー(エンジン外)

- `monthly_returns`: エンジン出力の保存先。status/as_of/provenanceを持つ(案はPart 9)。
- `trade_performance`: 境界イベントの記録(正規形=v5.22 §0.6準拠)。**月次リターン計算はこれを読まない**。
- `signals`/`ledger`: 保有の正本。**将来月の境界イベントは切替時に直接記録される**ため、通常運用ではPart 4のhistorical resolverを必要としない【現行ledger書込みが効力日を正しく記録しているかは要現物確認=cmd_4246】。

---

## Part 3: pending→confirmed lifecycle(第一級概念)

### 3.1 三状態(下知■8)

| status | 意味 | 例 | 扱い |
|---|---|---|---|
| **PENDING_EXPECTED** | 正式計算に必要な入力の一部が**まだ世界に存在しない**(未来データ未到着) | 8/1時点の7月End価格(8/3のopen/close)未到着、進行月のas_of評価 | 表示を止めない。provisionalで仮計算し追跡フィールドを付す |
| **CONFIRMED** | 全入力確定 | 境界価格・保有とも確定した過去月 | 確定値として保存 |
| **ERROR** | **存在すべきデータの欠損**・構成異常 | holding_signal欠損、weights空、必須過去価格欠落、config破損 | fail-visible。pendingで握りつぶさない |

pendingをERROR扱いしない(9a27eb4f型の全rollbackを再発させない)。ERRORをpendingで隠さない(fallback禁止は不変)。

### 3.2 実例タイムライン(下知■2の例、Q2-Q4の回答)

7/31(金)市場終了 → 8/1(土)暦上8月 → 8/3(月)8月初回取引:

- **8/1・8/2**: 7月のend_input=boundary(8月)の価格は**存在しない**。7月= `status=PENDING_EXPECTED`、値=provisional end(=as_of時点で利用可能な最新確定close=7/31 close)による仮計算。8月= boundary未形成につき期間が開始していない。表示は「8月: 開始待ち(pending)」であり、異常でもNULL消失でもない。
- **8/3市場後**: 8月境界が形成され境界価格が到着 → 7月のend_inputをprovisional(7/31 close)→正式(8/3の境界価格)へ**置換し、同一エンジンで再計算** → 7月=CONFIRMED。8月=進行月としてPENDING_EXPECTED(end=as_of)開始。
- 差し替わるのは**入力だけ**である。計算方式は切り替わらない(下知■3「同じ計算式に対して未確定入力が確定入力へ置換されるだけ」)。

### 3.3 provisional source(下知■7 — 設計案として提示。勝手に実装しない)

| 候補 | 内容 | 評価 |
|---|---|---|
| A | latest available market valuation | Cと実質同義だが「valuation」の定義が曖昧になりがち |
| B | 前市場日の確定Close | 明確・一次データのみ。ただし「前市場日」の解決が営業日判定に依存 |
| **C(推奨)** | **as_of時点で利用可能な最新確定価格(=直近close)** | Bと通常一致し、休日連続でも自明に定義され、pricesの一次データのみを使う(捏造ゼロ)。既存MTD計算の意味論と連続【現行MTDが実際に何を使うかは要現物確認】 |
| D | 現行UI意味論と整合する他の値 | cmd_4246 AC2の調査結果を待って比較 |

必須追跡フィールド: `provisional_source` / `provisional_as_of` / `missing_requirement`(何が到着すればconfirmedになるか)。**再計算保証**: 正式データ到着後の既存の定期再計算サイクルがpending行を必ず再評価する(新規の自動発火機構は作らない — 殿裁定2026-08-09 03:04「安易な自動実行の増設禁止」と整合)。

### 3.4 Open系列の注意

Open系列のend=境界日のopen。provisional期はopenが存在しないため、Open系列のpending値も「利用可能な最新確定値」で仮評価し、系列混在(closeをopenの代用として**保存**する等)は行わない — 仮計算値と仮の市場価格は別物(下知■6)。

## Part 4: historical repair(隔離レイヤー — 通常計算に持ち込まない)

今回事故で必要になった複雑性は全てここに住む。通常エンジンには現れない:

- **historical boundary resolver**: verification付き導出式(検証済ledger優先/expanded weights実切替日fallback/単純COALESCE禁止/root日付不採用)。歴史15,212行のledger backfill値が信頼できないための照合機構。**将来月には不要**(切替時に効力日を直接記録するため。現状の書込み実態は【要現物確認=cmd_4246】)
- **stale ledger失効**(effective_end=NULL無期限適用の是正、修正deploy済み)
- **backfill / 24anchor検証 / 7段実行順序 / backup+PF単位restore**: v5.22 WBS B4e/D系の実行装置
- **confirmed履歴の保全ガード**: cmd_4245の初回実装はrun231でFAIL確定(Phase0一括cleanupがガードより先に全PF履歴を消すためexisting_min/max=NULLで素通し)→revert 4d81c32+run232 full再計算で本番復旧(102PF・16,976行・2003-09〜2026-08、事前baseline完全一致=家老readonly実測2026-08-09 04:16)。**配置条件(run231実証=R11)**: 保全ガードは履歴を消し得る全操作(Phase0一括cleanup含む)の**上流**で効かなければ無意味 — 保護と破壊の順序はアーキテクチャの契約であり実装詳細ではない。後継実装は本再設計のMigration(Part 7)内で、通常経路=期間置換・全消し再構築=Part 4明示操作の分離とセットで設計する(実装は殿の別途下知)。それまでの暫定防御=mode='full'のみ運用(殿裁定2026-08-09 03:03: 知識層チェックリストが正、機構化しない)

v5.22の残工程(D/E系=本番浄化・三面一致、進捗75%)は**このレイヤーの台帳としてそのまま続行**する。再設計は残工程を無効化しない。

## Part 5: verification / migration(隔離レイヤー)

- 確定仕様オラクル(数値意味論§0.6-8含む)・全数監査・積=累積恒等式・検証者規約
- レーンS dual replay三分類とsignal影響評価(是正の一回性作業)
- 移行(migration): pending/confirmed導入時のschema変更・既存行のstatus付与は、cmd_4246調査後に本Partの移行計画として設計(実装は別途下知)
- 常設監視は最小の2つのみ: 正規形違反INSERT拒否(B5型)+月次1サイクル自然検証(E2型)

## Part 6: incident history(ポインタのみ)

- 事故の全経緯・棄却済み仮説・約90版の改訂履歴 = v5.22本文+`dm-monthly-trade-bug-genko-chain-archive_20260803.md`+gist 8cbc86a5。**削除ゼロ・移動のみ**(裁可後にv5.22をPart 4/5/6の台帳文書として再ラベルし、計算仕様の正本は本書系へ移す)

---

## Part 7: AsIs / Principle / ToBe / Migration(下知■13)

- **AsIs(どこが複雑か)**: Part 0の10項。本質は3つ — 歴史復元ロジックの定義への漏出(R1)、月クラス4分類によるエンジン分岐(R2)、pending不在によるERROR過剰(R3/R9)。コードレベルのAsIs接続はcmd_4246が確定する。
- **Principle(本来どうあるべきか)**: Part 1の9原則・5概念。
- **ToBe(最小構造)**: 単一エンジン+入力確定度タグ(Part 2)、三状態lifecycle(Part 3)、複雑性の2隔離レイヤー(Part 4/5)。通常経路の分岐=系列2×確定度2のみ。
- **Migration(既存データの安全な移行)**: (1)v5.22残工程(浄化D/E)は継続 — 歴史をCONFIRMEDへ是正する作業そのもの (2)pending導入のschema/API変更はcmd_4246調査後に移行計画を設計 (3)cmd_4245ガードがconfirmed履歴の保全を先行して固定 (4)全変更はbackupファースト+可逆で実行(実装は別途下知)。

## Part 8: 最重要レビュー質問への将軍回答(下知■14)

- **Q1**: Part 1の9行(数式1+境界1+系列1+空白1+momentum1+一次データ1+状態1+遡及1+評価定義1)。エンジン本体はPart 2.1の3行。
- **Q2**: 8/1・8/2の7月=PENDING_EXPECTED(値あり=provisional仮計算)、8月=境界未形成の開始待ちpending。NULL・表示消失・ERRORのいずれでもない(Part 3.2)。
- **Q3**: as_of時点で利用可能な最新確定価格(推奨案C)による同一エンジン仮計算。provisional_source/as_of/missing_requirementで根拠を追跡(Part 3.3)。
- **Q4**: end_inputだけが差し替わる(provisional価格→8/3境界価格)。エンジン・weight展開・系列は不変。再計算は既存定期サイクルが保証(Part 3.2-3.3)。
- **Q5**: 分岐していない(Part 2.1)。分岐の全量=系列×確定度の直積で機械判定(Part 2.2)。
- **Q6**: 区別している(Part 3.1の三状態表)。9a27eb4f型・L5 failed群がこの区別の不在の実証であり、本設計の直接の教訓。
- **Q7**: v5.22では漏れ出していた(R1/R4)。ToBeではhistorical resolverをPart 4へ隔離し、通常経路はPart 2.2の直積判定で漏出を機械検出。コード上の漏出実態はcmd_4246 AC2が列挙する。
- **Q8**: 混同していない(冒頭明記+Part 1-6)。momentum windowは不変更。
- **Q9**: 扱えている — FoF signal変化=「momentum inputである子PF月次系列の修正による二次効果」であり、遡及原則(ルール是正由来=受容)で管理(冒頭+Part 1-9)。
- **Q10**: **ledger**=保有正本(通常計算は確定holdingsとして消費するのみ。resolver複雑性はPart 4)。**boundary**=通常計算に必須(Part 1-3の中核概念)。**trade_performance**=記録・監査専用で通常のreturn計算に不要(Part 2.3)。**oracle/anchor/dual replay/backup**=Part 4/5専用。

## Part 9: 未決事項(殿裁定待ち — 設計案のみ、実装しない)

1. **provisional source**: 推奨案C(Part 3.3)。cmd_4246 AC2の現行実装調査後に最終案を上程。
2. **pending値のDB永続化方式**(下知■11): 候補=(a)runtime計算のみ(DBはconfirmedのみ保持。pendingはAPI層で都度計算)/(b)同一行にstatus/as_of/version列を持ち上書き/(c)pending専用キャッシュ層。**cmd_4246確定事実**: 現行は(a)に最も近い — Monthly Tradeのpendingは`monthly_returns`へ保存せず動的生成、schemaにstatus/as_of/provenance列なし。ただしMonthly Returns APIだけpendingを返せない非対称があり、statusのSSOT(型にはis_mtd/is_pendingがあるがDB行にない)が未決。**将軍の暫定推奨=案(a)+API統一**(既存動的pending機構の一般化。schema変更最小・confirmed偽装が構造的に不可能)だが、precomputed_raw cacheとの整合を含め殿裁可事項として上程する。「UIに常に値が必要だからconfirmedを偽装する」は全案で禁止(下知■11)。
3. **月替わり直後の新月(境界未形成月)の表示**: 「開始待ちpending」表示の具体形(値なしpending vs 0%表示等)はUI意味論調査後に提案。
4. **v5.22の再分類実行**(本書の6層への物理的な移設・再ラベル): 本書の殿裁可後に着手。

## 因果リンク

`[[殿下知_月次リターン基本原理再整理_20260809]] -> [[dm-monthly-trade-bug-asis-tobe-5w1h_20260802]] v5.22批判レビュー -> [[pending_confirmed_lifecycle]] -> [[migration_incident_recovery_layer]]分離`
関連: [[殿裁定_月次区間は執行日から執行日]] / [[月次リターン境界是正]] / [[cmd_4244三層根因偵察]] / [[cmd_4245ガード拡張]] / [[cmd_4246接続現物調査]]

## 改訂履歴

- v0.4 (2026-08-09 09:2x): cmd_4246現物調査統合 — R1/R9/R10を現物確定へ昇格(historical_backfill resolver混入・Monthly Trade/Returns APIのpending非対称・is_preliminary Open限定)。朗報2点(MTD同一エンジン済み・PriceCache backward=案C機構実装済み)をPart 0へ、Part 9-2のDB意味論を現物事実+将軍暫定推奨(案a+API統一)へ更新。R11(run231/232顛末=保護層が破壊層より下流→revert+full復旧)をPart 0/4へ焼込み(v0.3.1-0.3.2として先行反映済み)
- v0.3 (2026-08-09 04:0x): 初版起草(将軍直轄)。v5.22全文Read済み(453行)。Part 0レビュー10項+6層構造+Q1-Q10将軍回答。cmd_4246調査結果とQ回答(家老・軍師)の到着後にv0.x更新予定
