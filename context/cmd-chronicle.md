# CMD年代記
<!-- last_updated: 2026-03-23 -->

> 完了cmdの1行索引。詳細は queue/archive/cmds/{cmd_id}.yaml 参照。

## 2026-03

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
| cmd_709 | 偵察 — おしお殿(yohey-w)最新システム深掘り+5大システム対比分析 | infra | 03-10 | 偵察 — おしお殿(yohey-w)最新システム深掘り... |
| cmd_708 | GSD知見取込Phase2 — 逸脱管理ルール(Deviation Management)+認知バイアスガード | infra | 03-10 | GSD知見取込Phase2 — 逸脱管理ルール(Dev... |
| cmd_710 | GSD知見取込Phase3 — 検証パイプライン拡張（配線検証+ゴール逆算+スコープ適正） | infra | 03-10 | GSD知見取込Phase3 — 検証パイプライン拡張（... |
| cmd_711 | GSD知見取込Phase1-2ブラッシュアップ — 検出漏れ穴3件修復+検証レベル体系化 | infra | 03-10 | GSD知見取込Phase1-2ブラッシュアップ — 検... |
| cmd_712 | CI修復 — gitignoreホワイトリスト漏れ+テスト不整合21件 | infra | 03-10 | cmd_712 review 完了。対象 |
| cmd_714 | CI全緑化 — Unit環境互換修正+E2E全スイート検証 | infra | 03-10 | レビューFAIL。`889a467 te |
| cmd_713 | Android: キーボード表示時スクロールジャンプ修正 | infra | 03-10 | 全6AC PASS。SideEffect+snaps |
| cmd_715 | CI緑維持ルール — push前ゲート+赤時自動修正フロー制度化 | infra | 03-10 | AC5: cmd_complete_gate.shにCI |
| cmd_716 | Android: cmd_713スコープ外変更の整理（revert+空白統一） | infra | 03-10 | Android: cmd_713スコープ外変更の整理（revert+空白統… |
| cmd_717 | Android: v5.4 APKビルド+GitHubリリース | infra | 03-10 | Android: v5.4 APKビルド+GitHubリリース |
| cmd_718 | Android: imePaddingをNavigationBarから各InputBarに移動 | infra | 03-10 | imePadding修正+v5.5ビルド |
| cmd_720 | 偵察(GSD式) — DM-Signal本番表示性能ボトルネック特定（4名同一テーマ・観点分割） | dm-signal | 03-10 | インフラ・ネットワー |
| cmd_719 | 偵察 — DM-Signal本番表示性能の定量把握（4名並列） | dm-signal | 03-10 | 主要4ページのAPI依存 |
| cmd_722 | DM-Signal表示性能ベースライン統合 — cmd_719+720知識恒久化 | dm-signal | 03-10 | cmd_719(領域分割4名)+cmd_720(GSD式4名)の全8報告を… |
| cmd_721 | Android: cmd_713+cmd_718のキーボード修正を全revert → v5.6リリース | infra | 03-10 | cmd_713/cmd_718 のキーボード修正を 3 ファイルで巻き戻し… |
| cmd_723 | DM-signalの.gitignoreが未追跡ファイルをカバーできておらず、機密ファイルや一時出力が放置されている状態を解消する | dm-signal | 03-10 | DM-signal `.gitignore` を整理し、`.env.pre… |
| cmd_724 | Phase1施策のうちRenderプラン制約に依存する2件（uvicorn --workers 2、signal-pie-chart dynamic import）がRender Proプランで実現可能かを事実ベースで確認する | dm-signal | 03-10 | 偵察 — Render Proプラン制約とPhase1施策2件の実現可能性… |
| cmd_727 | 現行cdp_helper.py（1記事ベース11関数）では網羅できていないCDP技法を調査し、我が軍のブラウザ自動化能力の拡張余地を特定する | auto-ops | 03-10 | WSL2+Windows CDP 偵察Bを完了。一次情報/技術記事/Git… |
| cmd_725 | プラン制約に依存しない確実な2施策を実装し、CDP本番計測で効果を定量検証する | dm-signal | 03-10 | cmd_726(テスト修正)PASS + |
| cmd_728 | 偵察 — DM-signal UIゼロベース再設計調査（現行全情報・全機能の最適実現方式） | dm-signal | 03-10 | DM-signalフロントエンド全19ページ棚卸し +... |
| cmd_729 | 現行ダークモードに加え、ライトモードとブラック(AMOLED)モードを追加し、コントラスト改善と視認性向上を実現する | infra | 03-10 | Android 3テーマ実装を完 |
| cmd_730 | 殿のUIデザインTips30項目をinfra教訓に登録 | infra | 03-10 | 殿のUIデザインTips30項目をinfra教訓に登録 |
| cmd_731 | 家老がcmd配備時にntfyで殿に送る通知にcmdのtitleが含まれず(untitled)と表示される問題を修正する | infra | 03-10 | deploy_task.sh の初回配備 |
| cmd_732 | MCP将軍専用の知識が忍者に届かない構造的な穴をふさぐ自動同期パイプラインの実現方式を調査し、設計案を提示する | infra | 03-10 | 偵察 — MCP将軍知識→lessons.yaml自動同期パイプラインの設… |
| cmd_734 | cmd_729で実装済みの3テーマ対応をv5.7としてバージョンバンプ+APKビルド+GitHubリリースする | infra | 03-10 | Android v5.7リリース完了 |
| cmd_733 | 初期ロード時のprefetch 83本を selected PF用3本に縮退し、初期表示速度を大幅改善する | dm-signal | 03-10 | cmd_733 は PASS。hanzo 実 |
| cmd_735 | 将軍がMCPに[share:ninja]マーカー付きで書いた知識を、自動的にlessons.yamlに登録するパイプラインを構築し、MCP→忍者の知識同期を恒久的に自動化する | infra | 03-10 | 佐助レビュー指摘2件 |
| cmd_736 | v5.7のAPKが署名なしでインストールできない問題を修正し、殿のスマホにインストール可能な状態にする | infra | 03-10 | レビューPASS。`android/ap |
| cmd_737 | CDP計測フレームワーク構築 — 汎用ベンチマークツール+認証自動化+教訓統合 | auto-ops | 03-10 | CDP計測フレームワーク構築 — 汎用ベンチマークツー... |
| cmd_726 | spa-navigation.test.tsxの既存FAIL3件を修正し、cmd_725のAC3ブロックを解消する | dm-signal | 03-10 | 佐助の `9ebedcb` をレビ |
| cmd_738 | /x-research Skillを構築し、将軍がClaude CodeからGrok経由でXのリアルタイム検索・トレンド収集を実行できるようにする | infra | 03-10 | X検索Skillをxai Grok API経 |
| cmd_739 | /weekly-report Skillを構築し、DM-Signal Weekly Reportの記事生成を将軍が一発で再現可能にする | dm-signal | 03-10 | /weekly-report Skill を新設。DM-Signal AP… |
| cmd_745 | cmd_744で認証組み込みしたCDP計測フレームワークが、本番環境で一切の手動介入なく全ページ計測を一発完了できることを実戦検証する | auto-ops | 03-11 | verify — CDP計測フレームワーク実戦検証（本番全ページ一発計測） |
| cmd_744 | CDP計測フレームワーク(perf_measure.py)に本番viewer認証を組み込み、忍者が引数指定だけで認証済み本番計測を一発実行できる状態にする | auto-ops | 03-11 | perf_measure.pyに本番viewer |
| cmd_740 | perf — SignalsContext value useMemo化（全ページ再レンダー防止） | dm-signal | 03-10 | perf — SignalsContext value... |
| cmd_741 | layout.tsxでグローバルimportされているkatex CSSを、実際に使用するdocsページのみに限定し、全ページから不要な27KB CSSを排除する。CDP本番計測で改善効果を定量検証する | dm-signal | 03-11 | 佐助のcmd_741 impl報告を |
| cmd_743 | uvicornのワーカー数を1→2に増設し、APIの同時処理能力を倍増させる。CDP本番計測で改善効果を定量検証する | dm-signal | 03-11 | cmd_743 impl 完了。`render. |
| cmd_742 | signal-pie-chartコンポーネントをdynamic importに変更し、rechartsライブラリ(~280KB)を初期バンドルから排除する。CDP本番計測で改善効果を定量検証する | dm-signal | 03-11 | AC1-AC4 PASS。半蔵独自検 |
| cmd_747 | docs/research/cmd_719_720_performance-baseline.md と context/dm-signal-frontend.md に含まれるコールドスタート誤認を修正し、完了済み施策の状態を反映して、偵察報告を事実に基づく正確な内容にする | dm-signal | 03-11 | cmd_747 は PASS。欠落し |
| cmd_742 | signal-pie-chartコンポーネントをdynamic importに変更し、rechartsライブラリ(~280KB)を初期バンドルから排除する。CDP本番計測で改善効果を定量検証する | dm-signal | 03-11 | AC1-AC4 PASS。半蔵独自検 |
| cmd_751 | cmd_743(3e515ca)で導入したuvicorn --workers 2をrevertし、本番のviewer認証障害を即時復旧する | dm-signal | 03-11 | render.yamlのstartCommandか |
| cmd_749 | 偵察 — 全ページのアドミンログイン動作検証（本番で一部ページでログインが効かない） | dm-signal | 03-11 | 担当3ページ(/admin, /admin/fof, ... |
| cmd_752 | fix — viewerトークンをDB保存に移行（workers複数化の前提条件） | dm-signal | 03-11 | viewerトークンをインメモリdict(_viewe... |
| cmd_753 | cmd_749偵察で発見された3件の副次的バグについて、修正実装に必要なコードの全容（変更箇所・影響範囲・テスト対象・エッジケース）を特定し、後続のfix cmdが手戻りなく一発で完了できる材料を揃える | dm-signal | 03-11 | /monthly-trade は navigation 側で portfo… |
| cmd_754 | 偵察cmdの成果物が『修正実装に直結する粒度』をデフォルトで満たす状態にする。ルール追記だけでなく、ゲートで機械的に検証し、不足があればBLOCKする仕組みを構築する | infra | 03-11 | 半蔵のcmd_754実装をレビュー。4ファイル全てコード品質良好、構文PA… |
| cmd_755 | backend/app/auth.pyの_admin_tokens dictをDBに移行し、uvicorn workers複数化でadmin認証が壊れない状態にする。cmd_752(viewer_tokens)と同パターン | dm-signal | 03-11 | fix — admin_tokensをDB保存に移行（cmd_752のad… |
| cmd_748 | 偵察 — 性能改善残施策4件の実装根拠深堀り（コード実態+副作用+効果見積り） | dm-signal | 03-11 | 偵察 — 性能改善残施策4件の実装根拠深堀り（コード実... |
| cmd_756 | cmd_753偵察で実装直結粒度まで調査済みの3件を一括修正し、認証周辺の潜在バグを一掃する | dm-signal | 03-11 | review retry 完了。指定6 |
| cmd_759 | fix — Cookie expiry TZズレ修正（JST/UTCの9時間差でcookieが早期失効） | dm-signal | 03-11 | fix — Cookie expiry TZズレ修正（... |
| cmd_746 | CDP計測フレームワーク(perf_measure.py)を、忍者がコマンド一発で本番の全計測パターン（cold/warm/PF切替/SPA遷移/API個別応答）を実行でき、前回結果と自動比較できる完全なシステムに仕上げる | auto-ops | 03-11 | CDP計測フレームワーク |
| cmd_758 | PF切替時に1本のAPIが401を返しただけで全viewerセッションが崩壊する連鎖崩壊を修正し、単発401をエンドポイント単位で隔離する | dm-signal | 03-11 | AC1-AC5 PASS。viewer 401 を『単発即死』から『短時間… |
| cmd_757 | GATE CLEAR連勝が377から0にリセットされた原因を特定し、FAILしたcmdとその理由を報告する | infra | 03-11 | 377→0 を起こしたのは |
| cmd_760 | fix — FE api-client.ts 304対応（既存ETag 3件の有効化+将来拡充の前提整備） | dm-signal | 03-11 | FE api-client.ts 304対応（ETag... |
| cmd_761 | 偵察(水平) — dm-signal改善点洗い出し（4領域×1名、定量データ収集） | dm-signal | 03-11 | 偵察(水平) — dm-signal改善点洗い出し（4... |
| cmd_762 | dm-signalの最大のボトルネック・最高ROI改善策を、4名が異なる観点から独立分析し、結論を突合して盲点を炙り出す | dm-signal | 03-11 | 最大のボトルネックは |
| cmd_764 | 偵察 — DM-Signal trade rule全容の理解（シグナル/モメンタム/保有シグナル/リバランス） | dm-signal | 03-11 | 偵察 — DM-Signal trade rule全容... |
| cmd_763 | 認証インフラ修正（DB化+401 handler+Cookie TZ）が全て完了したため、uvicorn workers=2を再投入し、本番の同時処理能力を回復する。CDP計測で効果を定量検証する | dm-signal | 03-11 | workers=2デプロイ後curl |
| cmd_765 | 毎回のclearSignalsCache()によるTTL無効化を廃止し、stale-while-revalidateパターンを導入して初回ロード2-5秒の空白画面を解消する | dm-signal | 03-11 | 前任(才蔵)のSWR化実装 |
| cmd_766 | BE関連のdm-signal cmdに取り組む忍者が、trade-rule.mdの正式ルール（特にRULE09/10/11とLLMが間違えやすい14誤解パターン）を自動的に参照できる状態にする | dm-signal | 03-11 | trade-rule教訓8件を `lesso |
| cmd_750 | 偵察 — viewer認証の間欠的unauthorized問題（PF切替で発生、workers 2化の影響疑い） | dm-signal | 03-11 | viewer/admin認証トークンがBE側インメモリ... |
| cmd_767 | fix — trade-rule.md LLM誤読防止の7箇所補完 | dm-signal | 03-11 | fix — trade-rule.md LLM誤読防止... |
| cmd_769 | fix — trade-rule.md MECE整合性レビュー+今回の殿裁定6件反映 | dm-signal | 03-11 | cmd_769 impl(小太郎)のtrade-rul... |
| cmd_768 | fix(critical) — Trade期間リターンを月次複利合成に修正+四神・忍法再選定 | dm-signal | 03-11 | GSパイプライン内に `calculate_trade... |
| cmd_770 | fix — business_rules.md 現行コード・殿裁定との乖離10箇所修正 | dm-signal | 03-11 | PASS。佐助retry(commit `17378c... |
| cmd_771 | context鮮度回復 — dm-signal-core.md BE認証基盤変更(cmd_752/755/759/760)反映 | dm-signal | 03-11 | `context/dm-signal-core.md`... |
| cmd_772 | fix — trade-rule.md §7.3a逆参照追加+cmd_768完了に伴う不要コメント削除 | dm-signal | 03-11 | trade-rule.mdとprojects/dm-s... |
| cmd_773 | 偵察 — FEコンポーネント・ロジック重複の全量洗い出し | dm-signal | 03-11 | app/**/page.tsx のトップレベル宣言を棚... |
| cmd_775 | 偵察 — /api/monthly-returns 1721ms ボトルネック切り分け | dm-signal | 03-11 | 偵察 — /api/monthly-returns 1... |
| cmd_774 | 偵察 — /dashboardバンドル分析（238kB内訳特定+削減候補） | dm-signal | 03-11 | 偵察 — /dashboardバンドル分析（238kB... |
| cmd_776 | fix — lesson_candidate旧形式BLOCK根治（3層自動修正+共通関数） | infra | 03-11 | fix — lesson_candidate旧形式BL... |
| cmd_777 | 偵察 — STALL誤判定の実態調査+CLI間フック互換性+長時間Bash保護策の設計材料収集 | infra | 03-11 | 偵察 — STALL誤判定の実態調査+CLI間フック互... |
| cmd_778 | fix — context鮮度の自動検知（時間ベースWARN+cmd完了時nudge） | infra | 03-11 | cmd_778 review PASS。`contex... |
| cmd_779 | fix — BEテスト陳腐化削除+SKIP修復+pycache清掃 | dm-signal | 03-11 | fix — BEテスト陳腐化削除+SKIP修復+pyc... |
| cmd_780 | impl — deteriorationモジュール テストカバレッジ追加（BE 3ファイル） | dm-signal | 03-11 | deterioration service/batch... |
| cmd_781 | fix — STALL誤判定防御（pstree子プロセス検知+PreToolUseフック併用） | infra | 03-11 | fix — STALL誤判定防御（pstree子プロセ... |
| cmd_782 | 偵察(水平) — DM-signal最適化 実装設計（4領域分割） | dm-signal | 03-11 | 偵察(水平) — DM-signal最適化 実装設計（... |
| cmd_783 | 偵察(垂直) — DM-signal最適化 盲点発見（GSD式4観点） | dm-signal | 03-11 | 偵察(垂直) — DM-signal最適化 盲点発見（... |
| cmd_784 | impl — formatJST共通化（lib/date.ts抽出 + 10ファイル置換） | dm-signal | 03-11 | impl — formatJST共通化（lib/dat... |
| cmd_785 | impl — FolderFilterChip共通コンポーネント抽出（4ファイル→1） | dm-signal | 03-11 | impl — FolderFilterChip共通コン... |
| cmd_786 | impl — FEバンドル最適化3点（date-fns除去 + lucide optimize + dynamic import） | dm-signal | 03-11 | impl — FEバンドル最適化3点（date-fns... |
| cmd_788 | 偵察 — BE APIレスポンス ベースラインスナップショット取得 | dm-signal | 03-11 | API baseline取得（signals/metr... |
| cmd_789 | 偵察 — 本番PFリスト取得 + protected_portfolios突合 | dm-signal | 03-11 | 本番PFリストとprotected_portfolio... |
| cmd_787 | impl — PersistentFolderFilter hook抽出 + Page shell抽出 | dm-signal | 03-11 | Phase2a Part2: PageShellコンポ... |
| cmd_790 | 偵察 — BEベースライン再取得（正確PFセット15体×全期間×全API） | dm-signal | 03-11 | AC1-AC5完了。BEベースライン再取得 |
| cmd_791 | impl — monthly-returns API高速化（expanded_tickersスキップ + months前倒しslice） | dm-signal | 03-11 | monthly-returns APIからexpand... |
| cmd_792 | impl — 304エラー扱いバグ修正 + ETag有効化 | dm-signal | 03-11 | impl — 304エラー扱いバグ修正 + ETag有効化 |
| cmd_795 | impl — done通知スクリプト化（報告空欄チェック強制） | infra | 03-11 | cmd_795再レビューPASS。b |
| cmd_796 | context鮮度回復 — dm-signal系4ファイルに直近cmd成果… | dm-signal | 03-11 | dm-signal-core.md と dm-signa |
| cmd_797 | fix — E2E teardown cleanup失敗によるCI RED… | infra | 03-11 | cmd_797事後レビューは P |
| cmd_798 | 偵察 — NDL OCR-Lite 深掘り調査（サーバーサイド運用設計） | infra | 03-11 | 偵察 — NDL OCR-Lite深掘り調査(サーバーサイド運用設計) |
| cmd_793 | impl — SWR化（stale-while-revalidate キャ… | dm-signal | 03-11 | cmd_793 re-review は PASS。p |
| cmd_802 | 衛生 — logs/ログローテーション導入(ninja_monitor 1… | infra | 03-11 | cmd_802ログローテーシ� |
| cmd_799 | 衛生 — pending_decisions.yamlアーカイブ + cm… | infra | 03-11 | cmd_799レビュー PASS。PD� |
| cmd_801 | 衛生 — shogun_to_karo_done.yaml(44,698行… | infra | 03-11 | cmd_801レビューPASS。5スクリプトからdone.yaml参照完全… |
| cmd_850 | 整備 — cmd-chronicle空欄key_result補完（18行） | infra | 03-12 | 整備 — cmd-chronicle空欄key_result補完（18行） |
| cmd_849 | impl — B3 prefetch/page fetch責務統一 | dm-signal | 03-12 | impl — B3 prefetch/page fetch責務統一 |
| cmd_851 | 修正 — cmd_complete_gate.sh TSV ninja=n… | infra | 03-12 | 修正 — cmd_complete_gate.sh TSV ninja=n… |
| cmd_852 | 計測 — CDP After-After計測 Group1（Home/Da… | dm-signal | 03-12 | 計測 — CDP After-After計測 Group1（Home/Da… |
| cmd_856 | 検証 — Wave1-3 BE変更後の計算結果完全一致確認（シグナル不変精… | dm-signal | 03-12 | 検証 — Wave1-3 BE変更後の計算結果完全一致確認（シグナル不変精… |
| cmd_855 | 計測 — CDP After-After計測 Group4（Deterio… | dm-signal | 03-12 | 計測 — CDP After-After計測 Group4（Deterio… |
| cmd_853 | 計測 — CDP After-After計測 Group2（Compare… | dm-signal | 03-12 | 計測 — CDP After-After計測 Group2（Compare… |
| cmd_857 | 改善 — CDP計測フレームワーク安定化（Chrome移行+preflig… | dm-signal | 03-12 | 改善 — CDP計測フレームワーク安定化（Chrome移行+preflig… |
| cmd_858 | 整備 — DM-signal .gitignore整理整頓 | dm-signal | 03-12 | 整備 — DM-signal .gitignore整理整頓 |
| cmd_854 | 計測 — CDP After-After計測 Group3（Rolling… | dm-signal | 03-12 | CDP本番計測Group3（Rolling Returns/ |
| cmd_859 | 万全偵察 — P(det)信頼性検証+弱体化入替忍法の設計調査（水平4+垂… | dm-signal | 03-12 | P(det)入替忍法は「条件付きで成立可能」。最大リスクは過剰入替(whi… |
| cmd_860 | 万全偵察 — パフォーマンス持続性の数学的定量化手法調査（ベイズ/構造変化… | dm-signal | 03-12 | 4手法の非専門家向け解釈可能性は手法ごとに大きく異なる。 ベイズ持続確率(… |
| cmd_861 | 万全偵察 第2弾 — パフォーマンス持続性 追加7手法調査（HMM/AFM… | dm-signal | 03-12 | 万全偵察 第2弾 — パフォーマンス持続性 追加7手法調査（HMM/AFM… |
| cmd_863 | 辞書基盤構築 — 金融ML知識辞書のVercelスタイル骨格作成+cmd_… | dm-signal | 03-12 | 金融ML知識辞書のVercelスタイル骨格を構築完了。 6デ |
| cmd_862 | 万全偵察 第3弾 — López de Prado全講義・論文の体系的知見… | dm-signal | 03-12 | 万全偵察 第3弾 — López de Prado全講義・論文の体系的知見… |
| cmd_865 | 新PJ登録+偵察 — 殿の株式データベース（simokitafresh/d… | database | 03-12 | /mnt/c/Python_app/database リポジ |
| cmd_864 | 辞書充填 — cmd_860/861の全知見をknowledge-base… | dm-signal | 03-12 | knowledge-base 既存8エントリを更新し、cmd_860 の不… |
| cmd_866 | 辞書充填 — cmd_862のDC6件+教訓候補5件をknowledge-… | dm-signal | 03-12 | cmd_862統合報告のDC6件+LC5件を既存knowledge-bas… |
| cmd_867 | 辞書新設 — DM-Signalメタ構造の明示的記述+全エントリへの織り込み | dm-signal | 03-12 | 辞書新設 — DM-Signalメタ構造の明示的記述+全エントリへの織り込み |
| cmd_868 | 偵察 — 四神PFの実データ構造確認（データ長・相関・ファミリー構成） | dm-signal | 03-12 | 偵察 — 四神PFの実データ構造確認（データ長・相関・ファミリー構成） |
| cmd_870 | 恒久ルール追加 — 一次データ不可侵原則の全層明文化 | infra | 03-12 | 一次データ不可侵原則を全3層(ashigaru.md, karo.md, … |
| cmd_869 | 辞書構造改革 — 一次知識層とDM-Signal解釈層の分離+メタ構造記述 | dm-signal | 03-12 | 辞書構造改革 — 一次知識層とDM-Signal解釈層の分離+メタ構造記述 |
| cmd_871 | 辞書構造改革（8人全並列）— 一次知識層浄化+DM-Signal解釈層新設… | dm-signal | 03-12 | AC3: meta-structure.md新規作成完了。AC4: cmd… |
| cmd_872 | 辞書検証トレーサビリティ必須化 — 全エントリに出典・検証日・検証方法を記録 | dm-signal | 03-13 | knowledge-base の guide と methods/11件に… |
| cmd_873 | GSD式偵察 — 家老サブエージェント活用の設計検討（4観点独立分析） | infra | 03-13 | 家老サブエージェント導入の7失敗シナリオを分析。殿の核心指示「制限がキモ」… |
| cmd_875 | 実装 — gstack知見Tier1: 忍者プロンプト強化+タスクYAML… | infra | 03-13 | gstack知見Tier1。L215/L216登録 |
| cmd_878 | 修正 — 教訓injection_count同期修復+deprecatio… | infra | 03-13 | PD-002根本解決。L217登録 |
| cmd_876 | 実装 — gstack知見Tier2: 家老レビュー強化+PJ知識拡張+定… | infra | 03-13 | gstack知見Tier2。L218登録。自動退役4件 |
| cmd_877 | 実装 — gstack知見Tier3: CDP persistent da… | infra | 03-13 | gstack知見Tier3 |
| cmd_883 | 修正 — 知識基盤衛生修復（context鮮度+リンク切れ+gitignoreホワイトリスト） | infra | 03-13 | dm-signal.md cmd_804リンク切れ修復+database.md gitignoreホワイトリスト (cmd_883_B) |
| cmd_884 | 修正 — cmd-chronicle空欄補完（title37行+key_result92行） | infra | 03-13 | fix: fill cmd chronicle blanks for cmd_884 |
| cmd_888 | 偵察 — gate×skill自動修復パターンの外部知見調査（GSD/gstack/業界事例） | infra | 03-13 | 偵察 — gate×skill自動修復パターンの外部知見調査（GSD/gstack/業界事例） |
| cmd_887 | 偵察 — 忍者作業の繰り返しパターン分析+スキル化候補洗い出し | infra | 03-13 | 偵察 — 忍者作業の繰り返しパターン分析+スキル化候補洗い出し |
| cmd_886 | 偵察 — SPA遷移不成立の根本原因調査（Web+X検索含む） | dm-signal | 03-13 | 偵察 — SPA遷移不成立の根本原因調査（Web+X検索含む） |
| cmd_885 | 修正 — CDP 2系統統廃合（Legacy helper廃止→Daemon mode一本化） | auto-ops | 03-13 | add --remote-allow-origins=* to Chrome launch args (cmd_885_D) |
| cmd_880 | 実装 — SPA Phase2: Sidebar Link化+CDP動作検証 | dm-signal | 03-13 | cancelled |
| cmd_881 | 実装 — SPA Phase3: Dropdown Link化+CDP動作検証 | dm-signal | 03-13 | cancelled |
| cmd_890 | 修正 — help-link.tsx SPA遷移廃止→window.location.href統一 | dm-signal | 03-13 | 修正 — help-link.tsx SPA遷移廃止→window.location.href統一 |
| cmd_892 | 偵察 — Render frontend build failure調査（render-cli log取得） | dm-signal | 03-13 | 偵察 — Render frontend build failure調査（render-cli log取得） |
| cmd_891 | 修正 — skill_candidateフィールド活性化（忍者がスキル提案できる仕組み） | infra | 03-13 | skill_candidateフィールド活性化 — 記入ガイド+判定基準+処理フロー追加 (cmd_891_A) |
| cmd_893 | 修正 — Render build failure復旧（isLoadingMore prop型定義+redeploy） | dm-signal | 03-13 | 修正 — Render build failure復旧（isLoadingMore prop型定義+redeploy） |
| cmd_889 | 修正 — HomeButton SPA遷移廃止→window.location.href統一 | dm-signal | 03-13 | 修正 — HomeButton SPA遷移廃止→window.location.href統一 |
| cmd_879 | 実装 — SPA Phase1: HomeButton Link化+CDP動作検証 | dm-signal | 03-13 | cancelled |
| cmd_882 | 修正 — SPA Phase1修正: buildUrlWithPortfolio SSR対応+再検証 | dm-signal | 03-13 | cancelled |
| cmd_895 | 偵察 — note CDP自動ログイン+資料ページDOM構造調査 | auto-ops | 03-13 | 偵察 — note CDP自動ログイン+資料ページDOM構造調査 |
| cmd_894 | 実装 — note売上手数料PDF Google Driveアップロード+CSV追記 | auto-ops | 03-13 | 実装 — note売上手数料PDF Google Driveアップロード+CSV追記 |
| cmd_896 | 実装 — 個人事業_2025.csv 15列フォーマット移行（既存187行+新規14行） | auto-ops | 03-13 | 実装 — 個人事業_2025.csv 15列フォーマット移行（既存187行+新規14行） |
| cmd_898 | 実装 — 経費マスターSpreadsheet作成+個人事業READMEドキュメント整備 | auto-ops | 03-13 | 実装 — 経費マスターSpreadsheet作成+個人事業READMEドキュメント整備 |
| cmd_897 | 偵察 — MoneyForward CDP自動ログイン+家計簿CSV DLページDOM構造調査 | auto-ops | 03-13 | 偵察 — MoneyForward CDP自動ログイン+家計簿CSV DLページDOM構造調査 |
| cmd_899 | 修正 — マスターCSV「殿コメント」→「補足メモ」カラム名変更 | auto-ops | 03-13 | Drive上の個人事業_2025.csvヘッダー13列目「殿 |
| cmd_900 | 実装 — MoneyForward CDPログイン+グループ選択+家計簿CSV自動DLパイプライン | auto-ops | 03-13 | 実装 — MoneyForward CDPログイン+グループ選択+家計簿CSV自動DLパイプライン |
| cmd_902 | 整理 — auto-ops gitignore整備+未追跡ソースコミット+プッシュ | auto-ops | 03-13 | 整理 — auto-ops gitignore整備+未追跡ソースコミット+プッシュ |
| cmd_903 | 整理 — DM-signal 未コミットファイル一括コミット+プッシュ | dm-signal | 03-13 | 整理 — DM-signal 未コミットファイル一括コミット+プッシュ |
| cmd_904 | 整理 — shogun 未コミットファイル一括コミット+プッシュ | infra | 03-13 | 整理 — shogun 未コミットファイル一括コミット+プッシュ |
| cmd_901 | 実装 — CDP基盤にsnapshot+ref方式を組込み（gstack browse知見転用） | auto-ops | 03-13 | 実装 — CDP基盤にsnapshot+ref方式を組込み（gstack browse知見転用） |
| cmd_905 | 実装 — CDP Chrome自動クリーンアップ（PID追跡+idle時自動kill） | auto-ops | 03-13 | integrate CDP Chrome idle cleanup into ninja_monitor (cmd_905_B) |
| cmd_906 | 実装 — Render APIキー共通ローダー（.env自動読込ヘルパー） | dm-signal | 03-13 | Render APIキーの共通ローダー `scripts/l |
| cmd_908 | 実装 — note.com売上CSV+購入領収書PDF自動取得パイプライン | auto-ops | 03-13 | 実装 — note.com売上CSV+購入領収書PDF自動取得パイプライン |
| cmd_907 | 偵察 — MoneyForward認証方式調査（TOTP対応+email_otp自動化可否） | auto-ops | 03-13 | 偵察 — MoneyForward認証方式調査（TOTP対応+email_otp自動化可否） |
| cmd_909 | 実装 — MFパイプラインTOTP自動認証統合+live実証 | auto-ops | 03-13 | 実装 — MFパイプラインTOTP自動認証統合+live実証 |
| cmd_911 | 改善 — スキル品質是正（description統一+バリデーションスクリプト） | infra | 03-13 | 既存12スキルのdescriptionをWhat+When+ |
| cmd_910 | 実証 — note.comパイプラインlive実行（売上CSV+領収書PDF） | auto-ops | 03-13 | absorbed→cmd_912 |
| cmd_913 | 改善 — gstack停止条件二分法の導入（stop_for/never_stop_for） | infra | 03-13 | never_stop_forにデフォルト3条件を注入 (cmd_913_A) |
| cmd_915 | 実装 — PDFリネーム+Drive自動アップロードパイプライン | auto-ops | 03-13 | 実装 — PDFリネーム+Drive自動アップロードパイプライン |
| cmd_914 | 実装 — MF CSV→マスターCSV変換+マージパイプライン | auto-ops | 03-13 | 実装 — MF CSV→マスターCSV変換+マージパイプライン |
| cmd_912 | 修正 — note_pipeline購入領収書→PF手数料領収書に差替え+live実証 | auto-ops | 03-13 | 修正 — note_pipeline購入領収書→PF手数料領収書に差替え+live実証 |
| cmd_916 | 偵察 — 経費マスター19パターン証票入手経路の棚卸し | auto-ops | 03-13 | 偵察 — 経費マスター19パターン証票入手経路の棚卸し |
| cmd_918 | 修正 — receipt_manager.py unknown続行+サブフォルダ重複の2件修正 | auto-ops | 03-13 | 修正 — receipt_manager.py unknown続行+サブフォルダ重複の2件修正 |
| cmd_917 | 修正 — expense_csv.py 振込手数料fail-close+非月次CSV停止の2件修正 | auto-ops | 03-13 | 修正 — expense_csv.py 振込手数料fail-close+非月次CSV停止の2件修正 |
| cmd_919 | 実装 — 年度統合パイプライン（確定申告用一括処理） | auto-ops | 03-13 | 実装 — 年度統合パイプライン（確定申告用一括処理） |
| cmd_922 | 偵察 — MoneyForwardログインフォーム検出タイムアウト原因調査 | auto-ops | 03-13 | 偵察 — MoneyForwardログインフォーム検出タイムアウト原因調査 |
| cmd_921 | 修正 — annual_pipeline.py MFステップ例外ハンドリング追加 | auto-ops | 03-13 | 修正 — annual_pipeline.py MFステップ例外ハンドリング追加 |
| cmd_923 | 修正 — MFログイン既ログインredirect対応（fast-path追加） | auto-ops | 03-13 | 修正 — MFログイン既ログインredirect対応（fast-path追加） |
| cmd_924 | 修正 — note売上CSV取得を月別12回→1回に最適化 | auto-ops | 03-13 | 修正 — note売上CSV取得を月別12回→1回に最適化 |
| cmd_925 | 実装 — gstack Tier1適用: Suppressions+推薦先行+WHY（忍者報告品質） | infra | 03-14 | complete cmd_925 suppressions S1-S12 + recommendation WHY |
| cmd_926 | 実装 — gstack Tier1適用: Priority Hierarchy+並列実行明示（タスクYAML自動注入） | infra | 03-14 | ac_priority/parallel_okの空sentinel補完+extract_ac_ids (cmd_926) |
| cmd_928 | 実装 — gstack将軍適用: 推薦先行+WHY/モードコミットメント/Temporal Interrogation/Dream State Mapping | infra | 03-14 | approve scope_mode cmd format fix |
| cmd_929 | 実装 — gstack忍者適用: 反復STOP+名前をつけろパターン | infra | 03-14 | AC完了チェックポイント+報告具体性ルール+ac_checkpoint自動注入 (cmd_929) |
| cmd_930 | 修正 — note CDPを月ごとfresh tab+失敗時リトライに変更 | auto-ops | 03-14 | 修正 — note CDPを月ごとfresh tab+失敗時リトライに変更 |
| cmd_931 | 偵察 — gstack深掘り調査（GSD式4観点+水平4領域=8名全投入） | infra | 03-14 | gstack深掘り偵察統合レポート (cmd_931_INT) |
| cmd_920 | 実行 — 年度統合パイプライン2025年本番実行 | auto-ops | 03-14 | 実行 — 年度統合パイプライン2025年本番実行 |
| cmd_927 | 実装 — gstack Tier2適用: Engineering Preferences（PJ固有判断基準） | infra | 03-14 | engineering_preferences自動注入+PJ3件整備+忍者参照ルール (cmd_927) |
| cmd_933 | 実装 — gstack家老ロール適用: wrapError/A-B-C Triage/Re-review Loop | infra | 03-14 | wrapError action行追加+A/B/C Triage+Re-review Loop (cmd_933) |
| cmd_932 | 実装 — gstack将軍ロール適用: Deferred Work Discipline+統合サマリ義務化 | infra | 03-14 | cmd_932 enforce deferred work schema |
| cmd_934 | 実装 — gstack忍者ロール適用: Named Invariants/Incremental Evidence/Shadow Paths/Read-only | infra | 03-14 | Named Invariants+発見即記録+Shadow Paths+Read-only Default (cmd_934) |
| cmd_935 | 整備 — gstack知識の索引層構築（context/gstack-knowledge.md） | infra | 03-14 | cmd_935 gstack-knowledge.md re-review PASS (8/4/49/3整合確認) |
| cmd_936 | 偵察+修正 — マスターCSVデータ汚染の調査と復旧 | auto-ops | 03-14 | 偵察+修正 — マスターCSVデータ汚染の調査と復旧 |
| cmd_937 | 整理 — 確定申告データの不要ファイル削除+ディレクトリ浄化 | auto-ops | 03-14 | cancelled |
| cmd_939 | 実装 — note売上CSVのGoogle Drive upload機能追加 | auto-ops | 03-14 | 実装 — note売上CSVのGoogle Drive upload機能追加 |
| cmd_938 | 修正+整理 — 確定申告データの出力先修正+Drive upload+確認後ローカル削除 | auto-ops | 03-14 | 修正+整理 — 確定申告データの出力先修正+Drive upload+確認後ローカル削除 |
| cmd_940 | | | auto-ops | 03-14 | — |
| cmd_942 | | | auto-ops | 03-14 | — |
| cmd_944 | | | auto-ops | 03-14 | — |
| cmd_945 | | | auto-ops | 03-14 | — |
| cmd_946 | | | auto-ops | 03-14 | — |
| cmd_943 | | | auto-ops | 03-14 | — |
| cmd_949 | | | auto-ops | 03-15 | — |
| cmd_948 | | | auto-ops | 03-15 | — |
| cmd_947 | | | auto-ops | 03-15 | — |
| cmd_950 | | | auto-ops | 03-15 | — |
| cmd_951 | | | auto-ops | 03-15 | — |
| cmd_952 | | | auto-ops | 03-15 | 経費マスターSpreadsheetの既存パターンを調査し、4 |
| cmd_955 | | | dm-signal | 03-15 | — |
| cmd_956 | | | dm-signal | 03-15 | — |
| cmd_957 | | | infra | 03-15 | — |
| cmd_959 | | | infra | 03-15 | — |
| cmd_960 | | | infra | 03-15 | — |
| cmd_961 | | | infra | 03-15 | — |
| cmd_962 | | | dm-signal | 03-15 | — |
| cmd_964 | | | dm-signal | 03-15 | — |
| cmd_963 | | | dm-signal | 03-15 | — |
| cmd_967 | | | dm-signal | 03-15 | trade-rule.md §7.3aの逆参照注記を強化。既 |
| cmd_968 | | | dm-signal | 03-15 | 金融ML知識辞書 ID予約済み5エントリの辞書化完了。 全フ |
| cmd_965 | | | dm-signal | 03-15 | Recharts/KaTeX dynamic import強 |
| cmd_966 | | | dm-signal | 03-16 | — |
| cmd_958 | | | infra | 03-16 | — |
| cmd_969 | | | dm-signal | 03-16 | — |
| cmd_971 | | | dm-signal | 03-16 | DM-Signal FE Biome導入+PostToolU |
| cmd_974 | | | infra | 03-16 | — |
| cmd_975 | | | dm-signal | 03-16 | — |
| cmd_970 | | | infra | 03-16 | — |
| cmd_972 | | | infra | 03-16 | — |
| cmd_973 | | | infra | 03-16 | — |
| cmd_976 | | | dm-signal | 03-16 | — |
| cmd_978 | | | infra | 03-16 | — |
| cmd_980 | | | infra | 03-16 | — |
| cmd_979 | | | infra | 03-16 | — |
| cmd_981 | 'p̄（p平均法）をFoFレイヤーのコーディングブロックとして忍法パイプラインに組み込み、 | dm-signal | 03-16 | — |
| cmd_982 | 'Render BEデプロイが2連続update_failed。 | dm-signal | 03-16 | — |
| cmd_983 | 'p̄の複合PK化・複数n_splits事前計算・パイプラインブロック・FE表示について、 | dm-signal | 03-16 | — |
| cmd_977 | 'p平均法を知識辞書に反映し、DM-Signal BEに実装し、FEに表示する。 | dm-signal | 03-16 | — |
| cmd_984 | Android音声入力（Gboard等のIME）の認識結果に対し、アプリ内で後処理辞書による 自動置換を適用し、将軍運用で頻出する専門用語の入力精度を向上させる。 | infra | 03-16 | AC3+AC4完了。VoiceDictionarySecti |
| cmd_985 | AndroidアプリからOpenAI APIのusage（使用量・コスト）を確認できるようにする。 既存のClaude usage表示と並列で、Claude/OpenAI切替で両方のAPIコストを把握可能にする。 | infra | 03-16 | — |
| cmd_990 | 'cancelled - replaced by cmd_991' | infra | 03-16 | — |
| cmd_988 | 'p̄バッチがサイレントに壊れた場合を検知するゲートを追加し、 | dm-signal | 03-16 | — |
| cmd_986 | 'Androidアプリにオフライン対応の開発アイデア帳を追加し、 | infra | 03-16 | — |
| cmd_987 | 'PBarSelectionBlockをパイプラインに追加し、複合PK化+複数n_splits事前計算を実装する。 | dm-signal | 03-16 | — |
| cmd_989 | 'ntfy_listener, inbox_watcher, ninja_monitor等のデーモンが落ちた場合に | infra | 03-16 | — |
| cmd_991 | 'ダッシュボードの教訓注入率セクションにタスク種別(impl/review/recon/scout)ごとの | infra | 03-16 | — |
| cmd_992 | 'gate_context_freshness.shのWARN/ALERTを解消する。 | infra | 03-16 | — |
| cmd_994 | 'Androidアプリ v6.0をビルドし、GitHubリリースを作成してAPKをアップロード、 | infra | 03-16 | — |
| cmd_993 | 'dashboard_auto_section.shのshellcheck SC2034違反（未使用変数CLEAR_RATE, LAST_GATE）を修正し、Stop Hook lintをパスさせる。' | infra | 03-16 | dashboard_auto_section.sh の sh |
| cmd_995 | 'cmd_985のRate Limit表示を殿の要件通りに修正する。 | infra | 03-16 | — |
| cmd_996 | 'cmd_985/986の実装で発生した横スクロールを修正し、 | infra | 03-16 | — |
| cmd_997 | '音声辞書のプリセットを複数の方法論で大幅に増やす。 | infra | 03-16 | — |
| cmd_998 | 'PBarSelectionBlockを四神×3パターン=12体の入力プールでtop_n=2実行し、 | dm-signal | 03-16 | PBarSelectionBlock実戦テスト完了。四神×3 |
| cmd_1000 | '既存ビルディングブロック群とPBarSelectionBlockの動作形式の整合性を確認し、 | dm-signal | 03-16 | — |
| cmd_999 | 'PBarSelectionBlockの月次リバランス・均等保有バックテストを実施し、 | dm-signal | 03-16 | — |
| cmd_1001 | 'cmd_1000偵察でビルディングブロック内に共通期間算出がないことを確認した。 | dm-signal | 03-16 | — |
| cmd_1003 | '殿が発見した2件の表示バグを調査・修正し、さらに全PF/FoFで | dm-signal | 03-16 | — |
| cmd_1002 | 'PBarSelectionBlockのp̄計算に任意のlookback_months（ルックバック期間）を | dm-signal | 03-16 | — |
| cmd_1005 | '(1) MIN_PERIOD_LENGTH=12はrichmanbtcの実装判断であり学術的根拠なし。 | dm-signal | 03-16 | — |
| cmd_1004 | 'FoFの計算開始日(fof_valid_start_date)が構成PFのシグナル開始日しか見ておらず、 | dm-signal | 03-16 | — |
| cmd_1007 | 'cmd_1005のPBar BTをtop_n=1で再実行し、毎月p̄最良1体に集中した場合の | dm-signal | 03-16 | — |
| cmd_1008 | '各ファミリー（青龍/朱雀/白虎/玄武）内の3モード（激攻/鉄壁/常勝）から | dm-signal | 03-16 | — |
| cmd_1010 | | | dm-signal | 03-16 | AC7横断サマリー完了。4サブタスク(Sub-A〜D)の結果 |
| cmd_1014 | Max Run-upと直交する2メトリクスをL1レベルで特定し、シン四神CPCVスクリーニング用トリプルEを確定する | dm-signal | 03-17 | シン四神Phase1: L1ファミリー別メトリクス相関分析を |
| cmd_1016 | trade-ruleパリティ修正前に生成された汚染GS結果データを特定し完全削除する | dm-signal | 03-17 | — |
| cmd_1015 | run_077正規計算でL1フルGS月次リターンを生成し、Max Run-upと直交する2メトリクスをL1レベルで特定する | dm-signal | 03-17 | — |
| cmd_1017 | analysis_runs/docs/に定義された既存GSパイプライン(5 Phase, 56,556候補/ファミリー)がシン四神のL1 CPCVスクリーニング基盤として使えるか、精査し所見を報告する | dm-signal | 03-17 | — |
| cmd_1018 | シン四神設計書(outputs/analysis/shin_shijin_design.md §3)に定義された191,796変種のL1パラメータ空間をGS実行し、全変種の月次リターン+8メトリクスを算出する。GSエンジンは本番PipelineEngineと計算完全一致であること | dm-signal | 03-17 | — |
| cmd_1019 | cmd_1018出力の191,796変種×8メトリクスを3手法(全期間/ローリング/DD条件付き)で相関分析し、トリプルE候補を殿に推薦する | dm-signal | 03-17 | — |
| cmd_1020 | Phase 2(トリプルE確定)と並行してCPCV+PBO完璧版エンジンを構築する。メトリクス名はパラメータ化し、Phase 2完了後に即実行可能な状態にする | dm-signal | 03-17 | — |
| cmd_1021 | シン四神パイプラインで使用する全スクリプト（GS/メトリクス/CPCV/忍法/四つ身）の所在・状態・依存関係を棚卸しし、再利用カタログとして恒久記録する | dm-signal | 03-17 | — |
| cmd_1022 | 分析+設計更新 — シン四神トリプルE: ファミリー独立化+C3符号修正+設計書反映 | dm-signal | 03-17 | FAIL。C3の正方向jump限定ロジック自体は scrip |
| cmd_1023 | 実装 — シン四神Phase3: CPCV+PBOスクリーニング（ファミリー独立×3メトリクス独立） | dm-signal | 03-17 | — |
| cmd_1024 | シン四神 Phase 4 — 脱相関K体選出 + 16ユニット構築 | dm-signal | 03-17 | — |
| cmd_1025 | Phase 4完了後の殿裁定（ファミリー別K選択+32体構成）を設計書に正確に記録し、Phase 5以降の前提を確定させる | dm-signal | 03-17 | — |
| cmd_1026 | シン忍法GS(Phase 5)の前提として、四つ目GSスクリプトを作成して6忍法体制を完成させ、全スクリプトの命名を統一し、カタログドキュメントに記録する | dm-signal | 03-17 | 四つ目(yotsume) GSスクリプト新規作成 + 6忍法 |
| cmd_1027 | 32体ユニバースでの7忍法GS実行時間を実測し、チャンク分割並列実行の設計パラメータを確定する | dm-signal | 03-17 | — |
| cmd_1028 | シン忍法知見の教訓登録+設計書同期確認 | dm-signal | 03-17 | cmd_1028 impl成果物の全検証PASS。L357- |
| cmd_1029 | cmd_1027ベンチマークは本番高速化パスを使わず計測していた。本番と同じ実行方式で正確なms/patを取得し、全量見積もりを再算出する | dm-signal | 03-17 | — |
| cmd_1030 | cmd_1029でgrouped実行23.19h(直列)まで短縮済み。さらに10倍（直列2-3h、8並列20-30min）を目指し、全高速化手段を調査する | dm-signal | 03-17 | — |
| cmd_1031 | cmd_1030偵察結果の高速化#1(Grid dedup)+#2(PPE全忍法)+#5(worker 4→6)を実装。23h→2.8hを目指す。本番パリティ完全一致が絶対条件。 | dm-signal | 03-17 | — |
| cmd_1032 | cmd_1031のGrid dedupを差し戻す。本番は日次解像度でシグナル計算するため10D/15D/20D/1Mは全て異なる値を生む。月次GS内のbefore/after比較は本番パリティではない。PPE導入部分は残す。 | dm-signal | 03-17 | — |
| cmd_1033 | kawarimiのPPE効率が1.09x（他忍法2.5-3.75x）である原因を特定し、改善可能か判定する | dm-signal | 03-17 | — |
| cmd_1034 | kasoku GS(12.6Mパターン, PPE6で6.6h)のさらなる高速化余地を6観点から調査し、次の実装cmdの設計根拠を確立する | dm-signal | 03-17 | — |
| cmd_1035 | Phase 5(シン忍法GS 19.2Mパターン)実行前に、cmd_1034実証済み高速化をkasokuに組込み、他忍法にも横展開し、全7忍法スクリプトの本番パリティを再検証する | dm-signal | 03-17 | yotsume+bunshinベンチマーク計測完了。 yot |
| cmd_1037 | cmd_1035で各忍法に適用した高速化手法を横断分析し、忍法間の知見転用でさらなる高速化余地を定量的に特定する | dm-signal | 03-18 | — |
| cmd_1036 | 全忍法のGSベンチマークを1本の共通スクリプトで統一し、計測方法のブレ・重複実装・ミスを排除する | dm-signal | 03-18 | — |
| cmd_1039 | ninja_monitorの/clear判定を三段階化し、作業中(acknowledged/in_progress)の忍者を/clearしない | infra | 03-18 | — |
| cmd_1038 | cmd_1037偵察で実証済みの3高速化手法+tiebreakバグ修正を並列実装し、19.2M GS実行時間を20-30分から10-15分圏内に短縮する | dm-signal | 03-18 | — |
| cmd_1040 | cmd_1039の実装が殿の三段階仕様と不一致。正しい三段階（Stage 1: YAML確認→Stage 2: 再確認→Stage 3: /clear）に再実装 | infra | 03-18 | — |
| cmd_1041 | hooks・ninja_monitor・CI/テスト・通信基盤のバグ・エラーを網羅的に洗い出す | infra | 03-18 | — |
| cmd_1042 | GS高速化の1改良1ベンチ規律を強制するスキル+ベンチスクリプト拡張を整備する | dm-signal | 03-18 | — |
| cmd_1044 | Read追跡hook — Write/Edit前の未Readファイルを自動ブロック | infra | 03-18 | Read追跡hook作成完了。全3AC達成。 |
| cmd_1011 | 緊急修正 — DM-Signal本番 304 Not Modified キャッシュ不整合バグ | dm-signal | 03-18 | — |
| cmd_1012 | 分析 — 忍法二段重ね(2段パイプライン)BT | dm-signal | 03-18 | — |
| cmd_1013 | 分析 — CPCV+PBO過適合検証（既存忍法+二段重ね全チャンピオン） | dm-signal | 03-18 | — |
| cmd_1043 | インフラ全修正 — cmd_1041偵察で検出した全問題を殲滅（CRITICAL3+HIGH4+MEDIUM5+LOW3+EH群） | infra | 03-18 | AC8統合レビュー完了。5観点全PASS。19ファイル(+6 |
| cmd_1045 | 修正 — lessons_usefulゲート穴塞ぎ（string_list/dict_no_usefulすり抜け229件） | infra | 03-18 | — |
| cmd_1046 | 修正 — CI RED解消（pushトリガー不発+テスト失敗修正） | infra | 03-18 | CI RED修正完了。Unit Tests/Shell Li |
| cmd_1047 | 全activeプロジェクト(3PJ)のgit状態をクリーンにし、IDEの差分表示を正常化する | infra | 03-18 | DM-Signal gitignore整理+成果物commi |
| cmd_1048 | 高速化 — kasoku picks vectorize（T3: ctx build 84.8%ボトルネック直撃） | dm-signal | 03-18 | — |
| cmd_1049 | 修正 — ninja_monitor STALE-TASK判定にデプロイ直後グレースピリオド追加 | infra | 03-18 | — |
| cmd_1051 | oikaze/kawarimi/yotsumeにT3(picks vectorize)を横展開し、19.2M GS全体を62min→20min以下にする | dm-signal | 03-18 | — |
| cmd_1050 | 高速化 — nukimi picks vectorize（T3横展開: 残り最大ボトルネック2.3h） | dm-signal | 03-18 | — |
| cmd_1054 | cmd吸収時に旧cmdで稼働中の忍者を即座に/clearし、無駄な作業時間を防ぐ | infra | 03-18 | cmd_absorb.shにabort_deployed_n |
| cmd_1053 | ac_versionをACテキスト内容のハッシュに変更し、AC内容差替えを確実に検知する | infra | 03-18 | — |
| cmd_1052 | oikaze/kawarimi/yotsumeにT3を横展開し、各忍法のGS出力が本番(Render)と完全一致することを検証する | dm-signal | 03-18 | — |
| cmd_1055 | Playwrightスクレイパーのheadlessモード安定化とUI変更耐性の強化 | google-classroom | 03-18 | scrape_classroom.pyの脆弱なCSSセレクタ |
| cmd_1060 | Phase 3-4完了済みなのにドキュメントが未更新。32体ユニバース構成の正式定義が設計書にあるがcontext索引に反映されていない。コードとドキュメントの乖離を修復する | dm-signal | 03-18 | context/dm-signal-research.md |
| cmd_1061 | run_077_*.pyのPORTFOLIO_MAP/CANDIDATE_SETハードコードを外部YAML設定化し、シン四神32体・将来の新構成PFに差し替え可能にする | dm-signal | 03-18 | — |
| cmd_1062 | T3(picks vectorize)で全量42min→並列12minに到達。さらなる高速化余地を定量的に把握し、Phase 5実行前に追加最適化の要否を判断する材料を得る | dm-signal | 03-19 | — |
| cmd_1064 | 4忍法のmomentum_cube計算をpandas pct_change→numpy slice一括に置換し、ctx_build高速化+本番パリティ完全一致を確認する | dm-signal | 03-19 | — |
| cmd_1065 | queue/tasks/*.yamlへのWrite/Editをhookで無条件denyし、deploy_task.sh経由のみでタスクYAML生成を強制する | infra | 03-19 | — |
| cmd_1058 | 日次cronスクレイパー(第一段)のセレクタ劣化をメトリクスで検知し、classroom側スキル(第二段)でaria_snapshot+refによるセレクタ診断・修繕案提示を可能にする二段構えの自己回復機構を構築する | google-classroom | 03-19 | — |
| cmd_1066 | レビュー報告テンプレートにverdict/self_gate_checkを追加し、ゲートBLOCKによる家老の手戻りを解消する | infra | 03-19 | — |
| cmd_1068 | 12体レガシー四神で誤実行されたcmd_1057のGS出力18ファイルを削除し、汚染データの後続混入を防ぐ | dm-signal | 03-19 | — |
| cmd_1067 | queue/reports/*.yamlへのWrite/Editをhookで無条件denyし、report_field_set.sh経由のみで報告YAML更新を強制する | infra | 03-19 | — |
| cmd_1072 | 家老が/clear後もdeploy_task.sh・report_field_set.shの使い方を知っている状態にし、hookブロック→再学習の無駄サイクルを根絶する | infra | 03-19 | — |
| cmd_1071 | 'report_merge.shがtask YAMLのtitleフィールド（存在しない）で偵察判定しているバグを修正し、task_type: reconで判定するようにする' | infra | 03-19 | — |
| cmd_1070 | 忍者が/clear後もreport_field_set.shの使い方を知っている状態にし、hookブロック→再学習の無駄サイクルを根絶する | infra | 03-19 | — |
| cmd_1069 | run_077_*.pyがuniverse設定をどこから読み、なぜ32体ではなく12体で実行されたかを特定する | dm-signal | 03-19 | — |
| cmd_1074 | report_field_set.shがpipe入力のYAMLリスト/dictを文字列として格納するバグを修正し、構造化データを正しく保持する | infra | 03-19 | — |
| cmd_1073 | projects/dm-signal/lessons.yaml の全409件を精査し、本番バックエンド挙動に関する事実（PI候補）を網羅的に抽出する | dm-signal | 03-19 | — |
| cmd_1057 | 32体シン四神ユニバースで7忍法GS全量実行し、チャンピオンパラメータを決定する | dm-signal | 03-19 | — |
| cmd_1241 | startup gateにGate 10(idle自走トリガー)を追加し、パイプライン空+全忍者idle時に将軍が自動的にidle時自己分析手順に入る仕組みを作る | infra | 03-22 | — |
| cmd_1242 | CI赤(run 23387382972)を修正し、全CIジョブを緑に戻す | infra | 03-22 | — |
| cmd_1244 | commit_missing(変更ありcommitなし)をcmd_complete_gate.shでBLOCK化し、忍者のcommit漏れを構造的に防止する | infra | 03-22 | — |
| cmd_1243 | L0-M_XLU holding_signal不一致の根本解決。^VIX/DTB3 cache汚染修正 | dm-signal | 03-22 | 64/65 PASS。PI-010追加 |
| cmd_1245 | シン青龍-鉄壁 2024-11パリティ最後の1件。65/65 PASS目標 | dm-signal | 03-22 | — |
| cmd_1246 | gate_report_format.shにverdict二値バリデーション追加。CONDITIONAL_PASS早期検出 | infra | 03-22 | PASS。テスト5件追加、退行なし |
| cmd_1247 | 偵察 — 33体本番DB登録の前提条件チェック(runbook突合+GAP検出) | dm-signal | 03-22 | — |
| cmd_1248 | gate_report_format.sh: lessons_useful/binary_checks形式バリデーション強化 | infra | 03-22 | — |
| cmd_1249 | cmd_1247偵察で発見されたFoF 21体のCRITICAL GAP 2件(component_portfolios旧v1構成+selection params全空)を解消し、v2正本CSVと一致させる | dm-signal | 03-22 | — |
| cmd_1252 | — | infra | 03-22 | — |
| cmd_1257 | シン四神・シン忍法登録ランブックをv2(33体)に更新し、本番登録cmdの前提条件を整える | dm-signal | 03-22 | — |
| cmd_1258 | dashboard CI状態の自動反映 + 陳腐化防止 | infra | 03-22 | — |
| cmd_1259 | dm-signal.yaml pipeline flow + registration陳腐化ステータス更新 | dm-signal | 03-22 | — |
| cmd_1260 | 軍師S6提案実装 — lessons_useful/binary_checksプリフィル + report構造強制 | infra | 03-22 | — |
| cmd_1261 | 軍師提案パイプライン構造化 — YAMLコメント→構造化フィールド+自動サーフェシング | infra | 03-22 | — |
| cmd_1262 | ninja_monitor.sh AUTO-DONE重複書込みバグ修正 — idle通知嵐の根絶 | infra | 03-22 | — |
| cmd_1264 | inbox_write.sh gate発火100%化 — サイレントスキップ→BLOCK | infra | 03-22 | — |
| cmd_1266 | 偵察 — FoF selection_pipeline動作乖離の根本原因調査 | dm-signal | 03-22 | — |
| cmd_1263 | ninja_monitorにcommit未完了チェック追加 — commit_missing構造的根絶 | infra | 03-23 | — |
| cmd_1268 | CI RED修正 — Unit Tests 9件失敗(ntfy_ack mock不備+auto_deploy_done不整合) | infra | 03-23 | — |
| cmd_1269 | FoFパリティ検証 バッチ1(7体) — cmd_1251スクリプト展開 | dm-signal | 03-23 | — |
| cmd_1270 | FoFパリティ検証 バッチ2(7体) — 第2陣並列実行 | dm-signal | 03-23 | — |
| cmd_1271 | FoFパリティ検証 バッチ3(7体) — 第3陣並列実行 | dm-signal | 03-23 | — |
| cmd_1272 | L1シン四神12体 登録スクリプト構築+dry-run検証 | dm-signal | 03-23 | — |
| cmd_1273 | 本番登録環境PI-006検証 — ランブックv2全Step実行可能性の事前確認 | dm-signal | 03-23 | — |
| cmd_1265 | report_field_set.sh強制hook — 忍者の直接Edit禁止で源流から構造不正防止 | infra | 03-23 | — |
| cmd_1275 | GS混乱候補スクリプト7本削除 — 忍法スクリプト誤用防止 | dm-signal | 03-23 | — |
| cmd_1277 | deploy_task.sh配備高速化 — preflight_gate_artifacts()からarchive_completed.sh呼出を除去し、配備時間を50秒→5秒に短縮する | infra | 03-23 | — |
| cmd_1279 | gate発火ログ計測基盤の構築 — gate_report_format.shの発火・結果をログに記録し、gate効果の定量的計測を可能にする | infra | 03-23 | — |
| cmd_1280 | lessons.yaml 3ファイルのVercel化 — 索引+アーカイブ分離で500行以下に圧縮し、読込エージェントのCTX浪費を構造的に解消する | infra | 03-23 | — |
| cmd_1282 | 運用ファイル3件のVercel化 — context/cmd-chronicle.md + context/infrastructure.md + logs/gunshi_review_log.yaml を500行以下に圧縮する | infra | 03-23 | — |
| cmd_1281 | 核心知識ファイル3件のVercel化 — projects/dm-signal.yaml + instructions/shogun.md + instructions/karo.md を500行以下に圧縮する | infra | 03-23 | dm-signal.yaml 307行+shogun.md 275行+karo.md 367行。二重配備(小太郎+疾風)発生もファイル破損なし |
| cmd_1283 | lesson_update_score.shのCACHE_FILE→lessons_archive.yaml切替 — Vercel化索引の再膨張防止 | infra | 03-23 | — |
| cmd_1284 | dashboard🚨要対応セクション清掃 + report_field_set.sh BLOCK昇格 | infra | 03-23 | — |
| cmd_1285 | 家老用スタートアップゲート作成 — deepdive必読の自動化×強制 | infra | 03-23 | — |
| cmd_1286 | GP-014 commit層自動防御 — report完了前のgit uncommittedチェックgate | infra | 03-23 | — |
| cmd_1290 | insightsキュー自動アーカイブ — doneエントリの残存防止 | infra | 03-23 | — |
| cmd_1291 | 報告YAMLアーカイブ時期修正 — 家老レビュー完了前のアーカイブ防止 | infra | 03-23 | — |
| cmd_1292 | ninja_monitor report存在チェック — report未作成での/clear防止 | infra | 03-23 | — |
| cmd_1293 | 忍者報告テンプレート導線修復 — format workaround源流根絶(GP-017) | infra | 03-23 | — |
| cmd_1294 | PreToolUse DENY実装 — Write/Editでの報告YAML直接作成を阻止(GP-003完遂) | infra | 03-23 | — |
| cmd_1301 | startup gate bash算術エラー修正 — grep -c || echo anti-pattern根絶 | infra | 03-23 | — |
| cmd_1302 | cmd_complete_gate.sh archive実行タイミング修正 — GATE外完了の根絶 | infra | 03-23 | — |
| cmd_1303 | ninja_monitor uncommittedチェック scope修正 — 運用ファイル除外 | infra | 03-23 | — |
| cmd_1304 | 削除済みスクリプト参照27ファイルのクリーンアップ | infra | 03-23 | — |
| cmd_1305 | lesson_update_score.sh書込先修正 — Vercel化後のarchive参照切替 | infra | 03-23 | cmd_1283で既に対応済み。lesson_update_ |
| cmd_1306 | test_result_guard.sh偽陽性修正 — last_assistant_messageのSKIP誤検知除去 | infra | 03-23 | — |
| cmd_1307 | GP-021 ninja-adaptive failure injection — 忍者別過去失敗パターン自動注入 | infra | 03-23 | — |
| cmd_1308 | workaround率自動計測gate — cmd_complete_gate統合でpost-GP効果を自動追跡 | infra | 03-23 | — |
| cmd_1309 | queue/tasks/subtask_*.yaml 47件をarchive移動 — 旧アーキテクチャ残骸清掃 | infra | 03-23 | — |
| cmd_1310 | CI RED修正 — test_sync_lessons_injection_count_sync.bats L77 失敗 | infra | 03-23 | — |
| cmd_1311 | GP-003正規表現バグ修正 — report YAML hookが全忍者で未発火 | infra | 03-23 | — |
| cmd_1289 | GP-011 忍者別workaround率の自動計測・startup gate表示 | infra | 03-23 | — |
| cmd_1322 | GP-032 target_path存在検査WARN注入 | infra | 03-23 | — |
| cmd_1323 | STALL再配備時の旧報告テンプレート自動cleanup | infra | 03-23 | — |
| cmd_1324 | fix: lesson_impact.tsv タブ文字エスケープバグ修正+既存データ復旧 | infra | 03-23 | — |
| cmd_1326 | feat: cmd_complete_gate.sh GATE CLEAR後処理のpost-write verify横展開 | infra | 03-23 | — |
| cmd_1327 | fix: CI RED修復 — E2Eテスト2ファイルを現行編成に適合 | infra | 03-23 | — |
| cmd_1329 | fix: insights.yaml棚卸し — pending 25件の分類・重複削除・resolved更新 | infra | 03-23 | — |
| cmd_1328 | recon: GP-026実装設計 — report_yaml_missing BLOCK自動待機メカニズム | infra | 03-23 | — |
| cmd_1330 | feat: GP-027実装 — commit漏れ検出WARN(gate check前) | infra | 03-23 | — |
| cmd_1331 | fix: CI Unit Test FAIL — test_text_utils.bats bash -lc を bash -c に修正 | infra | 03-23 | — |
| cmd_1334 | feat: GP-029実装 — insights自動起票品質改善(dedup+ID一意化) | infra | 03-23 | — |
| cmd_1332 | feat: GP-026実装(B案) — CLEAR済みcmd再check防止+全non-done WAIT | infra | 03-23 | — |
| cmd_1333 | feat: GP-028実装 — 教訓注入projectフィールドフォールバック | infra | 03-23 | — |
| cmd_1335 | feat: GP-023実装 — 軍師レビュー時cross-ninja WA率チェック | infra | 03-23 | — |
| cmd_1336 | CLEAR率65→85%向上、WA率53→27%半減。autofix→format check順序でrace condition根絶 | infra | 03-23 | — |
| cmd_1337 | ダッシュボード更新の意志依存を排除。イベント駆動で即時更新し将軍の判断速度を向上 | infra | 03-23 | — |
| cmd_1338 | GATE時にautofixを再実行しrace condition根絶。verdict/no_lesson_reason自動補完で61 FAIL根絶。CLEAR率65→85%。家老workaround構造的根絶 | infra | 03-23 | — |
| cmd_1339 | 将軍のcmd重複起票を構造的に防止。今日のcmd_1338重複事故(家老cmd_1336と同内容)のwhy chain分析から特定した自動化ターゲット | infra | 03-23 | — |
| cmd_1340 | 偵察教訓注入率0%(cmd_513全スキップ)を解消。偵察固有教訓が偵察タスクに伝わらず改善ループが断絶している。偵察は全cmdの前段であり品質の起点 | infra | 03-23 | — |
| cmd_1341 | LLMには時系列の概念がない(殿指摘)。累積値は安心を与えるが因果を隠す。直近値は変化のシグナルを示す。recon注入率36%(実質0%)の誤認を構造的に防止 | infra | 03-23 | — |
| cmd_1342 | Step 2 Phase B — 既存追い風FoFパリティ検証（MomentumFilter） | dm-signal | 03-23 | — |
| cmd_1343 | Step 2 Phase C — 既存抜き身FoFパリティ検証（SingleViewMomentumFilter） | dm-signal | 03-23 | — |
| cmd_1344 | Step 2 Phase D — 既存変わり身FoFパリティ検証（TrendReversalFilter） | dm-signal | 03-23 | — |
| cmd_1346 | Step 2 Phase E2 — 既存加速D FoFパリティ検証（MomentumAccelerationFilter diff） | dm-signal | 03-23 | — |
| cmd_1345 | Step 2 Phase E1 — 既存加速R FoFパリティ検証（MomentumAccelerationFilter ratio） | dm-signal | 03-23 | — |
| cmd_1347 | Step 2 Phase F — 既存FoFパリティ検証（MultiViewMomentumFilter 5体） | dm-signal | 03-23 | — |
| cmd_1350 | Step 1やり直し — numpy快速パスの本番パリティ検証 | dm-signal | 03-23 | — |
| cmd_1349 | Step 3 — シン四神v2 12体作成（shin_shijin_l1_gs.py）【中止】 | dm-signal | 03-23 | — |
| cmd_1348 | Step 2 Phase G — 既存ネステッドFoFパリティ検証（7体） | dm-signal | 03-23 | — |
| cmd_1351 | Step 1補強 — 本番standard PF全65体のnumpy快速パスパリティ検証 | dm-signal | 03-23 | — |
| cmd_1352 | 全standard PF numpy快速パス完全パリティ（hs+ret両方）+ L0-M_XLU原因特定 | dm-signal | 03-24 | — |
| cmd_1353 | numpy快速パス 53/53完全一致達成 — ^VIX grid汚染修正+hs順序一致 | dm-signal | 03-24 | — |
