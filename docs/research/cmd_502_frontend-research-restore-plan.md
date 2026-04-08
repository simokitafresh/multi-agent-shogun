# cmd_502 frontend知識復旧3ファイル 実装仕様書

- 作成日: 2026-03-03
- 目的: `docs/research/frontend-components.md` / `docs/research/frontend-api-spec.md` / `docs/research/frontend-deploy.md` を、現行コード準拠で再作成できる実装仕様を確定する
- 前提: 本cmdは偵察専用（実装変更は禁止）

## AC1. 3ファイルの必須記載項目・章立て・根拠パス

| 対象ファイル | 必須章立て（最低） | 必須テーブル（最低） | 根拠パス（実コード/実設定） |
|---|---|---|---|
| `docs/research/frontend-components.md` | §0 対象範囲と更新日時 / §1 ディレクトリ棚卸し / §2 ページ・ルート一覧 / §3 Context・Hook / §4 コンポーネント分類 / §5 状態遷移とデータフロー / §6 既知ギャップ | T1: `directory_inventory(path,file_count,evidence)` / T2: `page_route_matrix(route,page_file,data_api,main_components)` / T3: `context_hook_matrix(kind,name,file,responsibility)` / T4: `component_catalog(category,file,role)` | `/mnt/c/Python_app/DM-signal/frontend/app` / `.../components` / `.../contexts` / `.../hooks` / `.../lib` / `context/dm-signal-frontend.md:23` |
| `docs/research/frontend-api-spec.md` | §0 対象境界(frontend client視点) / §1 API client基盤 / §2 endpoint一覧 / §3 認証・権限 / §4 キャッシュ・タイムアウト / §5 backend cross-map / §6 互換性注意点 | T1: `endpoint_inventory(client_method,http_method,path,auth,ttl,timeout,backend_source)` / T2: `auth_matrix(flow,storage,expiry,failure_handling)` / T3: `cache_policy(endpoint,ttl,invalidation,notes)` / T4: `method_drift_watch(path,frontend_method,backend_method,status)` | `/mnt/c/Python_app/DM-signal/frontend/lib/api-client.ts` / `.../lib/api-cache.ts` / `/mnt/c/Python_app/DM-signal/backend/app/api/*.py` / `/mnt/c/Python_app/DM-signal/backend/app/main.py` |
| `docs/research/frontend-deploy.md` | §0 デプロイ境界(Render + Next static export) / §1 ビルド・配備構成 / §2 Cron連鎖 / §3 環境変数 / §4 PWA配備物 / §5 ローカル実行手順 / §6 運用チェック | T1: `render_service_matrix(name,type,root,build,start,publish)` / T2: `cron_matrix(name,schedule_utc,schedule_jst,endpoint,auth)` / T3: `env_matrix(name,where,required,default,consumer)` / T4: `pwa_assets(file,purpose,cache_policy)` | `/mnt/c/Python_app/DM-signal/render.yaml` / `/mnt/c/Python_app/DM-signal/frontend/next.config.mjs` / `/mnt/c/Python_app/DM-signal/frontend/package.json` / `/mnt/c/Python_app/DM-signal/frontend/public/manifest.json` / `/mnt/c/Python_app/DM-signal/frontend/public/sw.js` / `/mnt/c/Python_app/DM-signal/docs/research/cmd_485_dm-signal-environment-catalog.md` |

## AC2. cmd_484/cmd_485との差分整理（項目単位）と新規復元範囲

