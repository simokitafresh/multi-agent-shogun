<!-- gist-master: da1b7617d777b62864953792b77d5a78 agent_readiness_level3_roadmap_20260831.md -->
# dm-signal.com Agent Readiness — Level 3 全完了ロードマップ v1.0

- 作成: 2026-08-31 05:25 JST（殿指示 05:22『level3まで全て完了させるためのロードマップをステップバイステップで』）
- 対象: Cloudflare AI Crawl Control › Agent Readiness 診断（殿提示 HTML 2026-08-31 03:15 準拠）
- 現状(13:08 更新): **Level1 5/5**(Markdown for agents ON 13:00、text/markdown 200 実測)・**Level2 3/3**(1-2(a) Link ヘッダ=Transform Rule 13:07 作成、curl -sI で Link 1 件実測)・Level3 1/8(2-1 済。次=cmd 2-2〜2-7、2-8 は Agent Card 後に DNS:Edit 済トークンで即時)（Commerce は optional=本書対象外）
- 前提事実（本番一次確認済み）: LP=Render static (`lp/`, autoDeploy)・BE=FastAPI (`dm-signal-backend.onrender.com`)・Auth=Supabase・zone proxied=ON・保管トークンは Single Redirect+zone read のみ

## 実装原則
1. 静的ファイル（`lp/public/.well-known/*` 等）で済むものは将軍 D0（可逆・push→autoDeploy）。
2. backend 実装を伴うものは cmd 起票（忍者レーン、契約は返却 JSON 例を AC に添付=型十八弾-2）。
3. Cloudflare dashboard 限定操作（トグル/トークン発行）は殿 Step として本書に列挙し、各 Step 後に将軍が curl/API で到達確認。
4. 各 Step の AC は二値。診断 Rescan の ✅ を最終 AC とする。

---

## Phase 0 — Level 1 完了（残 1）
| Step | 内容 | 担当 | AC |
|---|---|---|---|
| 0-1 | Cloudflare dashboard › AI Crawl Control › Optimization › **Markdown for agents** を ON | 殿(1 click) | `curl -H 'Accept: text/markdown' https://dm-signal.com/` の content-type=text/markdown |
| 0-2 | 診断 Rescan | 将軍 | Level1 5/5 |

## Phase 1 — Level 2: Technical Groundwork（3 項目）
| Step | 内容 | 担当 | AC |
|---|---|---|---|
| 1-1 **API Catalog** | `lp/public/.well-known/api-catalog` に RFC 9727 準拠 Linkset JSON を置く（公開 EP のみ: `/api/public/free-coupon`・showcase 系。認証必須 EP は Phase 2 の Protected Resource へ参照） | 将軍 D0 | `curl https://dm-signal.com/.well-known/api-catalog` 200 ∧ JSON valid ∧ 診断 ✅ |
| 1-2 **Link Headers** | 静的サイトはヘッダを足せないため 2 経路: (a) Cloudflare Snippets/Transform Rule で `Link: <https://dm-signal.com/.well-known/api-catalog>; rel="api-catalog"` を付与 (b) HTML `<link rel>` 併記(即日可・D0) | (a)殿→トークン発行後は将軍 API / (b)将軍 D0 | `curl -sI https://dm-signal.com/ | grep -i '^link:'` 1 件以上 ∧ 診断 ✅ |
| 1-3 **Auth.md** | `lp/public/auth.md`(=`/.well-known/auth.md` にも複置) に AI bot 向けログイン手順を記述: Supabase email+password / Google OAuth、Free tier 登録フロー、rate 制約、禁止事項 | 将軍 D0（文面は Free tier 設計書 v3.3 §契約から引用） | `curl https://dm-signal.com/auth.md` 200 ∧ 診断 ✅ |

