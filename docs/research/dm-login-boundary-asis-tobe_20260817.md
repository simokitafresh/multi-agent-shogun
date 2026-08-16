<!-- gist-master: 0d23e0c34127527dd9031aa7fd9ac269 dm-login-boundary-asis-tobe_20260817.md -->
# ログイン境界 AsIs/ToBe — tier境界のデータ漏れを構造で塞ぐ

## 原則（親文書と同じ。殿裁定 2026-08-15）

- ToBeは構造的に不可能でない限り妥協しない。AsIsは現実のコードそのもの。変更履歴は書かない（見出し=版+タイムスタンプ、粒度は末尾注釈）。
- 実装は殿の指示まで行わない（2026-08-17 00:26 殿「これは実装の話ではなくチャット」／00:42「まだ実装には入らず手を進めよう」）。

発端: 殿観測 2026-08-17 00:26 — admin認証→ログアウト→低tierで再ログインすると本来見えないPFのキャッシュが表示され、リロードするまで直らない。
イメージ図: https://claude.ai/code/artifact/1c498f5f-100f-447a-90ce-75d389a51904

## AsIs **v1.0** — 2026-08-17 01:15+09:00（cmd_4322 read-only棚卸し・飛猿報告 `queue/reports/tobisaru_report_cmd_4322.yaml`・軍師APPROVE・GATE CLEAR 01:11）

**AsIs契約表**（現物。行番号は2026-08-17時点の frontend/backend）

| 層 | 現物（ファイル/関数） | 認証切替の形 | キャッシュキーに主体を含むか | ログアウト時に消えるか |
|---|---|---|---|---|
| 認証(admin) | `frontend/components/viewer-auth-modal.tsx:97-150`(入力切替) → `adminAuth.login` → `api.adminLogin`(POST /api/admin/login, Basic) → localStorage `admin_session_active` → `AdminAuthProvider.login` → `refreshPortfolios` | **同一ツリー内のstate切替**（遷移なし） | — | logoutは `api.logout`(server cookie削除)+`admin_session_active/admin_user/admin_pass`+viewer token削除+auth event dispatch+AdminAuthContext/useAdminPageのReact state空化。**apiCache・ETag・handoff sessionStorage・Service Worker CacheStorage・selected_portfolio_id は消さない** |
| 認証(viewer) | `api.verifyViewer` → `viewerAuth.saveToken`(localStorage `dm_viewer_token`: token/expires/tier_name) → `window.location.reload` | **full document reload**（ツリー再生成あり） | — | `viewerAuth.clearToken`+reloadのみ。sessionStorage/IndexedDB/SWは残る |
| データ層(1) | Signals/ViewerPermissions/AdminAuth の React state/Context | — | **含まない**（キーなし） | React stateはreloadで消える。admin logoutは同一ツリー内なので残り得る |
| データ層(2) | signals handoff `sessionStorage` key=`dm-signal-signals-handoff-cache` | — | **含まない**（tier/token/userなし） | **消えない**（logout・reloadとも） |
| データ層(3) | localStorage `selected_portfolio_id`/folder filter/execution_timing/auth flags/token | — | データキャッシュではない（設定・フラグ） | tokenのみ消える |
| データ層(4) | api-cache Map + IndexedDB responses + manifest（`lib/api-cache.ts`） | — | **tierは含む**（`admin::endpoint` / `viewer:<tier>::endpoint`）、token/userは含まない | **消えない**（scope=adminの永続cacheが残る） |
| データ層(5) | ETag Map + IndexedDB etags | — | 同上scope（tier有、token/user無） | **消えない** |
| データ層(6) | Service Worker `dm-signal-v10` の API URL match/put | — | **含まない**（URLのみ） | **消えない** |
| データ層(7) | ブラウザ private HTTP cache（`Cache-Control: private, max-age=N`） | — | **Varyに主体なし** | ブラウザ依存 |
| HTTP(backend) | `backend/app/utils/etag.py:15-69` `generate_etag`=sort済みresponse dataのMD5のみ、`check_etag_match`=If-None-Matchと生成ETagの比較のみ。`make_response_with_etag` 利用=tier依存18 endpoint（各handlerはtier_idでvisibility/maskingを計算するがETag utilityへ主体は渡らない）。`compare_returns` のserver TTL keyだけは tier_id/is_admin/visible_ids を含む | — | ETag=**主体なし**、Cache-Control=**主体なし** → **別tier由来の同一ETagで304が成立する** | — |

