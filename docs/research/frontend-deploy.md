# DM-signal フロントエンド — PWA・テスト・デプロイ・機能追補
<!-- source: context/dm-signal-frontend.md (cmd_256 佐助補完) -->
<!-- moved: cmd_286 索引化+圧縮 -->

> 索引: `context/dm-signal-frontend.md` → このファイル

## §1 PWA対応

manifest.json, ServiceWorker(sw.js), オフラインフォールバックページ, installプロンプト

### §1.1 PWA設定詳細（manifest / SW / 更新通知）

対象ファイル:
- `public/manifest.json`
- `public/sw.js`
- `components/sw-register.tsx`
- `app/offline/page.tsx`

`manifest.json`:
- `name`: `DM-Signal`
- `short_name`: `DM-Signal`
- `display`: `standalone`
- `start_url`: `/`
- `orientation`: `portrait-primary`
- `theme_color`: `#22c55e`
- `background_color`: `#0a0a0a`
- icon: `icon-192.png`, `icon-512.png`（`purpose: any maskable`）

Service Worker (`sw.js`):
- キャッシュ名: `dm-signal-v8`（バージョン明示）
- install時に静的アセットを事前キャッシュ:
  - `/manifest.json`
  - `/icon-192.png`
  - `/icon-512.png`
- activate時に旧キャッシュを削除（`CACHE_NAME` 以外を purge）
- `self.skipWaiting()` + `clients.claim()` で新SWを即時反映

fetch戦略:
- `/_next/static/*`: **Cache First**（初回取得後キャッシュ）
- `/_next/*`（`/_next/data` 等）: **Network Only**
- `request.mode === "navigate"`: SW介入を回避（ブラウザ処理に委譲）
- `/api/*` および `/admin/*`（ページ本体以外）: **Network Only**
- `signals.json`: **Network First**（失敗時はcache fallback、未キャッシュなら503 JSON）
- script/style/image: **Cache First**

更新通知UI (`components/sw-register.tsx`):
- `navigator.serviceWorker.register("/sw.js")`
- `registration.onupdatefound` を監視し、新版検出時に右下トースト表示
- `Refresh` ボタンは `window.location.reload()`

オフラインページ:
- `app/offline/page.tsx` は存在するが、`sw.js` に navigation fallback (`/offline`) の明示ルーティングは未実装

## §2 テスト現状（cmd_256 AC2）

### §2.1 テストファイル全一覧（29件）

```text
app/__tests__/page-masking.test.tsx
app/__tests__/page_masking.test.tsx
app/admin/components/__tests__/AdvancedOperations.test.tsx
app/admin/components/__tests__/LoginModal.test.tsx
app/admin/components/__tests__/LookbackEditor.test.tsx
app/admin/fof/__tests__/fof_copy_reorder.test.tsx
app/admin/fof/components/__tests__/FoFEditor.test.tsx
app/admin/fof/components/__tests__/SelectionPipelineSection.test.tsx
app/admin/fof/components/__tests__/TerminalBlockSection.test.tsx
app/admin/visibility/__tests__/visibility-page.test.tsx
app/admin/visibility/components/__tests__/ManageTiersModal.test.tsx
components/__tests__/annual_returns_masking.test.tsx
components/__tests__/annual_returns_open_toggle.test.tsx
components/__tests__/auth-status.test.tsx
components/__tests__/chart-props.test.ts
components/__tests__/monthly_returns_056.test.tsx
components/__tests__/monthly_returns_masking.test.tsx
components/__tests__/monthly_returns_open_toggle.test.tsx
components/__tests__/period-notes.test.tsx
components/__tests__/summary-table-true-cagr.test.tsx
components/__tests__/viewer-auth-modal.test.tsx
hooks/__tests__/movePortfolio.test.ts
lib/__tests__/admin-auth.test.ts
lib/__tests__/api-client-auth.test.ts
lib/__tests__/api-client-password.test.ts
lib/__tests__/chart-utils.test.ts
lib/__tests__/constants.test.ts
lib/__tests__/lookbackFormatter.test.ts
lib/__tests__/viewer-auth.test.ts
```

