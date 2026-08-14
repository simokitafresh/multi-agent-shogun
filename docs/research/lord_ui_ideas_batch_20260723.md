# 殿UI改善アイデア帳(2026-07-23 19:44〜) — まとめて実装バッチ

殿指示「アイデアを出すからメモしてくれ、慌てないでまとめて実装しよう」(19:56)。
殿の追加アイデアを本ファイルへ追記し、出揃ったら殿の合図でcmd群へ機械導出する。

## 記録済みアイデア

1. **FoFポートフォリオ名の色変更(compare-summary/compare-returns)** — 19:44
   - 殿: lightでコントラスト問題で見えづらい。違う色に。既存使用色から選ぶ(統一感、19:50)
   - 将軍実測: 現行text-purple-400=2.5:1(4.5:1未達)。既存FoFバッジ(app/admin/page.tsx:1078)が
     `text-purple-600 dark:text-purple-400` を既使用 → 同型採用でlight5.1:1/dark不変/FoF=紫維持
   - 状態: cmd_4133起票済み(配備保留、バッチ待ち)

2. **compare-returnsページの縦スクロール廃止** — 19:55
   - 対象表: Portfolio 104行(実測)。現在は縦スクロール。廃止=全行展開(ページスクロールに委ねる)と解釈
   - 要確認: 廃止の意味(内側スクロールコンテナ除去か、行数削減か)。sticky headerとの関係
   - 状態: 未起票

3. **棒グラフ/ヒストグラムのバー色統一** — 19:57
   - 殿: 色味が異なるのはrolling-returnsページだけ。他と同じ組み合わせへ
   - 要実測: rolling-returnsのバー色 vs 他ページ(annual-returns等)のバー色をCDPで確定
   - 状態: 未起票

4. **チャートのカード枠除去(dashboard基準)** — 20:03
   - 殿: チャートのカードが残っている。dashboardを参考に外す
   - 将軍CDP全ルート実測(チャート保有ページとcard枠):
     - /dashboard: 3チャート, card無し(基準✓) / /compare: 1, 無し✓ / /annual-returns: 1, 無し✓
     - **/rolling-returns: 1, card有り(border0.67px+shadow+radius16px)✗**
     - **/drawdowns: 1, card有り(同上)✗**
     - **/metrics: 1, card有り(border0.67px, radius0)✗**
     - monthly-returns/summary/deterioration/monthly-trade/trades: チャート0
   - 修正対象=rolling-returns/drawdowns/metricsの3ページのチャートcard撤去
   - 状態: 実測済・未起票

5. **チャート背景罫線(縦横グリッド線)の視認性調整** — 20:06
   - 殿: 見えづらい。コントラストと太さを調整
   - チャートは自作svg(recharts非依存)。罫線stroke/幅の現行値はバッチ着手時にCDP実測で確定→殿に調整案提示
   - 状態: 未起票(現行値実測要)

