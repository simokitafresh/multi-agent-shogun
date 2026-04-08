# cmd_816: auto-ops CDP計測基盤アーキテクチャ

- 調査日: 2026-03-12
- 対象repo: `/mnt/c/Python_app/auto-ops`
- 対象ファイル:
  - `cdp/cdp_helper.py`
  - `workflows/perf_measure.py`
  - `workflows/perf_config.yaml`
  - `workflows/README.md`
- 調査メモ: task文面の `cdp/perf_measure.py` は現行repoに存在せず、計測CLI本体は `workflows/perf_measure.py`

## §1 構成マップ

| Layer | File | Role | Key refs |
|---|---|---|---|
| CDP transport | `cdp/cdp_helper.py` | WSL2 から PowerShell 経由で Edge/Chrome の CDP HTTP/WebSocket を叩く | `89-140`, `170-188`, `250-310`, `346-408` |
| Measurement CLI | `workflows/perf_measure.py` | config読込、preflight、viewer認証、reload/SPA/PF切替計測、JSON/Markdown出力 | `338-411`, `512-650`, `1447-1705`, `1846-1964` |
| Runtime config | `workflows/perf_config.yaml` | base URL、port、runs、threshold、page selector定義 | `1-120` |
| Operator note | `workflows/README.md` | 実行前提、出力ファイル、基本 usage | `3-49` |

## §2 CDPブラウザ起動オプション

| Item | Current value | Evidence |
|---|---|---|
| Browser selection | `detect_browser(prefer="edge")`。既定は Edge 優先、Chrome fallback | `cdp/cdp_helper.py:89-101` |
| Default port | `9223` | `workflows/perf_config.yaml:1-12`, `cdp/cdp_helper.py:111`, `workflows/perf_measure.py:1861` |
| Launch transport | `ps_run()` -> `powershell.exe -NoProfile -Command ...` | `cdp/cdp_helper.py:18-33`, `111-133` |
| Launch command | `Start-Process "{exe_path}" -ArgumentList ...` | `cdp/cdp_helper.py:125-132` |
| Debug args | `--remote-debugging-port={port}` | `cdp/cdp_helper.py:127` |
| Bind address | `--remote-debugging-address=0.0.0.0` | `cdp/cdp_helper.py:128` |
| Profile isolation | `--user-data-dir=$env:TEMP\\cdp-{browser}-{port}` | `cdp/cdp_helper.py:123-129` |
| Window mode | `--new-window about:blank` | `cdp/cdp_helper.py:130-131` |
| Skip launch case | `_is_cdp_alive(port)` が true なら既存CDPセッションを再利用 | `cdp/cdp_helper.py:111-114`, `191-197` |

補足:
- `launch_browser()` は「通常起動中ブラウザに後付けで CDP を有効化する」のではなく、専用 profile で別インスタンスを起動する設計。
- WebSocket送信は `_cdp_send_sequence()` が Base64 payload を PowerShell に渡し、connect timeout と command timeout を分離している。

## §3 計測フロー

### §3.1 エントリポイント

`main()` の大枠は以下。

```text
parse_args
-> load_config
-> normalize_pages / select_pages / parse_mode_arg / parse_navigation_mode_arg
-> preflight_cdp_flow(port, browser, launch_timeout=30)
-> get_tab_id(base_url, port)
-> enable_browser_domains(tab_id)
-> [production only]
   _warm_up_render
   -> _get_admin_credentials
   -> _fetch_viewer_password
   -> _authenticate_viewer_via_cdp
-> for page in selected_pages
   -> reload or spa measurement loops
   -> optional PF switch loops
-> write `results/perf_<timestamp>.json`
-> write `results/perf_<timestamp>.md`
```

Evidence: `workflows/perf_measure.py:338-411`, `512-650`, `1447-1705`, `1846-1964`

### §3.2 preflight -> 起動 -> 接続 -> 計測

`preflight_cdp_flow()` が cmd_815 時点の正規順序。

| Step | Function | What it does | Evidence |
|---|---|---|---|
| 1 | `_has_running_browser_process()` | Windows 上に `msedge` / `chrome` プロセスがいるか確認 | `cdp/cdp_helper.py:143-152`, `386-388` |
| 2 | `launch_browser()` | 未起動時のみ CDP付きブラウザを自動起動 | `cdp/cdp_helper.py:111-140`, `390-401` |
| 3 | `preflight_cdp_check()` | `/json/version` 疎通で CDP を確認し、失敗理由を整形 | `cdp/cdp_helper.py:155-188`, `403-405` |
| 4 | `perf_measure.py` 本計測 | tab取得、domain enable、認証、reload/SPA/PF switch 計測へ進む | `workflows/perf_measure.py:1887-1964` |

