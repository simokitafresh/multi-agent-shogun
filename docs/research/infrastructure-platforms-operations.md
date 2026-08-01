
`scripts/lib/field_get.sh` の `_field_get_log()` が全呼出しを `logs/field_deps.tsv` に無条件追記。呼出し元→対象ファイル→フィールドの依存関係を記録する診断用ログ。ローテーション未実装のため無限肥大リスクあり(L243)。

## tmux設定

prefix=Ctrl+A。session=shogun、W1=将軍、W2=agents(家老+軍師+忍者8ペイン)。形式: shogun:agents.{pane}
将軍1+家老1+軍師1+忍者6=全9名。全員Opus 4.6(2026-03-17)。CLI→`config/settings.yaml`

| pane | 名前 | pane | 名前 |
|------|------|------|------|
| 1 | karo | 5 | hanzo |
| 2 | gunshi | 6 | saizo |
| 3 | hayate | 7 | kotaro |
| 4 | kagemaru | 8 | tobisaru |

ペインレベル環境変数は存在しない。ペイン別CLAUDE_CONFIG_DIRはrespawn-pane -e or send-keys注入(L041)。
capture-paneバナー解析: モデル名+バージョン番号の精密パターン必須。コマンドテキスト自体のfalse positiveに注意(L046)。
- L004: pane変数空≠未配備（cmd_092）
- L067: ペイン背景色は@model_name更新と連動していない（cmd_365）
- L068: shutsujin_departure.shが2ファイル存在(root+scripts/)で背景色ロジック不整合（cmd_365）
- L094: scripts/shutsujin_departure.shにモデル名ハードコード残存（cmd_405）
- L105: E2Eテストでtmux pane-base-index依存は明示固定せよ（cmd_438）
- L118: tmux set-optionのtargetがsession指定だとwindow optionが意図せずcurrent windowのみ更新（cmd_468）
- L123: tmuxターゲットにウィンドウINDEXを使用するな — NAME(固有名)を使え（cmd_494）
- L124: paste-bufferの-dフラグはタイムアウト時に発動しない — 明示的delete-buffer必須（cmd_494）
- L125: paste-buffer注入先はagent_id検証で防御せよ(defense-in-depth)（cmd_494）
- L265: shutsujin_departure.shハードコードレイアウト禁止（3原則）（cmd_1139）
- L268: 非連番ペインインデックスにはPANE_IDS配列パターンが有効（cmd_1141）
→ `docs/research/infra-details.md` §6-7

## Claude Code マルチアカウント管理（cmd_313偵察）

- Usage API: `GET https://api.anthropic.com/api/oauth/usage` (OAuth Bearer + `anthropic-beta: oauth-2025-04-20`)
- レスポンス: `five_hour.utilization`(%), `seven_day`, `extra_usage`。read-only、クレジット消費なし
- Profile API: `GET https://api.anthropic.com/api/oauth/profile` → アカウント名・プラン・rate_limit_tier
- 認証保存: `~/.claude/.credentials.json` (claudeAiOauth.accessToken/refreshToken)
- 複数アカウント: `CLAUDE_CONFIG_DIR=~/.claude-{name}` でディレクトリ分離が最も堅牢(L015)
- WSL2+tmux同時監視: HIGH(curl 1本で取得可能、pane別環境変数で2アカウント並行)
- 注意: undocumented API(変更可能性あり)、refresh_tokenは1回限り使用(L016)
- WSL2→API応答5秒超のため監視スクリプトtimeout≥10秒必須(L040)
- L082: Codexは~/.codex/を全エージェント共有。分離機構なし（cmd_390）
- L083: bypass-approvals-and-sandboxフラグ漏れで全操作が権限確認停止（cmd_390）
- L237: OpenAI ChatGPT ProはOAuth認証でAPIキー不要。tmuxペインパース方式では不正確（cmd_995）
→ `docs/research/cmd_314_usage_api_verification.md` / `docs/research/cmd_314_account_switching_procedures.md`

## Google Workspace CLI (gws) — 全PJ共通ツール

