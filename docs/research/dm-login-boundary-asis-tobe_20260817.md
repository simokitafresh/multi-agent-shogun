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

## ToBe **v0.3** — 2026-08-17 09:15+09:00（v0.2=01:15。09:10-09:13 殿チャットで第0段の前提2点を追加）

- `/login` ルートを境界にする。未認証はデータfetchを走らせない（ルートガード）。**初期形はviewer(当月クーポン=noteパスワード)入力+ブラックアウト中の案内のみ**（現時点の動線はnoteのみ・殿 01:48）。Google/magic linkは第1段で追加。**adminログインは一般`/login`から分離**し `/admin` 配下の別画面（リンクなし・バンドルにadmin切替なし）。
- 認証成功／ログアウトのたびに **ハードリセット**（データ層・store・localStorage/sessionStorage全消去）してから遷移。
- キャッシュキー = `[主体(tier/token hash), endpoint, params]`。別主体は別キー。
- tier依存APIは `Cache-Control: private, no-store` またはETagを主体込みで生成。
- ハードリセットの対象は AsIs 表の全層: React state/Context・handoff sessionStorage・localStorage/IndexedDB(api-cache/ETag)・**Service Worker CacheStorage（`caches.delete` または SW側で主体scope付きキー）**。
- `SignalsProvider` の handoff 適用は **認証主体の確定後**にし、主体が保存時と異なれば捨てる（handoff に主体を焼く）。
- backend: `generate_etag` の入力に主体(tier_id/is_admin/visible_ids)を含める（compare_returns の TTL key と同じ考え方）か、tier依存18 endpointは `no-store`。
- 合否（各実装手の二値）: admin→ログアウト→低tier再ログインで、非公開PFがリロードなしに表示されない。
- **パスワード・tier・expires_atは第0段で変更しない**（殿09:10「現在のパスワードは変更しないままでできる？」→ できる）。第0段が触るのはfrontendの認証切替の形と7層の保持層・キャッシュキー・ETag入力のみ。値はbackend DB `viewer_tiers`系＋Render env（=SSOT、L249）にあり、`api.verifyViewer` も不変。着手前にtier別（tier_name/password/expires_at/updated_at）をread-only snapshotとして残す（保険。復元が要る事態は設計上起きない想定。復元時は `expires_at` をそのまま書き戻し、rotation再実行・再発行をしない）。
- **既存ログイン中ユーザーが1回ログアウト状態になるのは許容**（殿09:13「一回ログアウト状態は問題がない」）。∴ viewer tokenのlocalStorageキー名/形式は第0段で自由に変えてよい（主体入りキーへ移行可）。ユーザーは同じ当月パスワードを再入力すれば復帰＝パスワード変更ではない。
- 注意: `dm-signal-password-rotation` cronは毎月1日16:00 UTC（JST 2日01:00・既知の+1日ズレ、ops §901）に全tierを回す。作業が9/2 01:00 JSTをまたぐと第0段と無関係にパスワードは変わる。

### 第0段の実装単位（案・09:15）— 各1体×1層・可逆・push/deployは家老レーン・本番CDPは殿判断
| 手 | 内容 | 合否(二値) |
|---|---|---|
| ① | `/login`ルート新設（viewer=当月クーポン入力＋ブラックアウト中案内のみ）＋adminログインを`/admin`配下の別画面へ分離（一般UIからリンクなし・公開バンドルにadmin切替なし）。未認証はデータfetchを走らせないルートガード | 一般バンドルにadmin切替UIが0件／未認証で`/`を開くと`/login`へ／adminは`/admin/login`のみ |
| ② | 認証成功・ログアウト・主体切替のたびに7層ハードリセット（React state/Context・handoff sessionStorage・localStorage/IndexedDB api-cache+ETag・SW CacheStorage `caches.delete`）→遷移。handoffは主体確定後に適用し不一致なら捨てる | admin→logout→低tier再ログインで非公開PFがリロードなしに表示されない |
| ③ | キャッシュキー=`[主体(tier/token hash), endpoint, params]` 全層統一＋backend `generate_etag`入力に主体（or tier依存18 endpointを`no-store`） | 別tierで同endpointの304が成立しない（ETag不一致 or no-store） |