内訳:
- `lib`: 7件
- `hooks`: 1件
- `components`: 10件
- `app/__tests__`: 2件
- `app/admin/**/__tests__`: 9件

### §2.2 実行可否（Preflight + 実行結果）

Preflight:
- `node v20.20.0`
- `npm 10.8.2`
- `node_modules` 存在
- `npx jest --version` = `30.1.3`

実行コマンド:
- `npm test -- --runInBand --watchAll=false`

結果:
- Test Suites: `5 failed, 24 passed, 29 total`
- Tests: `22 failed, 202 passed, 224 total`
- Skipped: `0`
- 結論: **現状はテスト未完了（FAIL）**

主な失敗パターン:
- 文言変更の未追従（英語期待 vs 実装日本語）
  - `app/admin/fof/components/__tests__/SelectionPipelineSection.test.tsx`
  - `app/admin/fof/components/__tests__/FoFEditor.test.tsx`
- `structuredClone` 未定義（JSDOM側ポリフィル不足）
  - `app/admin/fof/__tests__/fof_copy_reorder.test.tsx`
- 期待値の旧仕様固定
  - `lib/__tests__/chart-utils.test.ts`（stroke width）
  - `lib/__tests__/api-client-auth.test.ts`（Authorization header）

### §2.3 カバレッジ現状

`npm test -- --runInBand --watchAll=false --coverage` 実行で `coverage/coverage-final.json` 生成を確認。

全体カバレッジ（coverage-final.json集計）:
- Lines: `71.44%` (7339/10273)
- Statements: `71.44%` (7339/10273)
- Functions: `38.48%` (127/330)
- Branches: `70.76%` (496/701)

`lib/`（types除外）カバレッジ:
- Lines: `65.25%` (1369/2098)
- Statements: `65.25%`
- Functions: `40.52%` (47/116)
- Branches: `76.63%` (141/184)

`lib`で未計測（coverage対象外）ファイル:
- `lib/colors.ts`
- `lib/faq-content.ts`

### §2.4 概算カバレッジ（ファイル比率）

- テストファイル数: `29`
- 対象ソースファイル数（`app+components+hooks+lib(types/test除外)`）: `108`
- テストファイル比率: 約`26.9%`
- `lib`実装ファイル: `12`、そのうち `lib/__tests__` で直接対象化: `7`

## §3 i18n対応範囲

結論:
- 本格i18nフレームワーク（next-intl / i18next等）は未導入
- 実装済み言語は **EN/JP の2言語のみ**
- EN/JP以外（zh/es/fr等）の翻訳データ・ルーティングは未実装

実装箇所:
- `lib/faq-content.ts`: `Record<"en" | "jp", FAQContent>` でFAQ全文を2系統保持
- `app/faq/page.tsx`: `?lang=jp` クエリで言語切替（未指定は `en`）
- `components/language-toggle.tsx`: `EN` / `JP` トグルUI
- ルートHTML: `app/layout.tsx` の `<html lang="ja">` 固定

補足:
- `next.config.mjs` に i18n locale 設定なし（locale routing未使用）
- FAQページ以外は共通文言（日本語/英語混在）で、ページ単位翻訳管理は行っていない

## §4 SEO / メタデータ設定

確認結果:
- `next-seo` 依存は未導入（`package.json` dependenciesに存在しない）
- メタデータ定義は `app/layout.tsx` のグローバル設定のみ

`app/layout.tsx` で設定される項目:
- `metadata.title`: `DM-Signal`
- `metadata.description`: `Premium Dual Momentum Signal Dashboard`
- `metadata.manifest`: `/manifest.json`
- icons: favicon / apple touch icon
- `<head>` 直書き:
  - backend への `preconnect`, `dns-prefetch`
  - `apple-mobile-web-app-capable`
  - `mobile-web-app-capable`
  - `apple-mobile-web-app-status-bar-style`

未実装項目:
- ページ個別 `metadata` / `generateMetadata`
- Open Graph / Twitter Card 専用設定
- `robots.txt` / `sitemap.xml`

## §5 環境変数一覧と用途

検出キー:

| 変数名 | 用途 | 主な参照箇所 |
|---|---|---|
| `NEXT_PUBLIC_API_HOST` | APIベースURL上書き。`api-client` が protocol補正付きで `baseUrl` を構築 | `lib/api-client.ts` |
| `NODE_ENV` | 開発時ログ出力の分岐（`development` のときのみ `console.log`） | `components/sw-register.tsx`, `hooks/usePrefetch.ts`, `hooks/useAppVisibility.ts`, `hooks/useAdminPage.ts`, `contexts/signals-context.tsx`, `lib/api-cache.ts`, `lib/api-client.ts` |

`.env*` 実ファイル:
- `frontend/` 直下に `.env`, `.env.local`, `.env.production` 等は存在しない

`NEXT_PUBLIC_API_HOST` 未設定時の挙動:
- `lib/api-client.ts` のデフォルト `baseUrl` は `http://localhost:8000`

## §6 PFフォルダー機能（cmd_283 実装済み）

### §6.1 実装サマリー

**ステータス: 実装済み（cmd_283）**

3 subtask構成で実装:
- subtask_283_api (sasuke): `/api/signals` folder_id追加 + 型更新 + context拡張
- subtask_283_admin (kagemaru): Admin画面フォルダー管理ページ
- subtask_283_selector (hanzo): PFセレクター フォルダーグループ表示

### §6.2 バックエンド変更

| 変更 | ファイル |
|------|---------|
| `/api/signals`レスポンスに`folder_id`追加 | `backend/app/api/signals.py` (3箇所のportfolio_signals.append) |

### §6.3 フロントエンド型・API

| 変更 | ファイル |
|------|---------|
| `PortfolioSignal`に`folder_id?: string \| null`追加 | `lib/types/portfolio.ts` |
| Folder CRUD API 6メソッド追加 | `lib/api-client.ts` (getFolders, createFolder, updateFolder, deleteFolder, reorderFolders, movePortfolioToFolder) |

### §6.4 Context拡張

`contexts/signals-context.tsx`:
- `folders: PortfolioFolder[]`をstate追加
- Admin時のみ`api.getFolders()`を呼び出し（Viewer 401回避）
- `SignalsContextValue`にfolders公開

### §6.5 PFセレクター（単一選択）

| ファイル | 役割 |
|---------|------|
| `components/portfolio-select-items.tsx` (新規91行) | フォルダーグループ化SelectItemリスト。`groupByFolder()`でフォルダー別に分類。全PFが未分類なら従来フラットリストにフォールバック |
| `components/ui/select.tsx` (+37行) | `SelectGroup`, `SelectGroupLabel`, `SelectSeparator`プリミティブ追加 |

適用ページ(10ページ): Home, Dashboard, Summary, Metrics, Trades, MonthlyReturns, AnnualReturns, MonthlyTrade, RollingReturns, Drawdowns

各ページの変更パターン: `SelectItem`直接レンダリング → `PortfolioSelectItems`コンポーネント委譲。`useSignals()`から`folders`取得。

### §6.6 PFセレクター（複数選択 — Compare）

`components/portfolio-selector.tsx` (86行→142行):
- `folders`プロパティ追加（オプション）
- `groupByFolder()`で内部グループ化
- フォルダーあり: グループ見出し + flex-wrap
- フォルダーなし: 従来フラットリスト

### §6.7 Admin画面フォルダー管理

`app/admin/folders/page.tsx` (新規611行):
- フォルダーCRUD（作成・編集・削除）
- PFのフォルダー割当・解除
- フォルダーsort_order管理
- Adminログインフロー + 認証チェック

`app/admin/page.tsx`: フォルダー管理ページへのナビゲーションリンク追加

### §6.8 未分類PF表示

フォルダー未所属PF（`folder_id`がnull/undefined/無効なfolder_id）は「Uncategorized」グループとして末尾に表示。フォルダーが空の場合は従来通りフラットリスト表示（UXの互換性維持）。

### §6.9 殿の個人PF保護

本変更はDB書き込み操作なし（表示のみ）。殿の個人PF35体に影響なし。