`npm i -g @googleworkspace/cli`。Gmail/Drive/Calendar/Sheets/Docs/Chat対応。

**アカウント:**
- デフォルト: `simokitafresh@gmail.com`（殿裁定 2026-04-13）
- サブ: `karasuyama3387@gmail.com`
- 切替: `gws auth switch <email>` or `--account <email>` フラグ
- 設定: `~/.config/gws/accounts.json`

**Sheets操作の注意点:**
- 日本語環境ではシート名が「シート1」（"Sheet1"ではない）。`spreadsheets get`でタブ名を確認してから`values update`
- `values update`は`--params '{"spreadsheetId":"...","range":"シート1!A1","valueInputOption":"USER_ENTERED"}'`
- CSV→2D配列変換は`--json '{"values": [[row1...],[row2...]]}'`
- 新規作成: `gws sheets spreadsheets create --json '{"properties":{"title":"..."}}'`

**Gmail操作（cmd_2900, 2026-05-20）:**
- 認証確認: `gws auth status`だけでログアウト判定するな。暗号化credentials検出漏れで`auth_method: none`でも実APIが通る場合あり。正判定は `gws gmail +triage --max 1 --format json` の成功確認（read-only、実測5.6秒）
- triage: `gws gmail +triage --max 5 --query 'is:unread newer_than:7d' --format table` / ラベル付き確認は `gws gmail +triage --labels --max 10`
- 検索: `gws gmail users messages list --params '{"userId":"me","q":"from:alerts@example.com is:unread","maxResults":10}'`。詳細取得は返却IDで `gws gmail users messages get --params '{"userId":"me","id":"MSG_ID","format":"metadata","metadataHeaders":"Subject"}'`
- フィルタ一覧/取得/削除: `gws gmail users settings filters list --params '{"userId":"me"}'` / `gws gmail users settings filters get --params '{"userId":"me","id":"FILTER_ID"}'` / `gws gmail users settings filters delete --params '{"userId":"me","id":"FILTER_ID"}'`
- フィルタ作成: `gws gmail users settings filters create --params '{"userId":"me"}' --json '{"criteria":{"from":"alerts@example.com","query":"subject:(deploy) newer_than:30d"},"action":{"addLabelIds":["Label_123"],"removeLabelIds":["INBOX"]}}'`。`removeLabelIds:["INBOX"]` がarchive相当。Gmail APIにfilter updateはないため、変更はdelete→create
- メッセージ操作: 既読化は `gws gmail users messages modify --params '{"userId":"me","id":"MSG_ID"}' --json '{"removeLabelIds":["UNREAD"]}'`、archiveは `--json '{"removeLabelIds":["INBOX"]}'`、ラベル付与は `--json '{"addLabelIds":["Label_123"]}'`。破壊操作のdeleteではなく必要ならtrash系を優先

**教訓(auto-ops由来、全PJ適用):**
- L023/L027: Sheets取得は`spreadsheets values get --params`形式が正（+read旧式）
- L028: Drive files get alt=media構文
- L030: Drive files rename/deleteバッチ
- L055: Drive moveはfiles updateのaddParents/removeParents

→ auto-ops固有の経費管理パターンは `context/auto-ops.md §gws CLI` 参照

## Render運用（cmd_2824, 2026-05-17）

推測禁止。コールドスタート仮説を出す前に、対象が `free` web service か、paid web service か、static site かをこの表で判定する。
根拠: Render公式Docs `https://render.com/free` / `https://render.com/docs/faq` / `https://render.com/docs/static-sites/` + `render services --output json` 実測(2026-05-17)。

### プラン別挙動

| 対象 | 挙動 | 障害切り分けでの扱い |
|------|------|----------------------|
| Free web service | 15分無通信でspin down。次のHTTP/WebSocketでspin upし、約1分かかる | 初回遅延/502/503はコールドスタート候補。ただしAPI疎通で確認してから判断 |
| Starter/Standard/Pro web service | Paid instance。Render FAQ上、paid instanceはspin downしない | コールドスタート仮説を採用しない。アプリ/DB/ログ/Render障害を先に見る |
| Static Site | Render Static Site。global CDN配信 | サーバー起動待ちはない。障害はビルド成果物、rewrite、CDN/Render Status、接続先APIを見る |
| Cron Job | スケジュール実行コンテナ | URLなし。失敗時はcron job logs、呼び出し先API、envVars、重複cronを確認 |
| Render Postgres | managed database | API不調時はDB接続/クエリ/容量/メンテナンスを確認。web serviceのcold startとは別物 |

