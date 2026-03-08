# CDP Helper Library

WSL2からWindows上のEdge/Chromeを自動操作するためのCDPヘルパーライブラリ。

## 前提

- WSL2環境（powershell.exeが利用可能）
- Edge or Chrome がインストール済み
- Python 3.10+（標準ライブラリのみ使用）

## Import

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

## 注意事項

- デバッグポートはブラウザ起動時のみ指定可能（後付け不可）
- WebSocketバッファは1MB
- SPA描画待ちのためnavigate後にデフォルト5秒wait
- 外部ライブラリ依存なし（subprocess, json, base64, time, os のみ）
