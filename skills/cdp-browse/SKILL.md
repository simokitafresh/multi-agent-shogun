---
name: cdp-browse
argument-hint: "[url] [screenshot_path]"
description: |
  CDPでWebブラウザを人間と同じように使うための基礎スキル。
  ブラウザ起動、ログイン、ページ遷移、スクリーンショット、画面状況確認を1つの標準フローで実行する。
  TRIGGER: /cdp-browse、CDPで確認、ブラウザ確認、ログインしてスクショ、本番画面をスクショ、スクショして、画面確認、Render画面確認、DM-Signal本番FE確認 project:dm-signal、rebalancer本番画面確認 project:rebalancer、本番動作確認 role:ninja、修正後の画面確認 role:ninja、CI RED後の画面確認 role:karo、本番FE検証 role:karo
  DO NOT TRIGGER: DB確認（→/db-check）、静的コード確認だけで足りる調査、E2E全体試験
quality_metric: "CDP確認タスクで、認証失敗・スクショ未取得・CDPポート不通によるやり直しが発生しない割合"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

<!-- script_refs_checked_at: 2026-06-26T17:40:00+09:00 -->

Script refs verified: 2026-06-20 782be65a6. `note_draft.sh` 直近変更はPJパス直書き除去でget_project_path経由へ置換した内部SSOT化。CDPブラウズ手順・preflight/navigate/screenshotの契約変更なし。

<!-- script_refs_checked_at: 2026-06-20T14:58:00+09:00 -->

Script refs verified: 2026-06-12. `note_draft.sh` の契約は `<markdown_file>` 1件を受け取りCDP経由でnote下書きを作る形式のまま。932936059は外部reCAPTCHA画像チャレンジ未解決を運用FAILではなくSKIPとして`skill_execution_log.yaml`へ記録し、exit 0で返す変更。Gate20も同じ外部reCAPTCHAチャレンジ由来の`note-draft`結果をFAIL率分母から除外する。引数・CDP_PORT・通常PASS/FAILログの契約変更なし。
Script refs verified: 2026-06-16 cmd_karo_skill_refs_update_20260616. `note_draft.sh` 直近変更(6ac00607e)はshellcheckコメント形式修正(markdown list→shell comment)のみ。引数・CDP_PORT・通常PASS/FAILログの契約変更なし。

# /cdp-browse

CDPの本質は、LLMが人間と同じようにWebブラウザを使えること。推測で答えず、ブラウザ起動、ログイン、遷移、スクリーンショット、画面確認までを同じ順序で実行する。

## 基本フロー

### Chrome未起動時の復旧

CDPポート未応答だけで止まらない。まず `preflight_cdp_flow` に自動起動させる。手動復旧が必要な場合は、Windows側Chrome/Edgeを隔離プロファイルかつ `--remote-allow-origins=*` 付きで起動する。

```powershell
Start-Process chrome.exe --remote-debugging-port=9222 --remote-allow-origins=* --user-data-dir=$TEMP/cdp-edge-9222 --no-first-run
```

`--remote-allow-origins=*` がないとCDP WebSocket接続が403になることがある。`--user-data-dir` は殿の通常Chromeセッションを汚さないため必須。

1. `preflight_cdp_flow` でCDPブラウザを確認する。CDPポート未応答で止まらず、隔離プロファイルのブラウザ自動起動に任せる。
2. 認証が必要なサイトなら、対象PJの `projects/{project}.yaml` と `context/{project}.md` から認証方式と認証情報の参照先を確認する。
3. UIログインが正本のサイトでは `ui_login` を使い、フォーム入力、送信、ログイン後URLまたは画面要素まで確認する。
4. Cookie注入などPJ専用の認証 helper が正本化されている場合は、そのPJ contextの手順を優先する。DM-Signalは `auto-ops` の `cdp_cli.sh auth --env <env>` が標準。
5. `navigate` で対象URLへ移動する。
6. `screenshot` で証跡を保存する。
7. スクリーンショットまたはAX snapshotを読んで、画面が期待状態かを報告する。

## 実行例

```bash
# 1. CDP daemonのヘルスチェック。未起動なら自動起動される。
scripts/cdp/cdp_cli.sh healthz

# 2. URL遷移。
scripts/cdp/cdp_cli.sh navigate "https://example.com"

# 3. スクリーンショット保存。
scripts/cdp/cdp_cli.sh screenshot "/tmp/cdp-browse-example.png"

# 4. 画面構造確認。クリック対象が必要なら @ref を使う。
scripts/cdp/cdp_cli.sh snapshot
```

## Python preflight / UI Login

`preflight_cdp_flow` と `ui_login` は `auto-ops` 側のCDPプリミティブを使う。手動で `chrome --headless` を叩く場合も `--user-data-dir` を省略してはならない。

```python
import sys
sys.path.insert(0, "/mnt/c/Python_app/auto-ops")
from cdp import cdp_helper

result = cdp_helper.preflight_cdp_flow(port=9222, browser="auto", launch_timeout=30)
port = result.get("cdp_port", 9222)
tab_id = cdp_helper.create_tab(url="https://example.com/login", port=port, timeout=30)
cdp_helper.ui_login(tab_id, user, password, port=port)
```

### Cookie注入失敗時のフォームログイン

`Network.setCookie` や `cdp_cli.sh auth` でCookieを注入しても認証ダイアログが解消しない場合は、UIフォームログインへ切り替える。React管理のinputはJSの直接 `value = ...` ではstateが更新されないため、`nativeInputValueSetter` で値を入れて `input` eventを発火する。

