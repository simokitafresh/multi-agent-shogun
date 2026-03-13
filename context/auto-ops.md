# Auto-Ops Context
<!-- last_updated: 2026-03-12 -->

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
- L002: CDP本番検証ではfrontend/backend hostを分離。dm-signal.onrender.comは404（cmd_746）
- L003: CDP本番viewer認証: input[type=password]のdisabled状態待機が必要（cmd_746）
- L004: ACが「実行して実証」を要求する場合、コード確認やpy_compile PASSだけで完了判定するな（cmd_815）

## ユースケース候補

- Gmail領収書メール → リンク先ログイン → PDF取得 → Drive保存+改名
- ブラウザ体感速度計測（DM-signal等のフロントエンド検証）
- Google Workspace定型業務自動化
- 個人事業経費管理（PDF命名+Drive整理+CSV管理）→ `projects/auto-ops.yaml` §個人事業

## 個人事業経費管理

- **マスターCSV**: 個人事業_{年}.csv（15列）。Drive「2026確定申告 個人事業」直下。→ `projects/auto-ops.yaml` §マスターCSVフォーマット
- **PDF命名**: `{対象年月}_{発行元}_{種別}_{金額}_{元ファイル名}.pdf`。→ `projects/auto-ops.yaml` §経費PDF命名ルール
- **note領収書取得方式(PD-003解決)**: 手動DL + 自動リネーム/アップロード。note利用規約でスクレイピング禁止のためCDP自動取得は見送り。将来再検討可(L010)

## CDP計測索引

- L005: WS URLキャッシュとバッチ送信は必須。毎回resolve→PS多重起動で5分タイムアウト→114msに改善（cmd_817）
- L274: CDP reload 計測の ready 条件は static selector 固定ではなく viewer 実DOM に合わせて見直せ（cmd_852）
- L275: CDP本番計測は共有ブラウザプロファイルを避けisolated portで実行せよ（cmd_853）
- L276: ブラウザprocess有無だけでCDP起動済みと判断するな（cmd_857）
- 計測CLI本体は `auto-ops/workflows/perf_measure.py`、CDP transport は `auto-ops/cdp/cdp_helper.py`。task文面にある `cdp/perf_measure.py` は現行repoには存在しない。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §1
- CDPポートは `9222` に統一（cmd_885）。`launch_browser()` は `--remote-debugging-port=9222`, `--remote-debugging-address=0.0.0.0` を付ける。Daemon mode(cdp_server.py)も `--cdp-port=9222` が既定。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §2
- 計測順序は `preflight_cdp_flow()` に統合済み: プロセス確認 → 未起動時自動起動 → CDP接続確認 → `perf_measure.py` 本計測。cmd_810/811/815 の着地点。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §3, §5
- `9224` は現行 `auto-ops` repo・git履歴・近傍workspace検索で実装痕跡なし。知識としては「現行未確認ポート」と扱う。→ `docs/research/cmd_816_cdp-measurement-architecture.md` §4

## 教訓索引（自動追記）

- （現在0件。L001-L003は振り分け済 → §設計方針、L004 → §設計方針、L005 → §CDP計測索引）
<!-- last_synced_lesson: L012 -->
- （現在0件。L006はL004と重複→統合済み）
- L007: 共有CDPポートではlaunch_browserの修正効果を実証できない場合がある（cmd_885）
- L008: Chrome CDP daemonはremote-allow-origins未設定だとWebSocket handshake 403で失敗する（cmd_885）
- L009: Drive上の生CSVは download/export より get alt=media が安定（cmd_894）
- L010: note.com領収書は直接PDFダウンロード不可+利用規約でスクレイピング禁止（cmd_895）
- L011: MF CSV DL URLは直リンク方式（/cf/csv?from=...）で認証Cookieがあれば直接取得可能（cmd_897）
- L012: 共有9222のheadless Chromeは対botログイン調査で403化するため隔離ポートの通常Chromeへ退避する（cmd_897）