| 差分項目 | 現行`frontend-*`(本リポ) | cmd_484 / cmd_485 または実コード | 復元範囲（cmd_503で追加/修正） |
|---|---|---|---|
| App/Component/Hookの規模 | `18ページ`,`65ファイル`,`6フック` 記載 | 現行は `19ページ`,`70コンポーネント`,`7 Hook`（`context/dm-signal-frontend.md:23`） | すべて現行値に更新し、算出根拠コマンドを明記 |
| `api-client.ts` 行数と機能面 | `1061行` 記載 | 実体は `1121行`。Folder API群が追加（`api-client.ts:1071-1112`） | API仕様の行数・メソッド一覧を再抽出して更新 |
| Admin routes | `/admin/folders` が欠落 | `frontend/app/admin/folders/page.tsx` が存在（616行） | Components/Deploy文書に Admin Folders ページを正式追加 |
| Folder APIのHTTPメソッド | 旧仕様混在の恐れ | frontendは更新 `PUT` 呼び出し、backend実装は `PATCH /api/admin/folders/{folder_id}`（`folders.py:175`） | `method_drift_watch` テーブルを新設し、差分を明示 |
| Render静的配備情報 | 断片的 | `next.config.mjs:3 output='export'` + `render.yaml:32 staticPublishPath: out` | Deploy文書に「Next static export前提」を明文化 |
| Cron連鎖の運用情報 | 未体系化 | `render.yaml` に4層sync + rotation cron詳細あり | UTC/JST併記の cron 行程表を必須化 |
| 環境変数の境界 | frontend中心で不足 | cmd_485 に backend/frontend/cron の環境変数全体像あり | `env_matrix` を frontend利用 + render設定 + backend依存に分離整理 |
| PWA配備資産 | 一部古い説明 | cmd_484 AC4 + 実体 `public/*`, `sw.js` (`CACHE_NAME=dm-signal-v8`) | Deploy文書に assets一覧と fetch戦略を再記述 |
| 参照元docsの所在 | 本リポ側のみ参照しがち | 最新補助資料は DM-signal 側 `docs/research/cmd_484/485` | 参照元を絶対パスで併記し、起点誤認を防止 |

## AC3. 実装時の回帰リスクと検証チェックリスト

### 3.1 回帰リスク

| ID | リスク | 具体例 | 予防策 |
|---|---|---|---|
| R1 | 古いAPI名/メソッドの誤記 | `/api/admin/folders/{id}` を `PUT` 固定で記載しbackend `PATCH` と乖離 | frontend呼び出しと backend router 定義を同時表記し、差分欄を必須化 |
| R2 | 行番号陳腐化 | `api-client.ts` 行数・関数位置が更新され旧line参照が無効化 | 行番号依存を最小化し、関数名/endpoint文字列 anchor を併記 |
| R3 | 環境変数誤記 | `NEXT_PUBLIC_API_URL` 等の非実在キー記載 | `render.yaml` + `api-client.ts` の一致確認を必須チェック化 |
| R4 | 規模値の手入力ドリフト | ページ数/コンポーネント数が実体と不一致 | `find` 集計値をテーブルに直接転記し、算出コマンドを残す |
| R5 | DM-signal側資料未追従 | cmd_484/485の更新内容を反映し忘れ | 参照資料チェック項目に DM-signal 側パス存在確認を追加 |

### 3.2 検証チェックリスト（cmd_503完了判定用）

| # | 検証コマンド | 期待結果 |
|---|---|---|
| 1 | `test -f docs/research/frontend-components.md && test -f docs/research/frontend-api-spec.md && test -f docs/research/frontend-deploy.md` | 3ファイル存在 |
| 2 | `rg -n "19ページ|70コンポーネント|7 Hook" docs/research/frontend-components.md` | 現行規模値が記載されている |
| 3 | `rg -n "/api/admin/folders|PATCH|method_drift_watch" docs/research/frontend-api-spec.md` | folder API差分監視が記載されている |
| 4 | `rg -n "NEXT_PUBLIC_API_HOST|NODE_ENV|env_matrix" docs/research/frontend-api-spec.md docs/research/frontend-deploy.md` | 環境変数名が実装準拠 |
| 5 | `rg -n "output: 'export'|staticPublishPath: out|cron_matrix" docs/research/frontend-deploy.md` | static export + Render配備要件が記載されている |
| 6 | `rg -n "dm-signal-v8|manifest.json|sw.js|pwa_assets" docs/research/frontend-deploy.md` | PWA資産とSW方針が記載されている |
| 7 | `rg -n "/mnt/c/Python_app/DM-signal/docs/research/cmd_484_dm-signal-supplemental-catalog-2.md|/mnt/c/Python_app/DM-signal/docs/research/cmd_485_dm-signal-environment-catalog.md" docs/research/frontend-*.md` | 最新補助資料への参照が残る |
| 8 | `rg -n "1061行|18ページ|65ファイル|6ファイル" docs/research/frontend-*.md` | 旧値が残っていない（0件） |

## cmd_503 実装順序（推奨）

1. `frontend-components.md` を先に再生成（実体棚卸し基準を確定）
2. `frontend-api-spec.md` を生成（components文書のroute/API対応を流用）
3. `frontend-deploy.md` を生成（cmd_485 + render/next/sw を統合）
4. 上記チェックリスト #1-#8 を実行してから提出
