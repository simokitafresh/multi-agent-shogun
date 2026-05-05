---
name: cdp-browse
argument-hint: "<url> [screenshot_path]"
description: |
  CDPでWebブラウザを人間と同じように使うための基礎スキル。
  ブラウザ起動、ログイン、ページ遷移、スクリーンショット、画面状況確認を1つの標準フローで実行する。
  TRIGGER: /cdp-browse、CDPで確認、ブラウザ確認、ログインしてスクショ、Render画面確認、DM-Signal本番FE確認
  DO NOT TRIGGER: DB確認（→/db-check）、静的コード確認だけで足りる調査、E2E全体試験
quality_metric: "CDP確認タスクで、認証失敗・スクショ未取得・CDPポート不通によるやり直しが発生しない割合"
---

# /cdp-browse

CDPの本質は、LLMが人間と同じようにWebブラウザを使えること。推測で答えず、ブラウザ起動、ログイン、遷移、スクリーンショット、画面確認までを同じ順序で実行する。

## 基本フロー

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

## DM-Signal 本番FE

DM-Signalの認証情報はPJ contextを参照し、値をレポートやログに書かない。標準手順は `auto-ops` の認証 helper でCookieをブラウザに注入してから確認する。

```bash
cd /mnt/c/Python_app/auto-ops
scripts/cdp/cdp_cli.sh auth --env .env.dm-signal --port 9400
scripts/cdp/cdp_cli.sh navigate "https://dm-signal-frontend.onrender.com/admin"
scripts/cdp/cdp_cli.sh screenshot "/tmp/dm-signal-admin.png"
```

## 判定基準

- CDPポート不通だけで中断していない。
- 認証が必要な場合、PJ contextの認証方式を確認してからログインしている。
- 最終回答に、確認URL、スクリーンショット保存先、画面上の確認結果が含まれている。
- 失敗時は、preflight、auth、navigate、screenshot のどこで失敗したかを分けて報告している。