### 障害切り分け手順

1. **API確認**: 対象URLの `/healthz` / `/health` / 主要APIを叩く。Static Siteなら接続先API URLも別に確認する。
2. **DB確認**: APIがDB依存なら `render psql <dpg-id>` またはPJ標準のDB確認手順で接続・代表クエリを確認する。
3. **ログ確認**: `render logs --output text <service-id-or-name>` / cron job logsでアプリ例外、OOM、deploy失敗、env不足を見る。
4. **Renderステータス確認**: 上記で異常が説明できない場合だけ `https://status.render.com/` とDashboardを確認する。

### 全サービス一覧

| 名前 | ID | 種別 | プラン | URL | 状態 |
|------|----|------|--------|-----|------|
| CPCV | `srv-d1map9qli9vc7399sk8g` | web_service | starter | `https://cpcv.onrender.com` | suspended |
| DM-metrics-checker | `srv-d2j03qe3jp1c73bvjnig` | web_service | standard | `https://dm-metrics-checker.onrender.com` | suspended |
| DM-momentum-checker | `srv-d2v8c9vdiees73dsaup0` | web_service | free | `https://dm-momentum-checker.onrender.com` | suspended |
| DualMomentum-Combination | `srv-d1q4hpbipnbc738lhfag` | web_service | starter | `https://dualmomentum-combination.onrender.com` | suspended |
| DualMomentum-Rebalancer | `srv-d1utt3re5dus7399plrg` | web_service | starter | `https://dualmomentum-rebalancer.onrender.com` | not_suspended |
| Kubun-checker | `srv-d10hahe3jp1c73907un0` | static_site | starter | `https://kubun-checker.onrender.com` | not_suspended |
| LP-DM-Standrad | `srv-d20skn95pdvs739dbnig` | static_site | starter | `https://lp-dm-standrad.onrender.com` | not_suspended |
| Legacy_PF_Rebalancer | `srv-d4iih4ili9vc73ej3m50` | web_service | starter | `https://rebalancer-backend-z9qd.onrender.com` | suspended |
| QuickCard | `srv-d1hnmkje5dus7397jth0` | web_service | starter | `https://quickcard-edrr.onrender.com` | not_suspended |
| Real-CPCV | `srv-d1ohqnbipnbc73f2bqqg` | web_service | starter | `https://real-cpcv.onrender.com` | suspended |
| Road-To-S4 | `srv-d1d5t4re5dus73b179ng` | web_service | starter | `https://road-to-s4.onrender.com` | suspended |
| Simple-Dual-Momentum | `srv-d15qgc7diees73ecrk3g` | web_service | starter | `https://simple-dual-momentum.onrender.com` | suspended |
| Simple-OCR | `srv-d1l2gnmmcj7s73bnmfp0` | web_service | starter | `https://simple-ocr.onrender.com` | not_suspended |
| SmartQuiz by Original | `srv-d1ela7be5dus73bj80m0` | web_service | free | `https://smartquiz-ocr.onrender.com` | not_suspended |
| Stockdata-API | `srv-d2psuqbe5dus73bedm2g` | web_service | standard | `https://stockdata-api-6xok.onrender.com` | not_suspended |
| Stockdata-API-daily-update | `crn-d2vqn6buibrs73dla6vg` | cron_job | starter | `-` | not_suspended |
| TEST-dm-signal-backend-lyk3 | `srv-d5ahs0ali9vc73b6tprg` | web_service | standard | `https://test-dm-signal-backend-lyk3.onrender.com` | suspended |
| askul-order | `srv-d0s64ps9c44c73cqpub0` | web_service | starter | `https://askul-order.onrender.com` | not_suspended |
| cafe_fresh | `srv-d0o6uh0dl3ps73aadid0` | static_site | starter | `https://cafe-fresh.onrender.com` | not_suspended |
| classroom-dashboard | `srv-d6hk293h46gs73e99ao0` | static_site | starter | `https://classroom-dashboard-5c2h.onrender.com` | not_suspended |
| dm-chart-backend | `srv-d4enc8pr0fns73br4o30` | web_service | starter | `https://dm-chart-backend.onrender.com` | not_suspended |
| dm-chart-etl | `crn-d4ene6hr0fns73br60a0` | cron_job | starter | `-` | not_suspended |
| dm-chart-frontend | `srv-d4enc8pr0fns73br4o2g` | static_site | starter | `https://dm-chart-frontend.onrender.com` | not_suspended |
| dm-rebalancer-backend | `srv-d4jacrfpm1nc73dudmn0` | web_service | starter | `https://dm-rebalancer-backend.onrender.com` | not_suspended |
| dm-rebalancer-frontend | `srv-d4jacrfpm1nc73dudmmg` | static_site | starter | `https://dm-rebalancer-frontend.onrender.com` | not_suspended |
| dm-signal-backend | `srv-d4ja7q15pdvs739a4q1g` | web_service | pro | `https://dm-signal-backend.onrender.com` | not_suspended |
| dm-signal-db | `dpg-d542chchg0os73979vg0-a` | postgres | basic_1gb | `-` | not_suspended |
| dm-signal-deterioration-batch | `crn-d6kehqlm5p6s73dov630` | cron_job | starter | `-` | not_suspended |
| dm-signal-etl | `crn-d4ja8pp5pdvs739a5fs0` | cron_job | pro | `-` | suspended |
| dm-signal-frontend | `srv-d4ja8pp5pdvs739a5fsg` | static_site | starter | `https://dm-signal-frontend.onrender.com` | not_suspended |
| dm-signal-password-rotation | `crn-d53agure5dus73ap8el0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-fof | `crn-d5e8rabe5dus73fhlkjg` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-prices | `crn-d5e8rabe5dus73fhlkj0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-standard | `crn-d5e8rabe5dus73fhlkl0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-tickers | `crn-d5e8rabe5dus73fhlkkg` | cron_job | starter | `-` | not_suspended |
| inventory-app | `srv-d1d3m9re5dus73av45q0` | web_service | free | `https://inventory-app-uaou.onrender.com` | not_suspended |
| karajibi-stabilo-checker | `srv-d22ddeidbo4c73f3s0gg` | static_site | starter | `https://karajibi-stabilo-checker.onrender.com` | not_suspended |
| kj-partshift-checker | `srv-d4vta05actks73aan3s0` | web_service | starter | `https://kj-partshift-checker.onrender.com` | not_suspended |
| kj-toilet-backend | `srv-d4la0dgdl3ps7382pk60` | web_service | starter | `https://kj-toilet-backend.onrender.com` | not_suspended |
| kj-toilet-db | `dpg-d4la00gdl3ps7382pdfg-a` | postgres | basic_256mb | `-` | not_suspended |
| kj-toilet-frontend | `srv-d4la00gdl3ps7382pdeg` | static_site | starter | `https://kj-toilet-frontend.onrender.com` | not_suspended |
| note-dr-premium | `srv-d1u5r0ur433s73ed6kc0` | static_site | starter | `https://note-dr-premium.onrender.com` | not_suspended |
| rebalancer-frontend | `srv-d4iil54hg0os739v3cc0` | static_site | starter | `https://rebalancer-frontend.onrender.com` | suspended |
| simple-dual-momentum-db | `dpg-d1altb95pdvs73avn820-a` | postgres | basic_256mb | `-` | suspended |
| sunabaco | `srv-d0k2kmje5dus73bd94qg` | web_service | starter | `https://sunabaco.onrender.com` | suspended |

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8
- **ディレクトリsymlink不可**: os.symlink成功→is_dir=False→listdir/read全ENOENT。テキストポインタ(latest.txt)またはファイルsymlinkを使え（L663, cmd_2332）
- L008: WSL2新sh→CRLF混入（cmd_143）
- L014: grep exclude WSL2不安定（cmd_151）
- L037: WSL2 Write tool .sh→CRLF確定(L008拡張)（cmd_311）
- L058: WSL2 Write toolでCRLF混入→sed -i 's/\r$//'必須（cmd_370）
- L129: WSL2 Python3.12環境では外部feed偵察時にvenv未整備ケースがある（cmd_506）
- L194: pre-push timeout 40s→120s延長(WSL2)（cmd_721）
- L221: WSL2上の/mnt/c/配下ファイルはCRLF含むことがある（cmd_911）
- L227: WSL2のWrite toolはCRLF改行を生成する（cmd_970）
- L228: ast-grepのregex ruleはkind併記が要る（cmd_973）
- L316: WSL→Windows venv Ruff hook: repo-relative pathを使え（cmd_976）
- L301: bash埋込みPythonではsys.argv経由でパスを渡せ。ヒアドキュメント内の変数展開でエスケープ地獄を回避（cmd_training_L4_004）

