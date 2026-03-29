# CMD年代記 — 2026-03 前半 (03-09)
<!-- archived_from: context/cmd-chronicle.md -->
<!-- date_range: 2026-03-09 -->
<!-- cmd_range: cmd_662 - cmd_707 -->

> 2026年3月9日のcmd索引。本体: `context/cmd-chronicle.md`

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_666 | PF切り替え+ページ遷移の7.5秒遅延の根本原因を特定し、10倍速(750ms以内)を実現する | dm-signal | 03-09 | PF切替遅延偵察+改善 — 7.5秒→750ms目標 |
| cmd_668 | Dashboardはyears=0(全期間)で取得するが、prefetchはyears=3/20しか取得しない。prefetch側にyears=0を追加しキャッシュヒットさせる | dm-signal | 03-09 | prefetch側へ performance 0 / |
| cmd_669 | 背景画像で文字コントラストが不安定。無地背景をデフォルトにし、TextMutedのWCAG不合格を修正する | infra | 03-09 | Android アプリに背景ス |
| cmd_662 | WSL2からEdge/Chromeを自動操作するCDPヘルパーをライブラリ化し、忍者が毎回インラインで書く無駄を排除する | auto-ops | 03-09 | 全AC PASS。11関数レビュ |
| cmd_670 | cmd_668(prefetchにyears=0追加)デプロイ後のPF切り替え速度を本番で計測し、改善効果を定量確認する | dm-signal | 03-09 | PF切替高速化 効果計測 — cmd_668デプロイ後 |
| cmd_671 | PCターミナル出力をそのまま表示しているため小画面で読みにくい。フォントサイズ調整とピンチズームで各デバイスに最適化する | infra | 03-09 | AC1-7全PASS。フォントサ |
| cmd_673 | Google Classroomダッシュボードのクラウド完全自動化に向け、現行スクレイピング構成を解明し、Render上ヘッドレスChromeで過去に取得できなかった情報の原因を特定する | google-classroom | 03-09 | Google Classroomスクレイ |
| cmd_663 | Google Workspace CLI(gws)をインストールし、Gmail検索・Drive操作が動作する状態を確立する | auto-ops | 03-09 | AC1-5全PASS。gws 0.8.0更新 |
| cmd_674 | cmd_671で追加したピンチズーム(0.5x-3.0x)が不要と殿が判断。フォントサイズ4段階設定で可読性は十分。ピンチズーム関連コードを削除してコードをシンプルに保つ | infra | 03-09 | PASS。AC1-4全て満足。ピンチズーム関連コード(state/modi… |
| cmd_672 | cmd_668のyears=0 prefetch追加はBG prefetch量増加で逆効果(7.5s→9.4s)。revert後、Semaphore優先度制御を導入しユーザー操作をBGより優先する | dm-signal | 03-09 | ローカル実装は完了。`609558a` で cmd_668 を rever… |
| cmd_675 | ターミナル出力の折り返し表示をユーザーが切替可能にする。コードを見る時は折り返しなし、長文を読む時は折り返しありが便利 | infra | 03-09 | cmd_675 soft wrap設定実装 |
| cmd_677 | PCターミナルの全幅をスマホ画面にフィットさせる「縮小表示」と、細部確認の「拡大表示」を両立する。PDFビューアと同じ自然なピンチズームUX | infra | 03-09 | AC1-5 PASS。ShogunScreen と |
| cmd_678 | ターミナル表示エリアを最大化する。キーボード表示時に送信ボタンが隠れる致命的バグも修正 | infra | 03-09 | cmd_678 の Android UI 省ス |
| cmd_679 | cmd_677で導入した1.0x-3.0x拡大のみのピンチズームを拡張し、softWrap OFFモードでPC端末の全幅をスマホ画面にフィットさせる縮小表示を追加する | infra | 03-09 | cmd_679 ピンチズーム全 |
| cmd_680 | ターミナル出力更新時にユーザーが上にスクロールして読んでいると強制的に最下部に飛ばされるバグを修正する | infra | 03-09 | cmd_680 自動スクロール |
| cmd_681 | cmd_676 Phase2計測でDashboard warm cacheがAPI9本/合計19秒と判明。他ページの10倍以上遅い最大ボトルネック。9本のAPIの内訳を特定し、改善策を提示する | dm-signal | 03-09 | Dashboard API 19秒ボトルネック解析+改善 |
| cmd_676 | cmd_672でPF切替は-78%改善を確認したが、計測対象がPF切替+3ページのみ。全19ページの性能ベースラインを網羅計測し、次の最適化対象を特定する | dm-signal | 03-09 | AC1 PASS(18ページcold cache |
| cmd_682 | cmd_678で実装した接続バー圧縮とボトムナビ自動非表示に殿から2点の指摘。(1)接続バー「●」は意味がない→正常時は非表示に (2)ボトムナビが下にずれただけでターミナル表示が広がっていない→実装修正 | infra | 03-09 | cmd_682 review は FAIL。実 |
| cmd_684 | cmd_680で上スクロール中の強制復帰を抑止したが、大量にスクロールした後に最下部(最新出力+入力欄)に戻る手段がない。フローティングボタンでワンタップ復帰を実現する | infra | 03-09 | Androidアプリの Shogun 画 |
| cmd_685 | Dashboard高速化 Step1 — performance(years=0) prefetchキー不一致修正 | dm-signal | 03-09 | Dashboard高速化 Step1 — perfor... |
| cmd_683 | cmd_679のピンチズームが「スマホ表示を縮小するだけ」で全幅表示にならない。ブラウザの「PC版サイトを表示」のように、PCターミナルの全幅をスマホ画面に収める表示を実現する | infra | 03-09 | cmd_683 review PASS。対象3 |
| cmd_687 | Androidアプリ APKビルド+配布 | infra | 03-09 | Androidアプリ APKビルド+配布 |
| cmd_688 | ダッシュボード清掃 — 完了済み偵察結果5件+将軍宛報告の整理 | infra | 03-09 | ダッシュボード清掃 — 完了済み偵察結果5件+将軍宛報... |
| cmd_689 | fix — Androidアプリ「デスクトップ表示」ピンチズームが実機で動作しない | infra | 03-09 | fix — Androidアプリ「デスクトップ表示」ピ... |
| cmd_686 | DM-signal Dashboard高速化 Step2 — deterioration冗長取得の最適化 | dm-signal | 03-09 | DM-signal Dashboard高速化 Step... |
| cmd_690 | fix — DM-signalローカル開発環境復旧 + cmd_686 CDP検証完了 | dm-signal | 03-09 | fix — DM-signalローカル開発環境復旧 +... |
| cmd_691 | fix — requirements.txt欠落によるvenv再作成時のpip install静黙失敗 | infra | 03-09 | fix — requirements.txt欠落による... |
| cmd_693 | Androidアプリ ボトムナビゲーション常時表示化 | infra | 03-09 | Androidアプリ ボトムナビゲーション常時表示化 |
| cmd_694 | Androidアプリ APKビルド + バージョン管理 | infra | 03-09 | Androidアプリ APKビルド + バージョン管理 |
| cmd_696 | GitHub Release v5.0作成 + READMEダウンロードリンク更新 | infra | 03-09 | GitHub Release v5.0作成 + REA... |
| cmd_701 | 知識基盤の衛生維持。Vercel整合性リンク切れ修復+context追跡漏れ解消 | infra | 03-09 | teire修復完了。死参照 |
| cmd_700 | 偵察 — gws CLIでGmailメール件数取得の実現可能性検証 | auto-ops | 03-09 | 偵察 — gws CLIでGmailメール件数取得の実... |
| cmd_698 | fix — CI test_stop_hook.bats setup_file失敗の修正 | infra | 03-09 | fix — CI test_stop_hook.bat... |
| cmd_697 | CDP標準計測スクリプトの型化 — 誰がやっても同一結果 | dm-signal | 03-09 | CDP標準計測スクリプトの型化 — 誰がやっても同一結果 |
| cmd_692 | Dashboard高速化 Step3 — Dashboard非必須API即時発火の抑制 | dm-signal | 03-09 | Dashboard高速化 Step3 — Dashbo... |
| cmd_703 | 殿がダッシュボードを見た時にcmd番号だけでなく何の作業かが一目でわかる状態にする（殿裁定A案） | infra | 03-09 | 全AC PASS。5列テーブル |
| cmd_702 | 殿がダッシュボードを見た時に現役モデルのスコアだけが見える状態にする。古いモデルや思考の深さが違うデータは参考にならない（殿裁定） | infra | 03-09 | PASS — 全AC(1-5)検証完 |
| cmd_699 | 偵察 — CDPでGmailアクセスの実現可能性検証 | auto-ops | 03-09 | 偵察 — CDPでGmailアクセスの実現可能性検証 |
| cmd_705 | 偵察 — Render CLIインストール手順+デプロイ完了検知の実現可能性 | dm-signal | 03-09 | 偵察 — Render CLIインストール手順+デプロ... |
| cmd_704 | 確定申告Phase1 — Gmail請求メールリスト作成（殿選別用） | auto-ops | 03-09 | 確定申告Phase1 — Gmail請求メールリスト作... |
| cmd_695 | CDP計測のviewer認証自動化 — 人間待ちの排除 | dm-signal | 03-09 | CDP計測のviewer認証自動化 — 人間待ちの排除 |
| cmd_706 | CDP計測自動パイプライン — デプロイ完了検知→計測→ntfy通知 | dm-signal | 03-09 | CDP計測自動パイプライン — デプロイ完了検知→計測... |
| cmd_707 | GSD知見取込Phase1 — スタブ検出ゲート+分析麻痺ガード+偵察4観点並行偵察 | infra | 03-09 | GSD知見取込Phase1 — スタブ検出ゲート+分析... |