## この境界の上に積むもの — 2026-08-17 01:38+09:00（殿とのチャット合意 00:56〜01:11・実装は殿の合図まで行わない）

- **第0段（本書）**: /login境界 + 7層ハードリセット + handoff/キャッシュキーに主体 + ETag入力に主体 or no-store。identity導入前でも必要。
- **第1段 identity + entitlement**（認証方式はチャット合意 01:20〜01:24）: **identityの正=DM-Signal側の `user_id`**。ログイン手段(プロバイダ)は user_id に紐づく「入口」にすぎず、entitlement(クーポン引き換え/Stripe)は必ず user_id に乗せる（プロバイダを後から足しても外しても権利は動かない）。入口の初期セット=**Google OAuth**（rebalancerで稼働中の実装・設定を流用）+ **magic link**（メールだけでログイン: 一回限り・数分失効の署名付きURLをメールへ送り、クリックで検証・セッション発行。Googleを持たない/使いたくないnote読者の受け皿。SPF/DKIM整備・迷惑メール問い合わせは前提）。メール+パスワードは認証基盤側で有効化できるなら併設可だが、初期は2択に絞り要望で開ける（選択肢が増えるほど問い合わせも増える）。Apple はiOSアプリ化を考える時に必須、X/LINE は読者動線次第。同一人物が別プロバイダで別アカウントにならないようメールで名寄せ。**認証基盤はrebalancerと同じもの**に乗せる（方式差より基盤の一本化がコストを決める。現物確認1手で確定）。`entitlement(user_id, tier, valid_until)` を可視性判定の正にする（API側は `valid_until > now`）。admin は role として同じidentityの上へ。
- **noteの月次パスワードは「その月だけ使えるクーポンコード」に置き換える**（殿案 01:00・合意）: `coupon(code, tier, valid_month)` を当月のnote記事に載せる → ログイン済みアカウントが引き換え → `valid_until=当月末+猶予`。同一アカウントは同一コードを1回。翌月は新コード＝noteの月額課金と同期。途中参加は当月末まで、退会は翌月コードを引き換えられないだけ、複数tierは(account,tier)ごとに独立（包含はtier包含表）。
- **クーポンは一般形で設計する**（殿案 01:26「期間限定のクーポンコード（パスワード）で広告が打ちやすくなる。試してもらうまでのハードルが今は高い」）: `coupon(code, tier, valid_from, valid_until, grant_rule, max_redemptions?, source_tag)`。用途はパラメータの違いだけ — note月次(月初〜月末・当月末まで付与・上限なし) / 広告お試し(キャンペーン期間・引き換えから14日等・先着N名=根拠ある上限・1アカウント1回) / 招待・インフルエンサー(出所タグで流入→Stripe転換を計測)。導線は「広告リンク(`?code=`埋め込み)→Googleでログイン→コード自動適用→即閲覧」の1〜2段。Stripe導入後は同じアカウントで「お試し→課金」を接続。
- **redeem_limit（引き換え上限）は置かない**（殿指摘 01:11: 複数tier加入・月途中の参加/退会・noteから購読者数が取れない）。共有への対策は「測る（コード別引き換えアカウント数の可視化）・重くする（本人アカウント1回・同時ログイン数上限は検討可）・失効できる（アカウント単位）」の3つ。
- **tierは既定**（殿裁定2026-05-10 tier_plan_mapping・可視性はtierごとの独立集合=cmd_3837/3839）。identity化後も (user_id, tier, position_month) を複数行持ち、可視性は保有tierの可視集合の和集合。包含は導入しない。
- **entitlementの単位はポジション月**（殿裁定 01:36）: `entitlement(user_id, tier, position_month)`。可視性=対象データの position_month ≤ 引き換え/課金済みの月。翌月ポジション（当月最終取引日の終値で確定）はM+1の権利保有者のみ。暦日grace不要。
- **ブラックアウト窓**（殿裁定 01:40）: 当月権利は**当月最終取引日 JST 00:00 に失効**（現行はadminの `custom_expiry` 運用で実現。identity化では既定として実装）。効果=翌月ポジション保護／誰もログインしていないメンテナンス窓／「当月結果を見たい」更新動機。最終取引日の算出元=現行運用は「月末の最終平日(土日除く)」(殿 01:46)。将来は米国市場の営業日カレンダーを**有効期限専用**に使う可能性あり(DM-Signalの計算系には使わない)。独立関数として分離、最終決定は保留。
- **同時ログイン端末数=5/アカウント**（殿裁定 01:36）。家族共有は禁止。超過時は最古セッション失効を既定案。
- **移行しない・恒久並走**（殿裁定 01:36）: note月次クーポン(日本語コミュニティ)とStripe(海外展開)は恒久的に両立。供給源2つ、判定は共通。
- **第2段 Stripe**: Checkout/Portal + webhook（署名検証・冪等）→ 同じ entitlement(position_month) を付与。判定ロジックは共通。海外展開向け。
- **横断のセキュリティ**: token は httpOnly cookie（短寿命access+refresh）、ログインrate limit、監査ログ、admin 2FA/role化。現行のtier別共有パスワードは「毎月失効する共有秘密」であり、失効の意図は正しく、弱いのは「共有」だけ。

