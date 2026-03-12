# CDP Automation Toolkit

WSL2からWindows上のEdge/Chromeを自動操作するためのCDPツールキット。
2つの経路を提供: **Daemon mode**（推奨）と **Legacy helper**（直接WebSocket）。

## 前提

- WSL2環境（powershell.exeが利用可能）
- Edge or Chrome がインストール済み（`--remote-debugging-port=9222` で起動）
- Python 3.10+
- Daemon mode: `pip install websocket-client`（requirements.txt参照）

## Legacy Helper Import

```python
from cdp_helper import launch_browser, get_tab, js_eval, navigate
```

同ディレクトリからimportする場合:

```python
import sys
sys.path.insert(0, "/mnt/c/tools/multi-agent-shogun/scripts/cdp")
from cdp_helper import launch_browser, get_tab, js_eval, navigate
```

## 関数一覧

| # | 関数 | 説明 |
|---|------|------|
| 1 | `ps_run(cmd, timeout=30)` | PowerShell実行ラッパー |
| 2 | `cdp_get(path, port=9223)` | CDP REST API呼び出し（/json等） |
| 3 | `cdp_send(ws_url, method, params, timeout=30)` | WebSocket経由CDPコマンド送信（B64エンコード） |
| 4 | `js_eval(ws_url, expression)` | JavaScript式評価 |
| 5 | `navigate(ws_url, url, wait=5.0)` | URL遷移+待機 |
| 6 | `detect_browser(prefer="edge")` | Edge/Chrome実行ファイルパスを自動検出 |
| 7 | `launch_browser(browser="auto", port=9223)` | デバッグモードでブラウザ起動（二重起動防止付き） |
| 8 | `get_tab(url_pattern=None, port=9223)` | タブ情報取得（URLパターンマッチ） |
| 9 | `wait_for_element(ws_url, selector, timeout=10)` | DOM要素出現待機 |
| 10 | `screenshot(ws_url, path)` | Page.captureScreenshot |
| 11 | `get_page_metrics(ws_url)` | Performance.getMetrics |

## 使用例

### 基本的な流れ

```python
from cdp_helper import launch_browser, get_tab, js_eval, navigate, wait_for_element

# 1. ブラウザ起動（既に起動済みならスキップ）
launch_browser()

# 2. タブ取得
tab = get_tab()
ws = tab["webSocketDebuggerUrl"]

# 3. ページ遷移
navigate(ws, "https://example.com")

# 4. DOM要素待機
wait_for_element(ws, "h1")

# 5. JavaScript実行
title = js_eval(ws, "document.title")
print(f"Title: {title}")
```

### 特定タブの操作

```python
tab = get_tab("github.com")  # URLに"github.com"を含むタブ
if tab:
    ws = tab["webSocketDebuggerUrl"]
    js_eval(ws, "document.querySelectorAll('.repo').length")
```

### スクリーンショット

```python
from cdp_helper import screenshot
screenshot(ws, "/tmp/page.png")
```

## アーキテクチャ

```
WSL2 Python
  └─ subprocess.run(powershell.exe)
       ├─ HTTP: Invoke-WebRequest → localhost:9223/json
       └─ WebSocket: ClientWebSocket → ws://... (B64エンコード)
            └─ CDP Protocol → Edge/Chrome
```

### B64エンコードの理由

Python → shell → PowerShell → WebSocket → CDP → JavaScript の5層を
通過するためクォートが衝突する。Base64でペイロード全体をエンコードし
PowerShell側でデコードすることで回避。

## Daemon Mode（cdp_server.py + cdp_cli.sh）

persistent WebSocket接続を維持するHTTPデーモン。毎回のWebSocket接続/切断コストを排除。

### 起動

```bash
# サーバー手動起動（通常はcdp_cli.shが自動起動する）
python3 scripts/cdp/cdp_server.py

# サーバー情報は /tmp/cdp-server.json に書き出される
cat /tmp/cdp-server.json
# {"port": 8222, "token": "uuid-...", "pid": 12345}
```

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
  └─ curl → HTTP localhost:8222
       └─ cdp_server.py (Python daemon)
            └─ persistent WebSocket → Chrome CDP (port 9222)
```

### Legacy helper（cdp_helper.py）との違い

| | Daemon mode | Legacy helper |
|---|---|---|
| 接続方式 | persistent WebSocket | 毎回PowerShell→WebSocket |
| 呼び出し | bash (curl) | Python import |
| 依存 | websocket-client | 標準ライブラリのみ |
| ref選択 | AXTree @ref | CSS selector |
| 速度 | 高速（接続維持） | 低速（毎回接続） |

## 注意事項

- デバッグポートはブラウザ起動時のみ指定可能（後付け不可）
- Legacy helper: WebSocketバッファは1MB、navigate後にデフォルト5秒wait
- Daemon mode: idle 30分で自動停止、Bearer認証必須
- Legacy helper: 外部ライブラリ依存なし（subprocess, json, base64, time, os のみ）