## Phase 2 — Level 3: Advanced Integration（8 項目・依存順）
### 2A. OAuth 系（基盤。他項目が参照）
| Step | 内容 | 担当 | AC |
|---|---|---|---|
| 2-1 **OAuth Discovery** | `/.well-known/oauth-authorization-server`(RFC 8414) を LP 静的配置。issuer=Supabase project URL、authorization/token/jwks の各 endpoint は Supabase Auth の現物 URL を curl で確認してから記載（想像で書かない） | 将軍 D0（現物確認→JSON） | metadata JSON が RFC 8414 必須キーを持つ ∧ 記載 URL 全てに curl 200 ∧ 診断 ✅ |
| 2-2 **OAuth Protected Resource** | `/.well-known/oauth-protected-resource`(RFC 9728) を配置。resource=`https://dm-signal-backend.onrender.com`、authorization_servers=[2-1 の issuer]、scopes(free/basic/standard/premium/secret=既存 tier) | cmd（backend にも同 EP を実装し LP と同内容。返却 JSON 例を AC 添付） | LP/BE 両方 200 ∧ JSON 一致 ∧ 診断 ✅ |
### 2B. Agent 対話面
| Step | 内容 | 担当 | AC |
|---|---|---|---|
| 2-3 **A2A Agent Card** | `/.well-known/agent-card.json`(A2A 仕様) を配置。name=DM-Signal、skills は 2-4 と同期、認証は 2-1/2-2 を参照。まず読み取り専用 capability(シグナル照会)のみ宣言 | cmd（雛形は将軍が書く） | JSON が A2A スキーマ valid ∧ 診断 ✅ |
| 2-4 **Skills Index** | agent が呼べる操作の索引（例: get_signals/get_monthly_returns/get_deterioration=既存公開 API の写像）を Agent Card の skills 配列+`/.well-known/skills.json` に列挙 | cmd（2-3 と同一 unit） | skills ≥3 件・各 entry に endpoint/入出力例 ∧ 診断 ✅ |
| 2-5 **MCP Server Card** | `/.well-known/mcp.json` に MCP server 情報を配置。実体は backend に `/mcp`(streamable HTTP) を新設し、tools=2-4 の read-only 3 本から開始。認証=Supabase JWT(既存 free-coupon と同方式) | **cmd 2 本**(①backend /mcp 実装+contract test ②card 配置+e2e: MCP client で tools/list 成功) | MCP client(公式 SDK)で tools/list が 3 tools を返す ∧ 診断 ✅ |
### 2C. Bot 身元・実行面
| Step | 内容 | 担当 | AC |
|---|---|---|---|
| 2-6 **Web Bot Auth** | 自サイト発の outbound bot は現状なし → 対象は将来の自動巡回のみ。HTTP Message Signatures(Ed25519) の鍵ペアを生成し `/.well-known/http-message-signatures-directory` に公開鍵を配置（署名運用は bot 新設時に有効化） | cmd（鍵生成+配置+検証 script） | directory 200 ∧ JWKS valid ∧ 診断 ✅ |
| 2-7 **Let AI agents run in-browser tools (WebMCP)** | LP に WebMCP(`navigator.modelContext` polyfill+tool 宣言 1 本=プラン表の照会)を最小実装。Cloudflare の WebMCP ガイドに従い script 1 枚 | cmd（LP のみ・可逆） | 診断 ✅ ∧ ブラウザ console で tool 登録 1 件 |
| 2-8 **DNS-AID** | DNS TXT `_aid.dm-signal.com` に agent discovery レコードを追加（値は 2-3 Agent Card URL）。DNS 編集権限トークン(Zone.DNS Edit)が必要 | 殿(トークン発行 1 回)→以後将軍 API | `dig TXT _aid.dm-signal.com` 1 件 ∧ 診断 ✅ |

## 殿にしか出来ない操作の全列挙（計 3 回）
1. Phase 0-1: Markdown for agents トグル ON（1 click）
2. Phase 1-2(a): Snippets/Transform 用 API トークン発行（または dashboard で Transform Rule 1 本作成）
3. Phase 2-8: Zone.DNS Edit 権限トークン発行（.env.cloudflare へ追記は将軍）

## 順序と目安
- 即日（D0 連続）: 0-1(殿)→1-1→1-3→1-2(b)→2-1 … 静的系は本日中に診断 ✅ 化可能
- cmd レーン: 2-2→2-3+2-4→2-5①→2-5②→2-6→2-7（直列依存は 2-1→2-2→2-3 のみ、他は並走可）
- 2-8 はトークン受領後 5 分
- 完了定義: 診断 Rescan で Level1 5/5・Level2 3/3・Level3 8/8

## リスク・注記
- Level3 は「外部 agent がログインして操作する」面を開く。書き込み系 tool は本ロードマップに含めない（read-only から開始、書き込み解禁は別裁定）。
- 診断は AI 生成の推奨であり項目仕様が変わりうる。各 Step 着手時に Rescan の検査内容を再確認してから実装する（型: 想像せず確認）。
- 進捗台帳: 本書の表に起票 cmd 番号を追記していく（LS086: 設計書クローズ時に未起票照合）。

## 進捗台帳
| Step | 起票/実施 | 状態 |
|---|---|---|
| 0-1 | 殿 ON 13:00→curl text/markdown 200 | done |
| 1-1/1-3/1-2(b)/2-1 | 将軍 D0 予定 | open |
| 2-2〜2-7 | cmd 未起票 | open |
| 1-2(a) | Transform Rule 作成 13:07(Link ヘッダ本番実測) | done |
| 2-8 | トークン権限確保済(DNS:Edit 実測)。Agent Card(2-3)後に投入 | ready |