## 裁定の因果連鎖 — なぜその判断か（追体験用・他LLM/他者との共通前提）— 2026-08-17 01:45+09:00

> 殿 01:42「全てには因果がある。なぜその判断を俺が選んだかという裏側の因果を明確にしておくと、議論がぶれにくいし追体験によって他のLLMや他の人間にも前提情報として共通理解ができる」。以後の裁定は必ず「事実 → 制約 → 判断 → 効果」の連鎖で記す。

| 裁定 | 事実（起点） | 制約 | 判断 | 効果（狙い） | Obsidian因果 |
|---|---|---|---|---|---|
| ログインページ＝境界装置 | admin→logout→低tierで非公開PFのキャッシュが見え、reloadまで直らない（殿観測 00:26） | 認証は同一SPAツリー内で切り替わり(admin)、7層の保持層のうち5層は主体なしで残る（cmd_4322現物） | 「画面」ではなく**認証主体が変わる瞬間に全部捨てる境界**を構造で強制。/loginルート+7層ハードリセット+主体入りキー+ETagに主体 | tier境界のデータ漏れをユーザーの操作(reload)に依存させない | [[殿観測_低tier再ログインで非公開PFキャッシュ_20260817]] -> [[認証切替とデータ層の分離不全]] -> [[ログイン境界=構造強制]] |
| identityの正＝DM-Signalのuser_id | 決済(Stripe)は「誰が・どのtierを・いつまで」が中核。noteの共有パスワードでは顧客と結び付かない | プロバイダ(Google/Apple/X…)は増減する。同一人物が別プロバイダで別人になる | プロバイダは「入口」、権利は必ずuser_idに乗せる。入口=Google(rebalancer流用)+magic link、メールで名寄せ | 入口を足しても外しても権利が動かない／Stripeとnoteが同じ表に落ちる | [[Stripe=entitlementが中核]] -> [[identity先行]] -> [[user_id正・プロバイダは入口]] |
| noteは移行せず恒久並走 | Stripe=今後の海外展開、note=日本人向けコミュニティ（殿 01:36） | noteをやめるメリットがほぼ無い。note側にwebhookは無い | 供給源を2つ(noteクーポン/Stripe)持ち、判定(entitlement)は共通 | 既存コミュニティを壊さず海外を足せる | [[note=日本コミュニティ]] + [[Stripe=海外]] -> [[恒久並走・判定共通]] |
| tierコード＝当月限りクーポン | noteは月額課金で毎月パスワード発行＝有効期限の実装（殿 01:00） | 共有秘密の弱さ(誰が使ったか不明・個別失効不可)だけを消したい。月次運用は変えたくない | パスワードを「その月だけ引き換え可能なクーポン」に置換。本人アカウントで1回引き換え | 運用は今と同じ、共有が「測れる・重くなる・失効できる」に変わる | [[毎月失効する共有秘密]] -> [[共有だけを消す]] -> [[当月限りクーポン]] |
| redeem_limitを置かない | 複数tier加入・月途中の参加/退会・noteから購読者数が取れない（殿 01:11） | 上限は根拠のない数字になり正当な購読者を弾く偽陽性を生む | 弾く方向を捨て、測る(可視化)/重くする(本人1回・端末上限)/失効できる(アカウント単位)へ | noteから取れない情報に依存しない | [[noteから購読者数が取れない]] -> [[上限=偽陽性]] -> [[測る重くする失効]] |
| 家族禁止・同時端末上限5台 | 想定はスマホ+PCの2台（殿 01:36） | 上限を厳しくすると問い合わせと面倒が増える | 5台なら実質誰も届かず、家族共有(禁止)は抑止できる | 面倒を増やさず共有を重くする | [[想定2台]] -> [[実質上限に届かない5台]] |
| entitlementはポジション月 | 当月内でも価格が揃えば翌月ポジションが見える。翌月ポジションは翌月分を払った人だけ（殿 01:36） | 暦日で期限を持つと月末営業日のズレやgraceの議論が発生する | 権利を暦日でなく `position_month` で持つ。可視性=position_month ≤ 権利月 | 保護対象(翌月ポジション)と権利が1:1になる | [[翌月ポジション=翌月料金]] -> [[暦日でなくポジション月]] |
| ブラックアウト窓（最終取引日JST00:00失効） | 現行運用は月末最終取引日の0:00にパスワードを失効（殿 01:40。現物: 既定は暦月末、adminのcustom_expiryで実現） | 翌月ポジションが最終取引日の終値で確定する | 当月権利は最終取引日00:00で切る。次の権利で再開 | (1)翌月ポジション保護 (2)誰もログインしていないメンテナンス窓 (3)「当月結果を見たい」更新動機 | [[最終取引日終値で翌月確定]] -> [[00:00失効]] -> [[保護+メンテ窓+更新動機]] |
| クーポンは一般形 | 広告を打ちたいが、今は「noteを買う→パスワードを見る→入力」で試すまでのハードルが高い（殿 01:26） | note月次/広告お試し/招待を別機構にすると車輪が増える | coupon(code,tier,valid_from,valid_until,grant_rule,max_redemptions?,source_tag)。導線=リンク(?code=)→Google1タップ→自動適用 | 用途差はパラメータだけ、出所タグで転換を計測 | [[試すまでのハードル]] -> [[クーポン一般形]] -> [[広告導線1-2段]] |
| tierは既定を踏襲（包含なし） | tier_plan_mapping(殿裁定2026-05-10)と可視性=tierごとの独立集合(cmd_3837/3839)が既にある | 想像で包含関係を作らない（殿 01:38「想像するな」） | (user_id,tier,position_month)を複数行、可視性=保有tierの和集合 | 既存の可視性実装をそのまま乗せる | [[tier_plan_mapping_20260510]] + [[tier別可視性完成形]] -> [[独立集合の和集合]] |
| 最終取引日の算出元（保留） | 現行adminは月末の最終平日(土日除く)で期限を決めている（殿 01:46）。祝日ズレはレア | 米国市場カレンダーを使うならDM-Signalの計算系とは分離し「有効期限専用」に限定（計算不変量に触れない） | 既定=最終平日、将来=NYSE営業日カレンダー(期限専用)へ差替え可能な独立関数にする。最終決定は今しない | 期限だけ精密化でき、計算契約は不変 | [[最終平日=現行運用]] -> [[期限専用カレンダー分離]] -> [[NYSE営業日は将来差替え]] |
| adminログインは一般UIから分離 | 一般向けモーダルにViewer/Admin切替が同居し、adminの存在が露出（cmd_4322現物） | 現時点の一般動線はnoteのみ。露出は攻撃面とUIノイズ。隠すだけでは防御にならない | 一般`/login`=viewer(当月クーポン)のみ。adminは`/admin`配下の別ログイン、リンクなし、バンドルにadmin切替なし。実防御は認証側 | 攻撃面縮小+一般UIの単純化、第0段の同一改修点で手戻りなし | [[殿裁定_設定画面は別ページ_20260628]] -> [[admin露出の除去]] -> [[/login=viewer専用]] |
| 実装は殿の合図まで入らない | 08-16に方針4転と復旧2回（LS120/LS099 detail_2） | 設計が固まる前の実装は手戻りが長い | チャットで因果を固め、設計書へ都度焼き、cmdはread-only棚卸しのみ | 車輪の再発明と手戻りを防ぐ | [[方針4転_20260816]] -> [[設計を固めてから1手ずつ]] |