6. **ダークモード背景を完全黒→以前の濃紺へ** — 20:08
   - 殿: 完全な黒ではなく以前のような濃紺に
   - git履歴調査済: 以前の濃紺=**#0f172a(slate-900)**(コメント『メイン背景』付きで存在)。履歴上#0a0a0a(ほぼ黒)への変更が存在。現行globals.css L61は#0f172aだが、殿が黒と視認=本番darkの実効背景が別要素で上書きの可能性→バッチ着手時にCDP darkモードで実効値を実測して特定
   - 状態: 未起票(候補値=#0f172a確定済み)

7. **スマホ(Galaxy等)の横スクロール解消 — PF名表示の工夫** — 20:12
   - 殿: レスポンシブ時にGalaxy等の携帯で横スクロールが発生。PF名などの表示を工夫してスマホでは横スクロールが起きないように
   - 方針案: PF名のtruncate/短縮表示・列の優先度落とし等。対象ページ・発生箇所はCDPをGalaxy相当幅(360-412px)にemulateして全ルート実測してから確定
   - 関連: rolling-returnsのmd:hiddenモバイル専用表(既存のモバイル対応機構あり)を再利用候補に
   - **必須再現ケース(殿実機22:29+22:31)**: (a)『New Fund of Funds_copy_copy』級の長いPF名 (b)『+171.9%』級の桁長return数値、の双方で横スクロール発生。cmd_4139 AC1へ追記済み(長名20文字超+3桁符号小数return fixture、名前=省略表示+title参照/数値=省略せず列幅設計で収容)
   - **手段の優先順(殿裁定22:33)**: (1)モバイルのセルpaddingをcanonical縦12横8から一段削減(例: 縦8横4、モバイル専用値・PC不変) (2)数値列最小幅+文字列列圧縮 (3)PF名省略表示。paddingで収まる表は省略表示不使用
   - 状態: cmd_4139起票済み(先行UI群完了後に配備)

8. **チャートの系列色をテーブル方式に統一(PF=青系/BM=グレー系)** — 20:20
   - 殿: テーブルではPF名は青系、ベンチマークはグレー系で表示されている。チャートでも同じ方式にする
   - 方針: テーブル側の実際の青系/グレー系の具体値をCDP実測で確定→チャート系列色(線・バー)を同方式へ。FoF=紫(アイデア#1)との整合も確認
   - 状態: 未起票(テーブル側色の実測要)

9. **全テーブルの罫線統一 + BM/PF間の縦罫線** — 20:35
   - 殿: すべてのテーブルの罫線の色と太さを同じにする。ベンチマークとPFの間に縦の罫線を入れるスタイルに統一
   - 実測済の現状: thead下罫線が0px(無)と0.667px solid rgb(226,232,240)で混在(cmd_4131実測)。統一値は殿裁定要(候補=compare-summary式0.667px slate-200)
   - 縦罫線: BM列(SPY/TQQQ)とPF列の境界に縦罫線。各表のBM位置特定要
   - 状態: 未起票

10. **狭tier cap 1200→1100へ変更(canonical更新)** — 20:38
   - 殿: 狭いページがやや間延びして見える。1200から1100に。横スクロールが発生しないかも確認
   - canonical変更: knowledge:384b8a64/最終確定仕様の狭tier cap=1200を1100へ更新要(実装時に正本md+記憶DBも更新)
   - 検証: 実装後CDPで全狭tier表のh_scroll=false確認(現行table実測幅1088のため1100でも収まる見込みだが実測で確定)
   - 状態: 未起票

11. **compare-returns表の列幅フィット調整** — 20:40
   - 殿: 中央揃えだと間延びして見える。列の幅を調整してフィットするように
   - 補足: cmd_4132(中央寄せ)は配備済みのまま完遂させ、本件はバッチで列幅フィット(表実測幅866pxをcap内で自然幅に)を上乗せ
   - 状態: 未起票

12. **Deterioration Monitorのデフォルトソート=good先頭** — 20:47
   - 殿: デフォルトをgoodからソート(goodが一番上)方式に
   - CDP実測: 現状デフォルトはPF名順(DM2-test/DM3/DM4...)でステータス順ではない
   - 状態: 未起票

13. **Deterioration詳細の履歴が一部PFで欠落 — 計算/表示/cron batch確認、全PF長期間表示** — 20:50
   - 殿: PC版でクリック詳細に履歴があるPFとないPFがある。履歴は全て表示できるはず。計算方法と表示方法を確認、cron batch側かもしれない
   - 方針: 偵察cmd(backend deterioration履歴テーブルのPF別行数実査+cron batch計算範囲+frontend表示ロジック)→修正cmd。UI統一バッチとは別レーン(バックエンド調査を含むため)
   - 状態: 未起票(偵察要)

14. **セクションタイトル前の縦線(アクセントバー)統一 — Drawdownsだけ縦線あり** — 20:52
   - 殿: Drawdownsのページだけチャートやテーブルのタイトル前に縦線がある。全ページで統一するべき
   - 要裁定: 統一方向=縦線なし(多数派)に揃えるか、縦線あり(Drawdowns式)に揃えるか →殿へ質問中
   - 状態: 未起票

## CDP実測データ(20:45-21:00収集)
- **チャートCSS変数(SSOT実効値)**: --chart-primary=#0ea5e9(sky-500青)/--chart-benchmark=#94a3b8(slate-400グレー)/--chart-grid=#e2e8f0(slate-200)/--chart-reference=#94a3b8
- **#3バー色**: annual-returnsのバー=#3B82F6(blue-500)+#2DD4BF(teal-400)のハードコードhex。grid=currentColor(CSS変数を不使用)。rolling-returns/dashboard/compareの線チャートはCSS変数使用。※rolling-returnsのヒストグラムバーは初回probeで捕捉できず(要追測)
- **#5罫線**: グリッド線=stroke var(--chart-grid) width1が標準(rolling/dashboard/compare)。annualのみcurrentColor width1-1.5
- **#6 dark実効背景**: dark時 body=rgb(15,23,42)=#0f172a(既に濃紺)。「完全な黒」に見える別要素があるか要追測→殿の視認と実測が不一致のため対象ページ確認要
- **#8**: 全表の名前列実測=rgb(15,23,42)黒(dashboard/summary/monthly-trade/deterioration)。「テーブルでPF=青/BM=グレー」は表では未検出。チャート線が既にPF=#0ea5e9青/BM=#94a3b8グレー→殿の意図確認要
- **#12**: deterioration現状デフォルト=PF名順

15. **compare-returns表を他と同じ幅に** — 07-24 00:42
   - 殿: 他のテーブルと同じ幅にしよう。実測: 現状は列幅フィットで866px、他の狭tier表は約1088px(cap1100いっぱい)
   - 方針: 表をw-full化しcap1100幅へ拡張(cmd_4137の列幅フィットを上書き。中央寄せは自然に維持)
   - 状態: cmd_4143起票・委任済み(07-24 00:46)

16. **「一番上に戻る」ボタン/アイコン設置** — 07-24 00:42
   - 殿: 一番上に戻るボタンやアイコンの設置はどうだ？モックを見せてほしい
   - モック3案から**殿裁定(00:45)=案A(右下44px円形アイコン・スクロール300px超で出現・smoothスクロール・テーマ連動accent色)**
   - 全行展開(cmd_4137)で縦に長くなったcompare-returns等で特に有用。共通component化し全ページ組込み
   - 状態: cmd_4143起票・委任済み(07-24 00:46)

17. **monthly-trade Full時のみ画面幅いっぱい(モード連動cap切替)** — 07-24 00:54
   - 殿: fullの時だけcompare-summaryと同じ画面幅いっぱい、simple時は通常の1100
   - 実測根拠: Full時は表1208pxがcap1100内で圧迫(sticky+横スクロール状態)。compare-summaryコンテナ=画面幅94%利用が基準
   - 状態: cmd_4144起票・委任済み(07-24 00:56)

18. **dashboard Total Return Chartの遷移復帰時loading残留バグ** — 07-24 00:58
   - 殿実機: 他ページからdashboardへ戻るとTotal Return Chartだけloadingが回り続ける。リロードで即表示
   - 将軍CDP試行1回は未再現(spinner0/チャート3描画)=競合条件型と推定。リロード正常=初回マウント経路は健全、遷移復帰経路のみの問題
   - 状態: cmd_4145起票・委任済み(07-24 01:00。根因特定AC+再マウント契約test付き)

19. **deteriorationも縦スクロール廃止(compare-returns同型)** — 07-24 01:04
   - 殿: Deterioration Monitorも縦スクロール廃止でcompare-returnsと同じに
   - 内容: 内側縦スクロール廃止・全104行展開・thead stickyページ追従化。広tierのためcol1 sticky+横スクロールは維持
   - 状態: cmd_4146起票・委任済み(07-24 01:06)

20. **compare-summaryも縦スクロール廃止(compare-returns同型)** — 07-24 01:06
   - 殿: Compare Summaryも同様に
   - 内容: 内側縦スクロール廃止・全104行展開・thead stickyページ追従化。広tier(18列)のためcol1 sticky+横スクロールは維持
   - 状態: cmd_4147起票・委任済み(07-24 01:08)

## 確定裁定
- **#1確定(殿裁定20:29)**: FoF名=`text-blue-600 dark:text-blue-400`(admin PF種別バッジ app/admin/page.tsx:1077 と同色)。紫やめ青系。cmd_4133を青系基準へ書換済み(配備は引き続きバッチ待ち。家老へhold指示済21:20。残修正=split_decision 3キー+LG020数値証跡)
- **#10はcanonical変更**: 二層モデルの狭tier cap=1100が新正本(実装時に反映)
- **#14確定(殿裁定21:15)**: 縦線なしに統一。Drawdownsのタイトル前アクセントバーを除去
- **#2確定(殿裁定21:15)**: 表内側スクロールを廃止し全行展開。ページ全体スクロールで見る(sticky headerは追従)
- **#8確定(殿裁定21:15+実測)**: 出所=annual-returns表ヘッダ。実測値 PF列(DM-safe)=rgb(3,105,161)=sky-700青/SPY(BM)=rgb(100,116,139)=slate-500グレー。この「PF=青/BM=グレー」方式をチャートのバー/線にも適用(チャート変数--chart-primary #0ea5e9/--chart-benchmark #94a3b8が既に同方式。annual-returnsバーのハードコード#3B82F6/#2DD4BFをこの体系へ統一)
- **#6更新(殿裁定21:15)**: 現dark背景#0f172aは「濃紺が強すぎる」→以前の背景色に戻す。git履歴実査: globals.cssのdark--backgroundは2025-11-26=#0a0a0a(黒)→2025-12-31から現在まで#0f172aで7ヶ月不変。つまり「以前」に相当する第3の背景色はglobals.cssには存在しない。仮説=cmd_4131のcard撤去でやや明るいカード面(#1e293bなど)が消え、全面#0f172aになったことで「濃紺が強すぎる」印象に変化した可能性。候補: #1e293b(slate-800、一段明るい濃紺)を殿に提示中

## 実装方針(確定済みドクトリン)
- 測定=本番CDP一次(grep禁止)、canonical=殿裁定、per-task CDP禁止、既存パターン再利用(車輪防止)
- 出揃い後: 実測→canonical確定→cmd機械導出→並列配備→push→将軍CDP全数再検証