**lock_path()実装の二重化に注意(cmd_3874, 2026-07-13)**: `scripts/lib/lock_path.sh`(正本)とは別に、`scripts/lib/yaml_field_set.sh`
がホットパス回避目的で`lock_path()`を独自にインライン再実装しており、`/mnt/c/*`パスで**正本と異なるハッシュ**を生成していた
(3箇所で重複実装、DJB2ハッシュ vs サニタイズ文字列末尾48文字)。`queue/insights.yaml`全損事故の直接原因、および`queue/tasks/*.yaml`
での潜在的事故要因(cmd_complete_gate.shは正本経由、ninja_monitor.sh/deploy_task.shはyaml_field_set()経由で異なるロック)を実証し統一済み。
L894(同一ファイル複数writerは単一lock_path()共有)の具体的落とし穴 — **「lock_path()」という同名関数が2つ存在しうる**ことも点検せよ。
新規flock実装は正本`scripts/lib/lock_path.sh`をsourceし、ロジックを複製・再実装するな → `docs/research/cmd_3874_lock_domain_unification.md`

## 競合調査

6スタイル+我らの定点観測レポート。毎回検索するな、ここを参照せよ。
我ら(57pt) > OpenAI(46) > OpenClaw(42) > ACE(40) > Teams(36) > Vercel(32)。
優位: 3層階層、6層知識、2重安全防御、インフラ構造保証。劣位: 外部可視性、セットアップ容易性。
→ `docs/research/competitive-landscape.md`