## チャット記録（殿×将軍・要旨・時系列。車輪の再発明防止のため原則ここに残す）— 2026-08-17 01:38+09:00

| 時刻(JST) | 殿の問い | 将軍の回答の要旨 | 合意/裁定 |
|---|---|---|---|
| 00:26 | ログインページを作るのはどうか。admin→logout→低tierで非公開PFのキャッシュが見え、リロードが要る | 症状の本体は「認証は切り替わるがデータ層が同一ツリーで生き残る」tier境界のデータ漏れ。ログインページは境界を構造で強制する器。同時に (1)キャッシュキーに主体 (2)tier依存APIは no-store/ETagに主体、が必要 | チャット。実装なし |
| 00:28 | AsIs/ToBeのイメージをartifactで | artifact 1c498f5f 作成（01:15に現物版へ更新） | — |
| 00:42 | 実装に入らず手を進めよう | 設計書起草(本書 v0.1)+cmd_4322 read-only棚卸し配備 → 01:11 GATE CLEAR → AsIs v1.0 | — |
| 00:56 | セキュリティ面は？ログイン画面は作る方がよいか？Stripe導入も考えている。noteのtier別パスワード公開だけでなくGoogle loginも？rebalancerでは導入済み | ログイン画面は作るべきだが目的は「identity(本人性)」。現行=共有秘密(誰が使っているか不明・個別失効不可・漏れたら全員)。Stripeは entitlement(user×tier×valid_until) が中核でidentityが前提。Google loginはrebalancer流用+magic link併設。順序=第0段(境界)→第1段(identity+entitlement)→第2段(Stripe)、横断でhttpOnly cookie/rate limit/監査/admin role | 方向合意 |
| 01:00 | noteは月額課金で毎月パスワード発行=有効期限のため | 現行は「毎月失効する共有秘密」で失効の意図は正しく、弱いのは「共有」だけ。identity化しても entitlement の valid_until=月末(+猶予) で同じ意図を保てる。noteの月次パスワードは「今月のtierコード」として残し引き換え | 合意 |
| 01:00 | tierコードは「その月だけ使えるクーポンコード」にするイメージは？ | 最もきれい。coupon(code,tier,valid_month)、ログイン済みアカウントで1回引き換え、当月末まで付与、翌月は新コード=noteの月額課金と同期。Stripeは同じentitlementを直接延長 | **合意（クーポンモデル確定）** |
| 01:11 | redeem_limitは複数tier加入・月途中の参加/退会・noteから購読者数が取れないため無理 | redeem_limitは捨てる。共有対策=測る(コード別引き換え数可視化)/重くする(本人アカウント1回・同時ログイン数上限は検討可)/失効できる(アカウント単位)。途中参加=当月末まで、退会=翌月コード不可、複数tier=(user,tier)独立 | **合意（上限なし）** |
| 01:20 | magic linkとは？ | パスワードなしのメールログイン(一回限り・数分失効の署名付きURL)。Googleを持たないnote読者の受け皿。SPF/DKIM・迷惑メール・短寿命が注意点 | — |
| 01:22 | メール+パスワードは？管理コストは？magic linkはスタンダードか？ | 管理コストは方式差より「認証基盤に乗るか自前か」で決まる。基盤(Supabase Auth等)ならGoogle/magic link/パスワードはトグル差。自前ならパスワードが最も高コスト。magic linkはB2Cサブスクで標準化しつつある。推薦=Google+magic linkの2択で開始、パスワードは要望で開ける。決めるべきは「rebalancerと同じ基盤か」 | 方向合意 |
| 01:23 | 他サービスのログイン(ソーシャルログイン)は？ | 良い。パスワードを預からない・摩擦最小・rebalancerのGoogle OAuth流用。注意=プロバイダごとの登録/審査、別プロバイダで別アカウント化(メールで名寄せ)、プロバイダ障害(メール系を1本残す)。読者層ならGoogle(+Apple)で十分、X/LINEは動線次第。**identityの正はDM-Signalのuser_id**、プロバイダは入口 | 合意 |
| 01:26 | 期間限定のクーポンコード設定もできるか？広告が打ちやすい。試すまでのハードルが今は高い | できる。クーポンを一般形(期間・付与ルール・上限・出所タグ)にすれば、note月次/広告お試し/招待が同じ表・同じフロー。導線=広告リンク(?code=)→Google1タップ→自動適用→即閲覧。Stripe後は同じアカウントでお試し→課金 | 合意 |
| 01:28 | チャット内容は設計書に残そう(車輪の再発明防止) | 本表を新設し以後のチャットも追記する | — |
| 01:31 | 将軍から殿へ質問6点(移行/アカウント粒度/猶予/tier包含/Stripe商品/認証基盤)+admin人数 | — | 殿回答は次行以降 |
| 01:36 | (1)移行: **移行せず半永久的に並走**。理由=Stripeは今後の海外展開向け、noteは日本人向けコミュニティでやめるメリットがほぼない | note月次クーポン方式とStripe方式は恒久的に両立させる設計にする（entitlementの供給源が2つ、判定は共通） | **裁定** |
| 01:36 | (2)家族共有は禁止。複数端末の同時利用は想定外だが、スマホ+PCの2台をイメージし**上限5台**にしておけば実質誰も届かず面倒が減る | 同時ログイン端末数上限=5(アカウント単位)。超過時の挙動は最古セッションの失効を既定案とする | **裁定(上限5台)** |
| 01:36 | (3)クーポンの期限は月末ではなく**月の最終取引日まで**。ポイント=当月内でも価格データが揃えば**翌月のポジションが見える**。翌月のポジションは翌月の料金を払った人だけ | 有効期限を暦日ではなく**「ポジション月」で持つ**のが本質: `entitlement(user_id, tier, position_month)`。可視性=「その行のposition_month ≤ 引き換え済みの月」。当月クーポンは当月ポジションまで、月末最終取引日の終値で計算される翌月ポジションはM+1クーポン(またはStripe当月分)保有者のみ。暦日のgraceは不要になり、月末営業日ズレの問題も消える | **裁定(最終取引日・ポジション月基準)** |
| 01:36 | まずはここまで検討 | 残る質問=(4)tier包含 (5)Stripe商品設計・お試し日数 (6)認証基盤=rebalancer同一でよいか、adminは殿1人か | 保留 |
| 01:38 | tierは既存の情報を確認せよ。想像するな | 既定を現物で確認: **tier_plan_mapping(殿裁定2026-05-10, projects/dm-signal.yaml)**= Basic(¥1,000 初月無料・公開)/AddOn 裏・Ave7(¥2,000・非公開)/Standard=古参¥4,000・非公開/NewStandard=¥8,000・公開/premium=ドクタープレミアム¥20,000招待制/劇薬DM¥30,000はdb_tier無し。**可視性=tierごとの独立集合**(`tier_visibility_settings.portfolio_settings`+global+folder非表示、閲覧EP18箇所 `check_hide_portfolio_or_folder`、cmd_3837/3839・note対応表準拠 2026-07-10)。AddOnは追加購読=複数tier同時保有が前提。∴ tier包含の新裁定は不要: entitlementは(user_id,tier,position_month)を複数行、可視性=保有tierの可視集合の和集合 | 既定確認(新裁定なし) |
| 01:40 | noteのパスワードはDM-Signal側で**月末の最終取引日の深夜0:00に失効**させている。効果=(1)一定期間誰もログインできない=メンテナンス時間 (2)当月結果を確認したい心理を刺激 | 現物: `password_rotation.py`既定は暦月末(`get_current_month_end`、当日有効・翌日JST00:00失効 `timezone.py:32-43`)、`viewer_tiers.py:317` `custom_expiry` でadminが任意期限を指定可=意図は運用で実現、既定には未焼込。設計要件として固定: **ブラックアウト窓**=当月最終取引日 JST 00:00 失効〜翌月権利で再開。entitlement(position_month)の可視期間=前月最終取引日00:00〜当月最終取引日00:00。効果3つ(翌月ポジション保護/メンテ窓/更新動機)を明文化。残論点=「最終取引日」の算出元(価格データ営業日 or 取引所カレンダー)。殿の現行基準に従う | **裁定(ブラックアウト窓)** |
| 01:46 | 現在adminで期限を決める基準=**月末の最終平日(土日除く)**。祝日や特殊パターンはレアなので簡略。できれば**米国市場の営業日カレンダー**を使いたいが、それはDM-Signalの計算には使わず**パスワード有効期限専用**。現時点で最終決定は不要 | 因果=(事実)祝日ズレはレア (制約)計算系のカレンダー契約と混ぜたくない (判断)期限専用のカレンダー関数として分離、既定は最終平日、将来NYSE営業日へ差替え可 (効果)計算不変量を汚さずに期限だけ精密化できる。設計書に「未決(保留)」として記録 | 保留(最終決定不要) |
| 09:10-09:13 | 現在のパスワードは変更しないままでできる？難しければtier別パスワードを保存し改良後に戻す（有効期限が変わらないよう注意）。一回ログアウト状態は問題がない | 第0段はfrontendの境界・保持層・キーの改修で、パスワード/tier/expires_atはbackend DB+Render env(SSOT)にあり触らない。唯一の副作用はtokenキー変更時の再ログイン | rotation cronは月初(JST 2日01:00)に走る。復元するならexpires_atは書き戻すのみで再発行しない | パスワード不変で第0段を実施。tokenキー/形式は変えてよい（再ログイン許容）。着手前にtier別snapshotをread-onlyで保存 | 手戻りゼロ・利用者体験はほぼ不変・復元手段は保険として持つ | `[[殿質問_パスワード不変で第0段可能か_20260817]] -> [[第0段は認証後のデータ隔離とUI入口]] -> [[パスワード不変+再ログイン許容]]` |
| 01:48 | 現時点の動線はnoteのみ。ログインページができればいい。admin認証のポップアップは一般には出ないのがいいよな？ | 同感。現状は`viewer-auth-modal.tsx:97-150`にViewer/Admin切替が同居=adminの存在が一般UIに露出。あるべき形=一般`/login`はviewer(当月クーポン)のみ、adminは`/admin`配下に自分のログイン画面・一般UIからリンクなし・公開バンドルにadmin切替を含めない(殿裁定2026-06-28「設定画面は別ページ、リンクなしで/admin」と同方向)。隠すのは露出削減であって防御ではない=実防御は認証側(rate limit・将来role/2FA)。第0段の同じ改修点なので一緒にやる | **合意** |


- 09:10 殿「artifact 1c498f5f の続きをやろう。まずはチャット。現在のパスワードは変更しないままでできる？難しいなら現在のtier別のパスワードを保存して改良後に戻してもいい。有効期限が変わらないよう気を付けないと」
- 09:12 将軍: できる。第0段はfrontendの境界/保持層/キー改修でパスワード・tier・expires_atはbackend SSOTにあり触らない。唯一の副作用=tokenキー変更時の再ログイン。保険にtier別read-only snapshot。rotation cron(9/2 01:00 JST)をまたぐと別要因で変わる。実装単位①/login+admin分離 ②7層リセット ③主体キー/ETagの3手案
- 09:13 殿「では設計書とアーティファクトを更新しよう。一回ログアウト状態は問題がない」→ ToBe v0.3（パスワード不変・再ログイン許容・3手案）

## 注釈 — 2026-08-17 01:30+09:00

- AsIs注釈: v1.0 は cmd_4322 の一次証跡（rg/nl による現物読解、行番号付き）で置換済み。SW `dm-signal-v10` と handoff sessionStorage が「主体なし・logoutで消えない」二重の抜け穴。
- ToBe注釈: ログインページはUIではなく「境界装置」。モーダル方式では消し忘れが意志依存になる。