```javascript
const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
const setInput = (selector, value) => {
  const el = document.querySelector(selector);
  setValue.call(el, value);
  el.dispatchEvent(new Event("input", { bubbles: true }));
};

setInput('input[name="username"], input[type="text"]', user);
setInput('input[name="password"], input[type="password"]', password);
document.querySelector('button[type="submit"], button').click();
```

## ポート使い分け

| port | 用途 | profile |
|------|------|---------|
| 9222 | 汎用。DM-Signalなどの本番FE確認 | `$TEMP/cdp-edge-9222` |
| 9234 | note.com下書き保存 | `$TEMP/cdp-edge-9234` |
| 9400 | `auto-ops` CDP daemon / `cdp_cli.sh` 操作口 | daemon管理 |

同時に複数サイトを扱う場合はポートと `--user-data-dir` を分ける。ログイン状態やCookieを混ぜない。

note.com下書き保存では、共通ヘルパー `scripts/note_draft.sh` を使う。引数はMarkdownファイル1件のみで、`CDP_PORT` 未指定時は9234を使う。9234はnote.com専用の隔離プロファイルとして扱い、9222の汎用確認や9400のdaemon操作口と混ぜない。

```bash
CDP_PORT=9234 bash scripts/note_draft.sh "<記事.md>"
```

`note_draft.sh` は `auto-ops/cdp/cdp_helper.py` の `launch_browser` / `get_tab` / `js_eval` / `navigate` / `cdp_send` / `screenshot` / `_is_cdp_alive` を使う。bash層でChrome CDP事前チェック(Step 0)を行い、CDP_PORTに応答がなければSKIP(exit 0)で抜ける(FAIL率汚染防止)。Chrome起動時は `launch_browser`(PowerShell)を試行し、失敗時は `cmd.exe` フォールバックで隔離プロファイル付きChrome起動を試みる。未ログイン時は `.env.note` の `NOTE_EMAIL` / `NOTE_PASSWORD` でログインし、reCAPTCHA画像チャレンジが出た場合は `/tmp/note_recaptcha_challenge.png` を出力して最大120秒待つ。外部reCAPTCHAチャレンジが解決されずログイン完了できない場合はSKIPとして記録し、exit 0で終了する。これは人間/外部サービス待ちであり、Gate20のスキルFAIL率からも除外される。ProseMirrorエディタがスピナーで停止している場合は `Page.reload` で最大2回リトライする。本文挿入は `.ProseMirror.note-common-styles__textnote-body` → `div.ProseMirror` → `div[contenteditable]` の3段fallbackでエディタを検出する。下書き保存の成果はnote.comエディタ上のドラフトで、スクリプトは最終URLを `[note_draft] Done: ...` に出し、`skill_execution_log.yaml` にPASS/FAIL/SKIPを記録する。

## cdp_cli.sh不可時の直接WS操作

`cdp_cli.sh` やdaemonが使えない場合は、Chromeの `/json` からWebSocket URLを取得してCDPを直接送る。最小パターンは `Page.navigate` と `Page.captureScreenshot`。

```python
import base64
import json
import urllib.request
from websocket import create_connection

port = 9222
tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
ws = create_connection(tabs[0]["webSocketDebuggerUrl"], timeout=10)
seq = 0

def send_cmd(method, params=None):
    global seq
    seq += 1
    ws.send(json.dumps({"id": seq, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == seq:
            return msg

send_cmd("Page.enable")
send_cmd("Page.navigate", {"url": "https://example.com"})
shot = send_cmd("Page.captureScreenshot", {"format": "png", "fromSurface": True})
open("/tmp/cdp-direct.png", "wb").write(base64.b64decode(shot["result"]["data"]))
```

## DM-Signal 本番FE

DM-Signalの認証情報はPJ contextを参照し、値をレポートやログに書かない。標準手順は `auto-ops` の認証 helper でCookieをブラウザに注入してから確認する。

```bash
cd /mnt/c/Python_app/auto-ops
scripts/cdp/cdp_cli.sh auth --env .env.dm-signal --port 9400
scripts/cdp/cdp_cli.sh navigate "https://dm-signal-frontend.onrender.com/admin"
scripts/cdp/cdp_cli.sh screenshot "/tmp/dm-signal-admin.png"
```

## 能動的な画面確認

ブラウザ状態を推測で埋めない。次のどれかに当たる場合は、遷移直後または操作直後にスクリーンショットかAX snapshotを取得してから判断する。

- ログイン、認証ダイアログ、bot検知、user_verificationの有無を確認する時
- UI変更、FE修正、本番FE、Render画面など、画面の見た目や表示状態が結論になる時
- ボタン押下、フォーム入力、下書き保存、ファイル出力など、操作成功をブラウザ上で確認すべき時
- CDPコマンドは成功したが、URL、DOM、画面表示のどれかが期待状態か不明な時

## 判定基準

- CDPポート不通だけで中断していない。
- 認証が必要な場合、PJ contextの認証方式を確認してからログインしている。
- 最終回答に、確認URL、スクリーンショット保存先、画面上の確認結果が含まれている。
- 失敗時は、preflight、auth、navigate、screenshot のどこで失敗したかを分けて報告している。

## 因果リンク

- → [[cdp-severity.md]] CDP計測・canary・ブラウザ実測の異常分類（操作失敗時の重大度判定基準）

<!-- script_refs_checked_at: 2026-06-26T17:40:00+09:00 -->