五者対比図(われら/ACE/Vercel/おしお/Claude Teams): 10軸×5者の詳細対比+系譜図+参考文献。
殿の厳命「われらはACEもVercelもOpenClawも内包し上回る」の根拠文書。
→ `docs/research/five-system-comparison.md`

Autoresearchエコシステム対比(Karpathy派生70+プロジェクト): 将軍システムは既にkeep-or-revert(gate)・永続メモリ(lessons/deepdive)・メタ改善(cmd_save.sh自己改善)・マルチエージェント調整(鎖/inbox)を実装済み。将軍独自の強み: revertではなく「修正→再実行」(学習を伴う)、追体験(deepdive)。未実装: 自動メタ改善(GEPA的instructions自動修正提案)、水平知識共有(忍者間ゴシップ)、安価ランタイム自動蒸留。注目: GEPA(ICLR 2026 Oral, 自然言語反射)、CORAL(共有永続メモリ+SOTA)、AI-Researcher(NeurIPS 2025, 仙人構想の参考)。
→ `docs/research/autoresearch-ecosystem-analysis.md`

## Android App

将軍Androidアプリは `android/` 配下の Kotlin + Jetpack Compose 製コンパニオン。package/applicationId=`com.shogun.android`、v6.4(versionCode 15)、SSH経由でtmuxを操作し、Dashboard/Agents/ShogunScreen/Settings/GistIndex/Usage を提供する。