**漏れの因果列（現物名のみ）**: admin取得データが React Context・handoff sessionStorage・Service Worker URL cache・scope=admin の api-cache/ETag に残る → admin logout は cookie/flags と React admin state を落とすだけで handoff/SW/永続cache を破棄しない → 低tier token 保存+reload 後、`SignalsProvider` が**認証確認前に handoff を適用**し、Service Worker も同一URLの stale response を返せる → 低tier の network response が届く前に admin 時の非公開PFが表示され得る。**reloadで直る理由**: React state/memory が再生成され fresh な低tier request が走り、その応答が勝てば表示が更新される。ただし sessionStorage/IndexedDB/SW は reload では消えないため「勝てなければ残る」。

**確認できた事実**: SWR/QueryClient 実装は0件。認証切替はadmin=同一ツリー／viewer=reloadの二値。tier依存ETag endpoint=18。コード変更0・本番操作0（読み取りのみ）。

## ToBe **v0.2** — 2026-08-17 01:15+09:00

- `/login` ルートを境界にする。未認証はデータfetchを走らせない（ルートガード）。
- 認証成功／ログアウトのたびに **ハードリセット**（データ層・store・localStorage/sessionStorage全消去）してから遷移。
- キャッシュキー = `[主体(tier/token hash), endpoint, params]`。別主体は別キー。
- tier依存APIは `Cache-Control: private, no-store` またはETagを主体込みで生成。
- ハードリセットの対象は AsIs 表の全層: React state/Context・handoff sessionStorage・localStorage/IndexedDB(api-cache/ETag)・**Service Worker CacheStorage（`caches.delete` または SW側で主体scope付きキー）**。
- `SignalsProvider` の handoff 適用は **認証主体の確定後**にし、主体が保存時と異なれば捨てる（handoff に主体を焼く）。
- backend: `generate_etag` の入力に主体(tier_id/is_admin/visible_ids)を含める（compare_returns の TTL key と同じ考え方）か、tier依存18 endpointは `no-store`。
- 合否（各実装手の二値）: admin→ログアウト→低tier再ログインで、非公開PFがリロードなしに表示されない。

## この境界の上に積むもの — 2026-08-17 01:20+09:00（殿とのチャット合意 00:56〜01:11・実装は殿の合図まで行わない）

- **第0段（本書）**: /login境界 + 7層ハードリセット + handoff/キャッシュキーに主体 + ETag入力に主体 or no-store。identity導入前でも必要。
- **第1段 identity + entitlement**: Google login + magic link（rebalancerの既存実装・流儀を流用）。`entitlement(account, tier, valid_until)` を可視性判定の正にする（API側は `valid_until > now`）。admin は role として同じidentityの上へ。
- **noteの月次パスワードは「その月だけ使えるクーポンコード」に置き換える**（殿案 01:00・合意）: `coupon(code, tier, valid_month)` を当月のnote記事に載せる → ログイン済みアカウントが引き換え → `valid_until=当月末+猶予`。同一アカウントは同一コードを1回。翌月は新コード＝noteの月額課金と同期。途中参加は当月末まで、退会は翌月コードを引き換えられないだけ、複数tierは(account,tier)ごとに独立（包含はtier包含表）。
- **redeem_limit（引き換え上限）は置かない**（殿指摘 01:11: 複数tier加入・月途中の参加/退会・noteから購読者数が取れない）。共有への対策は「測る（コード別引き換えアカウント数の可視化）・重くする（本人アカウント1回・同時ログイン数上限は検討可）・失効できる（アカウント単位）」の3つ。
- **第2段 Stripe**: Checkout/Portal + webhook（署名検証・冪等）→ 同じ entitlement を直接延長。判定ロジックは共通。手動の月次発行はStripe顧客には不要になる。
- **横断のセキュリティ**: token は httpOnly cookie（短寿命access+refresh）、ログインrate limit、監査ログ、admin 2FA/role化。現行のtier別共有パスワードは「毎月失効する共有秘密」であり、失効の意図は正しく、弱いのは「共有」だけ。

## 注釈 — 2026-08-17 01:20+09:00

- AsIs注釈: v1.0 は cmd_4322 の一次証跡（rg/nl による現物読解、行番号付き）で置換済み。SW `dm-signal-v10` と handoff sessionStorage が「主体なし・logoutで消えない」二重の抜け穴。
- ToBe注釈: ログインページはUIではなく「境界装置」。モーダル方式では消し忘れが意志依存になる。
