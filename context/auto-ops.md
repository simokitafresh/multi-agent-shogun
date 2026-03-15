# Auto-Ops Context
<!-- last_updated: 2026-03-15 lesson-sort L024-L055振り分け -->

## 概要

CDP(Chrome DevTools Protocol) + Google Workspace CLI によるデスクトップ・ブラウザ自動化基盤。

- repo: https://github.com/simokitafresh/auto-ops (private)
- path: `/mnt/c/Python_app/auto-ops`

## 技術スタック

### CDP (Chrome DevTools Protocol)
- WSL2 → PowerShell → Edge/Chrome CDP(port 9222)でDOM直接操作
- Computer Useの2倍速・裏動作・トークン安
- B64エンコードで4重クォート回避
- 参考: https://zenn.dev/shio_shoppaize/articles/wsl2-edge-cdp-automation

### Google Workspace CLI (gws)
- `npm i -g @googleworkspace/cli`
- Gmail, Drive, Calendar, Sheets, Docs, Chat, Admin対応
- MCP標準搭載 + 40以上のAgent Skills
- Rust製、Apache 2.0

## 設計方針

- CDP: ブラウザでしかできない操作（ログイン・DOM操作・PDF取得）
- gws: Google API操作（メール検索・Drive保存・改名）
- 外部ライブラリ依存最小（標準ライブラリ優先）
- L015: PEP668環境でのPython依存追加は_vendor注入が安全（cmd_909）
- L002: CDP本番検証ではfrontend/backend hostを分離。dm-signal.onrender.comは404（cmd_746）
- L003: CDP本番viewer認証: input[type=password]のdisabled状態待機が必要（cmd_746）
- L004: ACが「実行して実証」を要求する場合、コード確認やpy_compile PASSだけで完了判定するな（cmd_815）
- L024: fail-closeのwarn/skipを上位オーケストレーターで成功扱いするな（cmd_919）
- L057: Chrome headless(--print-to-pdf等)は必ず--user-data-dirで隔離プロファイルを指定せよ。省略時はデフォルトプロファイルが使われ殿の全アカウントがログアウトされる（cmd_954事故）

## ユースケース候補

- Gmail領収書メール → リンク先ログイン → PDF取得 → Drive保存+改名
- ブラウザ体感速度計測（DM-signal等のフロントエンド検証）
- Google Workspace定型業務自動化
- 個人事業経費管理（PDF命名+Drive整理+CSV管理）→ `projects/auto-ops.yaml` §個人事業

## 個人事業経費管理