### §3.3 シナリオ別の主処理

| Scenario | Flow | Evidence |
|---|---|---|
| Reload | `ensure_authenticated(cold only)` -> `navigate()` -> `wait_for_page_ready()` -> `get_navigation_entry()` / `get_page_metrics()` / `collect_resource_entries()` | `workflows/perf_measure.py:563-650`, `1447-1524` |
| SPA | source page へ `navigate()` -> `wait_for_page_ready()` -> `reset_perf_probe()` -> `trigger_spa_transition()` -> `collect_perf_probe()` | `workflows/perf_measure.py:1573-1667` |
| PF switch | 対象 page へ遷移 -> PF DOM 観測 -> pair ごとに browser 内 switch 計測 | `workflows/perf_measure.py:1669-1844` |

### §3.4 生成物

| Output | Path | Evidence |
|---|---|---|
| JSON summary | `results/perf_<timestamp>.json` | `workflows/README.md:19`, `workflows/perf_measure.py:1952-1956` |
| Markdown summary | `results/perf_<timestamp>.md` | `workflows/README.md:20`, `workflows/perf_measure.py:1958-1960` |
| Screenshot | `results/screenshots/<page>.png` | `workflows/README.md:21`, `workflows/perf_measure.py:1491-1493`, `1621-1623` |
| Baseline cache | `results/baseline/*.json` | `workflows/perf_measure.py:1869-1875`, `1938-1941` |

## §4 ポート 9223 / 9224 の現状

| Port | Status | Usage | Evidence |
|---|---|---|---|
| `9223` | 実装あり | config既定値、CDP HTTP(`/json/version`)、CDP WebSocket、結果JSONの `port` フィールド | `workflows/perf_config.yaml:5`, `cdp/cdp_helper.py:111-188`, `workflows/perf_measure.py:1861` |
| `9224` | 実装痕跡なし | 現行 `auto-ops` repo、cmd_810/811/815 を含む git履歴、multi-agent-shogun / DM-signal 近傍検索で用途未確認 | `rg -n "9224|remote-debugging-port=9224|port: 9224" ...` と `git log -S'9224' --oneline` の両方で未検出 |

結論:
- 現行知識として扱うべき CDP計測ポートは `9223` のみ。
- `9224` は旧メモ、外部手動運用、または task AC の陳腐化とみるのが自然。ただし「存在しない」と断定ではなく、「現行コード/履歴では確認不能」という扱いが安全。

## §5 cmd_810 / 811 / 815 の反映位置

| cmd | Effect | Code landing point |
|---|---|---|
| `cmd_810` | `preflight_cdp_check()` 追加、HTTP timeout 導入、WebSocket connect timeout と command timeout 分離 | `cdp/cdp_helper.py:170-188`, `250-310` |
| `cmd_811` | `auto_launch_browser()` と自動起動失敗時 ntfy | `cdp/cdp_helper.py:346-370`, `workflows/perf_measure.py:57-76` |
| `cmd_815` | `preflight_cdp_flow()` に「確認 -> 起動 -> 接続」を一本化し、`perf_measure.py` の分散 preflight を置換 | `cdp/cdp_helper.py:373-408`, `workflows/perf_measure.py:1887-1891` |

## §6 運用上の要点

| Topic | Current rule | Evidence |
|---|---|---|
| Production auth | `profiles.production` は frontend=`dm-signal-frontend.onrender.com`, API=`dm-signal-backend.onrender.com` を使う | `workflows/perf_config.yaml:14-24` |
| Cold session | `ensure_authenticated(... cold=True)` が cache/cookie/localStorage を消して再認証 | `workflows/perf_measure.py:549-592`, `1447-1458` |
| Readiness判定 | `wait_for_page_ready()` は `document.readyState` + path一致 + selector待ち | `workflows/perf_measure.py:594-650` |
| Operator docs gap | README 先頭は「existing CDP session」と書くが、現行コードは `preflight_cdp_flow()` で未起動時自動起動まで面倒を見る | `workflows/README.md:5-13`, `cdp/cdp_helper.py:373-408` |

## §7 要約

- CDP計測の実体は `workflows/perf_measure.py` + `cdp/cdp_helper.py` の2層構成。
- ブラウザ起動オプションは `--remote-debugging-port=9223 --remote-debugging-address=0.0.0.0 --user-data-dir=%TEMP%\\cdp-{browser}-{port} --new-window about:blank`。
- 現在の正規フローは `preflight_cdp_flow()` による「プロセス確認 -> 未起動時起動 -> CDP接続確認 -> 計測」。
- `9224` は現行実装・履歴では確認できず、知識としては `9223` 一本で保持するのが妥当。