| 項目 | 正本 |
|------|------|
| パス | `android/` |
| ビルド | `android/app/build.gradle.kts`（Gradle + AGP、Kotlin、Compose、Min SDK 26 / Target 34） |
| パッケージ | `com.shogun.android` |
| 主要画面 | Dashboard / Agents / ShogunScreen(将軍CLI) / Settings / GistIndex / Usage |
| SSH | `android/app/src/main/java/com/shogun/android/ssh/SshManager.kt`（JSch） |
| 音声入力 | `android/app/src/main/java/com/shogun/android/util/VoiceDictionary.kt`（90+プリセット） |
| README | `android/README_ja.md` / `android/README.md` |
| APK | `android/release/` |
| cmd履歴 | `context/cmd-chronicle.md` cmd_1809-1816, cmd_1924, cmd_1943, cmd_1945, cmd_2104 |
| 入力ロス調査 | [[android-ssh-input-loss-investigation]] |
| pane表示制限 | Claude CLI v2.1.201が`alternate_on=1`(alternate screen buffer)を使用。`capture-pane -S -500`で画面内の行しか取得できず、Androidアプリのpane遡りが不可能。pinned 2.1.87(`alternate_on=0`)とCodexは正常。回避策: pinned版維持 or `tmux set -g terminal-overrides "xterm*:smcup@:rmcup@"`(未検証)。調査: 2026-07-07 [[LS081_alternate_screen]] |

## 記憶DBバックアップ棚卸し（cmd_3869）

`data/`配下の記憶DBバックアップ903件/246,244,670,464 bytesを完全二分し、保持22件/5,701,424,128 bytes、削除候補881件/240,543,246,336 bytes（未削除・殿確認待ち）。完全一覧と各行の根拠 → `docs/research/cmd_3869_memory_db_backup_inventory.md`

## DM-Signal outputs陳腐化中間成果物削除（cmd_3871）

`outputs/`配下のDELETE候補38件のうちrg参照検証で10件(cmd_3819/cmd_3825/1026_yotsume DM系8ファイル)が現役設計書・lessons.mdから参照ありと判明しKEEPへ再分類、残28件を削除実行（df実測回収4,804,820,992 bytes≒4.47GiB）。**教訓: DELETE候補リストは前担当者の分類を鵜呑みにせず、AC2のrg参照検証を必ず自分で実行してから削除せよ**。完全一覧 → `docs/research/cmd_3871_stale_artifact_inventory.md`

## `/mnt/c`残量の事前検知（cmd_3875）

df計測SSOT=`scripts/lib/disk_space_watch.sh`。将軍/家老startupは警告域でALERT、危険域で総合BLOCK、`ninja_monitor.sh`は家老へ`disk_space_alert`通知して`gate_fire_log`へ記録する。既定50GB/20GB、環境変数で調整可能。動作証跡 → `docs/research/cmd_3875_disk_watch.md`

## 防御機構スループット棚卸し（cmd_4059）

最終checkpointは維持し、毎tool・毎prompt・毎commitの同期枝を計測可能化して非同期化/差分化するのが最優先。現物189項目の全数台帳と上位候補 → `docs/research/gate_hook_inventory_20260718.md`

## 外れ値型防御checkの発生条件（cmd_4185）

q11/three-layerはcache miss、instruction_syncはinstructions正本staged、test_granularityは追加test候補の全tree探索で発火。self_syncはsync枝まで部分特定、枝選択5項目の追加観測が必要。§3更新用の3点表・event生値・是正弾入力 → `docs/research/cmd_4185_outlier_conditions.md`

## DM-signal outputs陳腐化成果物削除（cmd_3871, 2026-07-24）

cmd_3819(3.4GB)+cmd_3825系(3.0GB)+grid_search bak(31MB)=計6.4GB回収。C: 664G→658G(72%→71%)。保全: cmd_3854 golden baseline(96MB)・cmd_3859 shadow artifacts(18MB)は無傷。詳細 → `DM-signal/docs/research/cmd_3871_stale_artifact_inventory.md`
