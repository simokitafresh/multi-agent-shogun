# CDP哲学 — 人間と同じようにブラウザを操作する
<!-- last_updated: 2026-04-26 殿定義(修正版) -->

## 本質（殿定義 2026-04-26）

**CDPとは「人間と同じようにブラウザを操作する」こと。**

**スクショ(視覚情報)+直接操作 = 人間と同じ = 全て可能。**
人間を排除しない(headlessにしない)以上、人間ができることは全てCDPでできる。
captureもOAuthもログインも。API呼出しやCookie注入は不要 — 人間はAPIを叩かない。

人間がやること → CDPが自動でやる:
- ブラウザが閉じている → **起動する**（cdp_helper.launch_browser）
- ポートが塞がっている → **別ポートを使う**（cdp_helper._find_available_cdp_port）
- ログインしていない → **.envの情報でログインする**（cdp_cli.sh auth）
- 複数作業を並行 → **別ポートで並列実行**（_CDP_SCAN_PORTS）
- Chrome/Edgeどちらでも → **Chromium系なら何でも動く**（detect_browser）

殿の手を借りる工程は**ゼロ**。「殿のChromeで起動してくれ」「殿にログインしてもらう」はCDP哲学の否定。

## ×誤解 → ○正しい理解

| × 誤解 | ○ 正しい理解 |
|--------|-------------|
| 殿の既存Chromeセッションに接続する | 未起動でも起動してログインまで自動でやる |
| Chrome CDPが起動していることが前提 | 未起動なら自動起動。ポート塞がりなら自動探索 |
| 殿にChromeを起動してもらう必要がある | 殿の手は一切不要。全自動 |
| port 9222固定 | 9222-9300を自動スキャン。並列計測対応 |
| ヘッドレスが高速 | headless禁止（reCAPTCHA対策）。D009遵守 |

## 技術スタック

| 層 | ファイル | 役割 |
|----|---------|------|
| 共通基盤 | `auto-ops/cdp/cdp_helper.py` | ブラウザ起動/ポート自動探索/CDP接続/タブ管理/ui_login |
| 認証 | `cdp_helper.ui_login()` | 人間と同じUI操作でログイン(snapshot→入力→クリック→確認) |
| 計測ラッパー | `scripts/cdp/cdp_measure.sh` | Pre-flight→Artifact分離→計測→比較の4Phase統合 |
| 計測エンジン | `auto-ops/workflows/perf_measure.py` | ページ計測本体(2,412行) |

## 自動化フロー（全ステップ人間介入ゼロ）

```
cdp_measure.sh 実行
  → Phase 1a: perf_measure.py存在確認
  → Phase 1b: Frontend healthz確認
  → Phase 1c: cdp_cli.sh auth 呼出し
      → cdp_helper.preflight_cdp_flow
          → ブラウザプロセス確認
          → ポート自動探索 (9222→9223→...→9300)
          → 未起動→自動起動 (Chrome/Edge自動検出)
          → CDPポート疎通確認
      → .envからcredentials読取り
      → Viewer認証 (POST /api/auth/verify-viewer)
      → Admin認証 (POST /api/admin/login + Basic Auth)
      → Network.setCookieでブラウザにCookie注入
  → Phase 2: cmd_idベース出力先自動決定
  → Phase 3: perf_measure.py実行 (ブラウザ認証済み)
  → Phase 4: ベースライン比較
```

## 並列計測

複数忍者が同時にCDP計測する場合、各忍者は異なるポートで独立起動:
- 忍者A: CDP_PORT=9222 (自動割当)
- 忍者B: CDP_PORT=9223 (9222塞がり→次の空き)
- 忍者C: CDP_PORT=9224

`cdp_helper._find_free_port`が空きポートを自動検出。

## Chromium共通

CDPプロトコルはChromium共通。Chrome/Edge区別不要。
`cdp_helper.detect_browser`がChrome優先→Edge fallbackで自動検出。

## 実績

| 用途 | 内容 |
|------|------|
| FE速度計測 | `cdp_measure.sh` 4Phase統合パイプライン |
| note.com投稿 | `CDP_PORT=9234 bash scripts/note_draft.sh <記事.md>` |
| auto-ops認証 | `.env.{service}`パターンでサービス別CDP自動入力 |
| 確定申告証票 | cmd_947-951: note.com領収書DL、PayPal領収書差替え |

## WSL2固有の注意

- **curlはWindows localhostのCDPに接続不可**（Connection refused）
- **Python socketは接続可能**
- CDPチェックはcurlではなく`cdp_helper.preflight_cdp_check`(Python)を使え