- **マスターCSV**: 個人事業_{年}.csv（15列）。Drive「2026確定申告 個人事業」直下。→ `projects/auto-ops.yaml` §マスターCSVフォーマット
- **PDF命名**: `{対象年月}_{発行元}_{種別}_{金額}_{元ファイル名}.pdf`。→ `projects/auto-ops.yaml` §経費PDF命名ルール
- **証票突合ルール(殿厳命)**: 日付一致+金額一致(ドル円10%閾値)+1対1対応必須。→ `projects/auto-ops.yaml` §receipt_matching_rules
- **証票有効性**: Receipt/Invoiceのみ有効。金額なしemailは証票無効。→ `projects/auto-ops.yaml` §receipt_validity
- **フォルダ名ステータス**: `[OK]_`/`[NG]_`/`[--]_`プレフィックス。ASCII限定。→ `projects/auto-ops.yaml` §folder_status_naming
- **Spreadsheet記載**: 証票あり/なし+具体的入手方法。曖昧表現禁止。→ `projects/auto-ops.yaml` §spreadsheet_truth_rules
- **証票取得原則(殿厳命)**: 正確性>網羅性。Gmail不十分なら個別パイプライン構築。汚染データは即排除。ゼロの方が嘘より100倍マシ。→ `projects/auto-ops.yaml` §receipt_acquisition_principle
- **報告品質**: 根拠なき所見はFAIL差し戻し。→ `projects/auto-ops.yaml` §report_quality
- **note領収書取得方式(PD-003解決)**: 手動DL + 自動リネーム/アップロード。note利用規約でスクレイピング禁止のためCDP自動取得は見送り。将来再検討可(L010)
- **MFA方式(PD-003)**: TOTP自動化(pyotp)で確定。email_otp完全置換(L014/cmd_909)
- **MFグループ(PD-004)**: 殿が個人事業専用グループを既に設定済み。事前作成不要
- **CSV DL方式(PD-005)**: 定期cronは設けず、殿が任意のタイミングで手動指示する方式
- **Drive命名違反修正(PD-006)**: 258件は段階修正方式で対処(MECE分割×4名+再チェック4名)。cmd_941で実施
- L009: Drive上の生CSVはdownload/exportよりget alt=mediaが安定（cmd_894）
- L010: note.com領収書は直接PDFダウンロード不可+利用規約でスクレイピング禁止（cmd_895）
- L011: MF CSV DL URLは直リンク方式（/cf/csv?from=...）で認証Cookieがあれば直接取得可能（cmd_897）
- L014: MF TOTP設定でemail_otp完全置換 — 認証系サイト自動化はTOTP第一手段（cmd_907）
- L016: MF IDログインsnapshot textbox名はlabelではなくplaceholder/field名（cmd_909）
- L018: MoneyForward login snapshotのtextbox名はlabelではなくplaceholder/field名になることがある（cmd_909）
- L019: 複数候補の証票PDFは先頭採用せず空文字でfail-closeせよ（cmd_914）
- L020: PDF抽出結果にunknownが残る場合はrename/uploadを継続せずfail-closeせよ（cmd_915）
- L021: note.comのuser_verificationはURLを変えず404コンテンツを表示する。フォーム存在チェック必要（cmd_912）
- L022: note.com売上管理ページのDOMスコープマッチは行レベルで行え（cmd_912）
- L025: MF loginは既ログインredirectをフォーム待機前にshort-circuitせよ（cmd_922）
- L029+L031: master_csv.drive_idはフォルダIDであり実CSVファイルIDとは別物（cmd_941）
- L032: Stripe系email-only PDFは証票と見なす前に本文確認が必要（cmd_942）
- L033: note証票PDFはファイル名を信用せず本文の注文ID・金額・対象月をspot checkすべし（cmd_942）
- L034: SpreadsheetとCSVの行番号不一致（cmd_943_B）
- L035: GitHub Gmail再取得は円額検索だけでは取りこぼす（cmd_943_E）
- L036: CSVの証票フォルダ名とDrive実フォルダ名の不一致（cmd_943_R）
- L037: PayPal系email PDFが本文欠落でもGmail原文HTMLは有効証票情報を保持（cmd_943_D）
- L038: PayPal経由決済はGmail検索(from:paypal.com+サービス名)で正式領収書メール取得可能（cmd_943_J）
- L039: note振込手数料の全12ファイルが同一取引IDの1月分コピーだった（cmd_943_S）
- L040: MF年次CSV直リンクはHTML応答になる場合あり。月次直リンクが安定（cmd_944）
- L041: 非Stripe系独自メールreceipt取得はGmail API→HTML抽出→Chrome headless --print-to-pdfが有効（cmd_943）
- L042: note購入証票はGmailのpurchase-complete mailだけを候補にし、order_dateとMF日付のexact matchまで通らなければ不採用に倒す（cmd_943）
- L043: Spreadsheet証票更新対象はtaskのrow/column指定を信用せず、IDとヘッダでlive特定すべし（hayate）
- L051: Buffer payment mailのStripe invoice URLは失効し得る。email header付きPDF生成パスを正本運用として既定化すべし（cmd_943）
- L052+L053: cmd_950系のSpreadsheet更新対象は経費マスターではなく取引台帳『個人事業_2025』（cmd_950）
- L054: Spreadsheet部分未同期はローカルCSV/Drive CSVが正でも残り得る。対象ID全件のreadback比較が必須（cmd_951）
- L056: 証票取得経路の分類はPDF名からの推定で決めるな。Gmail検索を実際に実行してから判断せよ（cmd_954）

## gws CLI

