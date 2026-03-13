# CDP Automation Toolkit

WSL2からWindows上のChrome/Edgeを自動操作するためのCDPツールキット。

## 正式手段: Daemon Mode（cdp_server.py + cdp_cli.sh）

**Daemon modeが唯一の正式なCDP操作手段。** persistent WebSocket接続を維持するHTTPデーモンで、毎回のWebSocket接続/切断コストを排除する。

### 前提

- WSL2環境（powershell.exeが利用可能）
- Chrome or Edge がインストール済み（`--remote-debugging-port=9222` で起動）
- Python 3.10+
- `pip install websocket-client`（requirements.txt参照）

### CLI使用例

```bash
# ヘルスチェック（サーバー未起動なら自動起動）
scripts/cdp/cdp_cli.sh healthz

# URL遷移
scripts/cdp/cdp_cli.sh navigate "https://example.com"

# スクリーンショット
scripts/cdp/cdp_cli.sh screenshot /tmp/page.png

# アクセシビリティツリー取得（@ref付き）
scripts/cdp/cdp_cli.sh snapshot

# ref-based要素クリック
scripts/cdp/cdp_cli.sh click @e1

# JavaScript実行
scripts/cdp/cdp_cli.sh eval "document.title"

# サーバー停止
scripts/cdp/cdp_cli.sh stop
```

### アーキテクチャ

```
bash (cdp_cli.sh)
  └─ curl → HTTP localhost:9400
       └─ cdp_server.py (Python daemon)
            └─ persistent WebSocket → Chrome CDP (port 9222)
```

### 特徴

| 項目 | 内容 |
|------|------|
| 接続方式 | persistent WebSocket（websocket-client） |
| 呼び出し | bash (curl) |
| ref選択 | AXTree @ref（インタラクティブ要素自動番号付け） |
| 認証 | Bearer token（UUID、/tmp/cdp-server.json） |
| 自動停止 | idle 30分で自動shutdown |
| CDPポート | 9222（`--cdp-port`で変更可） |

## ブラウザ起動ヘルパー（cdp_helper.py）

ブラウザの検出・起動のみを担当するユーティリティ。CDP操作機能はDaemon modeに統合済み。

### 関数一覧

| # | 関数 | 説明 |
|---|------|------|
| 1 | `ps_run(cmd, timeout=30)` | PowerShell実行ラッパー |
| 2 | `cdp_get(path, port=9222)` | CDP REST API呼び出し（_is_cdp_alive内部用） |
| 3 | `detect_browser(prefer="chrome")` | Chrome/Edge実行ファイルパスを自動検出 |
| 4 | `launch_browser(browser="auto", port=9222)` | デバッグモードでブラウザ起動（二重起動防止付き） |

### 使用例

```python
from cdp_helper import launch_browser, detect_browser

# ブラウザ起動（既に起動済みならスキップ）
launch_browser()

# Chrome優先で検出
path = detect_browser(prefer="chrome")
```

## 注意事項

- デバッグポートはブラウザ起動時のみ指定可能（後付け不可）
- CDPポートは全コンポーネントで `9222` に統一
- Daemon mode: idle 30分で自動停止、Bearer認証必須

## Deprecated: Legacy Helper関数

以下の関数はcmd_885でcdp_helper.pyから削除済み。全てDaemon mode（cdp_cli.sh）で代替可能。

| 旧関数 | Daemon代替 |
|--------|-----------|
| `cdp_send(ws_url, method, params)` | `cdp_cli.sh eval` / `/cdp/command` endpoint |
| `js_eval(ws_url, expression)` | `cdp_cli.sh eval "<expression>"` |
| `navigate(ws_url, url)` | `cdp_cli.sh navigate "<url>"` |
| `get_tab(url_pattern, port)` | Daemon内部で自動選択 |
| `wait_for_element(ws_url, selector)` | `cdp_cli.sh eval "!!document.querySelector('...')"` |
| `screenshot(ws_url, path)` | `cdp_cli.sh screenshot <path>` |
| `get_page_metrics(ws_url)` | `/cdp/command` endpoint + `Performance.getMetrics` |