- L023: gws 0.6.3ではSheets取得に+read/--spreadsheetヘルパー構文を使う（cmd_916）
- L027: gws 0.6.3 Sheets取得はgws sheets spreadsheets values get --params形式が正しい。L023の+read構文は旧式
- L028: gws drive files getでalt=mediaは--params '{"fileId":"...","alt":"media"}'構文で成功（cmd_941）
- L030: gws drive files rename/deleteのバッチ処理パターン（cmd_941）
- L055: gwsではDrive move専用サブコマンドがなく、files updateのaddParents/removeParentsで移動する（cmd_951）

## CDP計測索引

- L005: WS URLキャッシュとバッチ送信は必須。毎回resolve→PS多重起動で5分タイムアウト→114msに改善（cmd_817）
- L274: CDP reload 計測の ready 条件は static selector 固定ではなく viewer 実DOM に合わせて見直せ（cmd_852）
- L275: CDP本番計測は共有ブラウザプロファイルを避けisolated portで実行せよ（cmd_853）
- L276: ブラウザprocess有無だけでCDP起動済みと判断するな（cmd_857）
- L007: 共有CDPポートではlaunch_browserの修正効果を実証できない場合がある（cmd_885）
- L008: Chrome CDP daemonはremote-allow-origins未設定だとWebSocket handshake 403で失敗する（cmd_885）
- L012: 共有9222のheadless Chromeは対botログイン調査で403化するため隔離ポートの通常Chromeへ退避する（cmd_897）
- L013: f-string内のJS空オブジェクト{}はSyntaxError（cmd_901）
- L026: note CDP page WebSocketは長時間月次ループで途中失効する。年次バッチでは月ごとfresh tab再取得のfailoverが必要（cmd_920）
- L044+L047: Chrome 145 CDP起動阻害: User Dataパスのスペース→ジャンクションリンクで回避（cmd_949）
- L045: note.com CDPログイン手順: .env.noteクレデンシャル+DOM操作+user_verification突破（cmd_949）
- L046: isolated Chrome profile(別ポート)はCDP接続には成功するが既存セッションのCookieを継承しない（cmd_949）
- L048: Edge CDPでも殿のデフォルトプロファイルがnote.comにログイン未済なら同結果（cmd_949）
- L049: note.com売上管理ページはuser_verificationが必要。パスワード再入力をCDPで突破可能（cmd_949）
- L050: Chrome(9222)ログイン済み前提のnote taskでも9222が通常Chromeへ未結線ならpreflightがclean temp profileを起動しstop_forへ直行する（cmd_947）
- 計測CLI本体は `auto-ops/workflows/perf_measure.py`、CDP transport は `auto-ops/cdp/cdp_helper.py`。task文面にある `cdp/perf_measure.py` は現行repoには存在しない。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §1
- CDPポートは `9222` に統一（cmd_885）。`launch_browser()` は `--remote-debugging-port=9222`, `--remote-debugging-address=0.0.0.0` を付ける。Daemon mode(cdp_server.py)も `--cdp-port=9222` が既定。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §2
- 計測順序は `preflight_cdp_flow()` に統合済み: プロセス確認 → 未起動時自動起動 → CDP接続確認 → `perf_measure.py` 本計測。cmd_810/811/815 の着地点。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §3, §5
- `9224` は現行 `auto-ops` repo・git履歴・近傍workspace検索で実装痕跡なし。知識としては「現行未確認ポート」と扱う。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §4

## 教訓索引（自動追記）

- （現在0件。L001-L003は振り分け済 → §設計方針、L004 → §設計方針、L005 → §CDP計測索引）
<!-- last_synced_lesson: L057 -->
- （現在0件。L006はL004と重複→統合済み）
- （L007-L017は振り分け済 → §CDP計測索引(L007/008/012/013), §個人事業経費管理(L009-011/014/016), §設計方針(L015)。L017はL015と重複→統合）
- （L018-L022は振り分け済 → §個人事業経費管理(L018-L022)、L023 → §gws CLI）
- （L024-L055は振り分け済 → §設計方針(L024), §個人事業経費管理(L025/L029+L031統合/L032-L043/L051/L052+L053統合/L054), §gws CLI(L027/L028/L030/L055), §CDP計測索引(L026/L044+L047統合/L045/L046/L048-L050)）
- （L056は振り分け済 → §個人事業経費管理）
