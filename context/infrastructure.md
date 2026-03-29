# インフラコンテキスト
<!-- last_updated: 2026-03-29 cmd_1480 偵察5要件追加+cmd_1476反映 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。Codex忍者=/new、Claude忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

## 直近改善（cmd_181〜cmd_541）

初期インフラ整備+教訓サイクル構築。acknowledged status(181), ペイン消失検知(183), inbox re-nudge(188/189/191), grep -cバグ(192), 裁定伝播遅延検出(PD-016), 知識鮮度警告(PD-017), dashboard_update(337), auto_deploy_next(338), ゲート迂回防止(339), 教訓タグ注入(348/349/350/351), 量→質転換(531), CMD年代記(544)
→ `docs/research/infra-details.md` §2, 各スクリプト: `scripts/` 配下

## 直近改善（cmd_602〜cmd_612）

review品質機械検査(607), ntfy_listener dual watchdog(609), lesson_impact feedback修復(611), 旧terminology一掃(612)
→ `context/cmd-chronicle.md` 03-06 / `scripts/` + `config/settings.yaml`

## 直近改善（cmd_875〜cmd_878）

gstack Tier1-2取込(875/876): 忍者プロンプト強化+家老Two-pass Review+Gate [CRITICAL]/[INFO]分離。CDP daemon化(877): persistent WebSocket+@ref体系。教訓同期修復(878): 淘汰カウント精度向上
→ `docs/research/gstack-analysis.md` / `scripts/cdp/README.md` / `context/cmd-chronicle.md` 03-13

## 直近改善（cmd_1039〜cmd_1120）

| cmd | 改善 | 結論 |
|-----|------|------|
| 1039/1040 | **ninja_monitor三段階/clear** | Stage 1: YAML確認→Stage 2: 再確認→Stage 3: /clear。作業中(acknowledged/in_progress)忍者の誤/clear防止 |
| 1044 | **Read追跡hook** | Write/Edit前の未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| 1053 | **ac_versionハッシュ化** | ACテキスト内容のハッシュでバージョン管理。AC内容差替えを確実に検知 |
| 1054 | **cmd_absorb.sh abort機能** | cmd吸収時に旧cmdで稼働中の忍者を即/clearし無駄な作業時間を防止 |
| 1065 | **タスクYAML hook強制** | queue/tasks/*.yamlへのWrite/Editを無条件deny。deploy_task.sh経由のみ許可 |
| 1067 | **報告YAML hook強制** | queue/reports/*.yamlへのWrite/Editを無条件deny。report_field_set.sh経由のみ許可 |
| 1111 | **家老教訓自動ロード** | /clear Recovery手順にlessons_karo.yaml読込を追加。家老の教訓参照漏れ防止 |
| 1113 | **gate穴検出3問トリガー** | GATE CLEAR時にgate_improvement_trigger.sh自動発火。3問で防御層の穴を検出 |
| 1117 | **hook失敗自動記録+穴検出3問** | 報告テンプレートにhook_failures欄追加。hook失敗→穴検出3問を自動連鎖 |
| 1118 | ラルフループ効果検証 | 学習ループ(clear→知識基盤残存→穴検出→防御層強化)の定量検証スクリプト |
| 1119/1120 | **自動トリム機構** | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive_completed.shで自動トリム |

→ 完了履歴: `context/cmd-chronicle.md` 03-18〜03-20

## 軍師品質管理ユニット（cmd_1144〜cmd_1181）

家老+軍師=品質管理ユニット化。軍師が一次レビュー→LGTM→家老スタンプのみ/FAIL→家老介入。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1162 | **忍者報告一次レビュー委譲** | 軍師が忍者報告の一次レビューを担当（report_review）。家老のレビュー負荷消滅→配備+教訓に専念 |
| 1174 | **GSD式6観点+5段階プロトコル** | 軍師レビュー基準体系化: 前提検証/数値再計算/時系列シミュレーション/事前検死/確信度ラベル/North Star整合 |
| 1181 | **git show HEAD検証+証拠必須化** | ドラフトレビュー前提検証でgit show HEAD使用+証拠添付必須。未commit変更の既実装誤判定防止 |

→ `instructions/gunshi.md` §Review Criteria / §5段階思考プロトコル / §Report Review
- L271: gunshi_accuracy_log.sh未作成 — 軍師accuracy計測スクリプト欠落（cmd_1158）
- L281: 軍師基準設計は実例駆動で内面化する（cmd_1174）

## 偵察デフォルト品質5要件（cmd_754+cmd_1476）

偵察は現象特定で止めるな。以下5要件をデフォルト品質として自動化×強制:
1. 変更対象ファイル・行番号
2. 波及先ファイル
3. 関連テスト有無・修正要否
4. エッジケース・副作用
5. **依存関係・順序制約**(flush順序・キャッシュ共有・ネスト読み書き等) ← cmd_1476追加

テンプレート(deploy_task.sh)+ゲートWARN(cmd_design_quality.yaml)で強制。cmd_754で4要件導入、cmd_1476で第5要件追加(DC裁定)。
→ `instructions/ashigaru.md` 偵察テンプレート / `logs/cmd_design_quality.yaml` q4_depth

## 忍者個別弱点自動注入（cmd_1307）

deploy_task.shにinject_ninja_weak_points関数追加。karo_workarounds.yamlから忍者名でフィルタし、workaround:trueのcategory別件数をtask YAMLのninja_weak_pointsセクションに自動注入。0件忍者には注入しない。
→ `scripts/deploy_task.sh` L2038

## gate強化（cmd_1178〜cmd_1180）

cmd_1173偵察で特定した高優先gate未実装項目の構造的実装。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1178 | **lesson_candidate+binary_checks gate検査** | cmd_complete_gate.shにlesson_candidate空検証+binary_checks検証を追加。報告品質の機械的保証 |
| 1179 | **gate_dc_duplicate.sh新設** | DC裁定重複チェックゲート。既決PDへの再エスカレーション防止（L236対策） |
| 1180 | **FILL_THIS残留BLOCKメッセージ** | FILL_THIS残留検出時の具体的BLOCKメッセージ追加。忍者が修正箇所を即特定可能に |

- L299: git_uncommitted_gateはプロジェクトリポジトリを解決すべし。multi-agent-shogunとDM-signalで対象が異なる（cmd_1412）
- L300: binary_checks GATE検証はACグループ化+yes/true値をサポートすべし（cmd_1412）
→ `scripts/cmd_complete_gate.sh` / `scripts/gates/gate_dc_duplicate.sh`

## 知識サイクル現状（cmd_531/533/541/1111/1113/1117 反映）

教訓の蓄積→注入→参照→淘汰を自動で回す仕組み。家老が健全性を問われたらここを読め。

### 稼働中の仕組み

| 仕組み | 実装先 | 導入cmd | 動作 |
|--------|--------|---------|------|
| MAX_INJECT=5 | deploy_task.sh | cmd_531 | タスクあたり注入上限5件。helpful_count降順で優先。超過分はwithheldとしてlesson_impact.tsvに記録 |
| タグベース注入 | deploy_task.sh | cmd_349 | タスクtags[]と教訓tags[]をマッチングし関連教訓を自動注入 |
| 自動退役 | lesson_deprecation_scan.sh | cmd_531 | 有効率10%未満×注入10回以上→自動deprecated。ファイル消滅教訓も自動退役。GATE CLEAR時に自動実行 |
| 効果率監視 | gate_lesson_health.sh | cmd_531 | 直近30cmdの効果率計算。50%未満→WARN(ntfy)、30%未満→ALERT(ntfy+ダッシュボード) |
| lesson_candidate検証 | cmd_complete_gate.sh | cmd_528 | 報告YAMLのlesson_candidateフォーマットをゲートで検証。旧形式(リスト)→BLOCK |
| lesson_tracking.tsv | cmd_complete_gate.sh | cmd_348 | 教訓注入・参照の追跡ログをTSV永続化 |
| PDサマリー自動更新 | pending_decision_write.sh | cmd_541 | PD書込み/resolve時にpending_decisions.yaml冒頭のtotal/resolved/pending件数を自動更新 |
| context未更新ゲート | cmd_complete_gate.sh + deploy_task.sh | cmd_543 | cmd YAMLにcontext_update指定→deploy時に忍者タスクへ伝播→GATE時にlast_updated検査→stale時BLOCK |
| CMD年代記 | archive_completed.sh | cmd_544 | cmd完了→archive時にcontext/cmd-chronicle.mdへ1行自動追記。月別セクション+flock排他 |
| Read追跡hook | settings.json hook | cmd_1044 | Write/Edit前に未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| タスク/報告YAML hook強制 | settings.json hook | cmd_1065/1067 | queue/tasks/*.yaml, queue/reports/*.yamlへの直接Write/Editを無条件deny。deploy_task.sh/report_field_set.sh経由のみ許可 |
| 家老教訓自動ロード | instructions/karo.md | cmd_1111 | /clear Recovery手順にlessons_karo.yaml読込を追加。教訓参照漏れ防止 |
| gate穴検出3問トリガー | gate_improvement_trigger.sh | cmd_1113 | GATE CLEAR時に3問で防御層の穴を自動検出。ninja_monitor定期巡回に統合(cmd_1114) |
| hook失敗自動記録 | 報告テンプレート+ashigaru.md | cmd_1117 | hook_failures欄で失敗を構造化記録。穴検出3問と自動連鎖 |
| 自動トリム | archive_completed.sh | cmd_1119/1120 | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive時に自動トリム |

### 現行メトリクス（2026-03-04時点）

| 指標 | 値 | 備考 |
|------|------|------|
| 教訓総数(SSOT) | 152件(退役5件) | tasks/lessons.md |
| 教訓参照率 | 82.4% | lesson_tracking.tsv（391タスク中322件が参照） |
| 注入/除外比 | injected:1398 / withheld:763 | MAX_INJECT=5の効果。35%がフィルタリング |
| 初回CLEAR率 | 全体64%、直近50件83% | gate_metrics.log。構造BLOCK(missing_gate)65%含む |
| 手戻り率 | 1.3% (1/77cmd) | fixes付きcmd |

### 設計思想

helpful/harmful手動評価に依存しない。注入回数と参照率を代理指標として自動で品質制御する。
- L418: ランブック品質はdb-operations-runbook以外極めて低い。28件中22件監査、21件が教訓参照ゼロ。ランブック品質底上げにはlesson索引セクション追加とPIの明示的組込みが必要（cmd_1094）
- L247: found:falseは教訓を探さなかった証拠。全タスクに学びがある。no_lesson_reason必須化+家老差し戻しルール追加（cmd_1104）
- L249: 教訓還流の仕組み変更は3層同時修正必須: ashigaru.md+deploy_task.sh+karo.md（cmd_1104）

## ninja_monitor.sh

idle検知+コンテキストリセット送信（Codex=/new, Claude=/clear）、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
三段階/clear(cmd_1039/1040): Stage 1: YAML status確認(acknowledged/in_progress→skip)→Stage 2: 再確認(race condition防止)→Stage 3: /clear送信。作業中忍者の誤クリア防止。
auto-done判定: parent_cmdだけでなくtask_idも一致チェック必須。Wave間で誤done発生実績あり(L048)。
auto_deploy統合(cmd_338): auto-done後にauto_deploy_next.sh自動発火。次サブタスク自動配備。
DEPLOY-STALL強化(cmd_461): 家老通知(L712-715)、再STALLエスカレーション(STALL_COUNT連想配列)、Codex stall_debounce=180s(cli_profiles.yaml)。
cmd_500(2026-03-03): check_stall()を再設計。`STALL_NOTIFIED`を5分デバウンス再通知へ変更、in_progress停滞時に本人へ`task_assigned`再送+`STALL-RECOVERY-SEND`ログ、同一subtask複数回で`stall_escalate`送信（「差し替え必須」明記）。Codex向け`in_progress_stall_min`を`config/cli_profiles.yaml`から読取（未設定時20分fallback）。
L112対応履歴: `task_id || subtask_id` フォールバック適用済み。調査記録は `docs/research/cmd_462_codex-stall-analysis.md`、実装記録は `docs/research/cmd_500_codex-stall-enforcement.md`
- L052: DESTRUCTIVE検出でcapture-pane履歴にsend-keysが残る誤検知あり（cmd_324）
- L114: safe_send_clear独自idle判定(tail -3)がCLIステータスバーで❯を見落とし永久CLEAR-BLOCKED。idle判定はcheck_idle()に一本化せよ（cmd_466）
- L134: NINJA_MONITOR_LIB_ONLYガードでbashスクリプトの関数テストが可能に（cmd_519）
- L204: STALL誤判定の実態は「idle+status未更新」が主因。pstree方式で予防的防御層追加が有効（cmd_777）
- L205: Codex paneの@agent_state=idleをbusy判定のtruth sourceにしてはならぬ（cmd_777）
- L248: assigned→idle化は/clear後にtask YAMLを読まなかった可能性大。STALL検知(10分超)で自動捕捉+家老に再配備通知（cmd_1105）
- L259: STALL偽陽性の38%はStale YAML Ghost(task_id空)が原因（cmd_1129）
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
2026-03-03 運用修正: Codexで`@agent_state=active`残留時はcapture-paneでidle/busyを再判定し補正。BUSY deferはretry消費しない。`profiles.codex.inbox_busy_max_defer_sec`(既定30秒)超過で強制nudge。
- L002: FG bashでnudge不可（cmd_125）
- L018: Edit tool flock未対応→inbox既読化はinbox_mark_read.sh必須（cmd_189）
- L029: nudge嵐=二重経路合流（cmd_255）
- L043: inbox_write.sh Python展開にインジェクション脆弱性（cmd_317）
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
- L160: ntfy添付DLはAUTH_ARGS再利用でprivate topicでも同一認証経路を維持できる（cmd_551）
- L161: 画像添付MIME整合改善の必要性（cmd_551）
- L166: ストリーミング受信デーモンは起動側pkillに依存せず受信側でも単一起動ロックを持つべし（cmd_571）
- L167: ストリーム購読系デーモンはsingleton lock + message idempotency必須セット（cmd_571）
- L174: watchdogがkeepalive/open行のread成功でも活動時刻を更新→ntfy keepalive(45秒)で永遠延命（cmd_608）
- L175: ストリームwatchdogが任意受信バイトで更新されるとkeepaliveで実メッセージ断を見逃す（cmd_608）
- L176: watchdogの活動時刻は「意味のあるイベント処理成功」で更新すべし（cmd_608）
- L298: NTFY_LISTENER_LIB_ONLY=1でもtop-level初期化コードが実行される。source時の副作用に注意（cmd_1409）
→ `docs/research/infra-details.md` §5

## ログローテーション

二重機構で運用:

| 機構 | 実装 | トリガー | 閾値 | 世代 |
|------|------|----------|------|------|
| スタンドアロン | `scripts/log_rotate.sh` | 手動 or cron | 10MB/ファイル | 5世代(.1-.5) |
| ninja_monitor内蔵 | `lib/rotate_log.sh` → `rotate_all_logs()` | 10分間隔(メインループ) | 10,000行 or 1MB | 3世代(.1-.3), copytruncate方式 |

ninja_monitor内蔵版が常時稼働の主系。スタンドアロン版は非監視ログの手動ローテーション用。
- L258: ログローテーション世代数不足+task_idログ欠損（cmd_1129）

## field_deps.tsv

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

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8
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

## 競合調査

6スタイル+我らの定点観測レポート。毎回検索するな、ここを参照せよ。
我ら(57pt) > OpenAI(46) > OpenClaw(42) > ACE(40) > Teams(36) > Vercel(32)。
優位: 3層階層、6層知識、2重安全防御、インフラ構造保証。劣位: 外部可視性、セットアップ容易性。
→ `docs/research/competitive-landscape.md`

五者対比図(われら/ACE/Vercel/おしお/Claude Teams): 10軸×5者の詳細対比+系譜図+参考文献。
殿の厳命「われらはACEもVercelもOpenClawも内包し上回る」の根拠文書。
→ `docs/research/five-system-comparison.md`

## Infra教訓索引
<!-- last_synced_lesson: L302 -->
<!-- lesson-sort 2026-03-28: L298-L301の4件を振り分け。ntfy(L298), gate強化(L299/L300), WSL2(L301) -->
<!-- lesson-sort 2026-03-22: L256-L284の29件を振り分け(27件移動+2件重複削除)。§メインセクション: ninja_monitor(L259), ログローテーション(L258), tmux(L265/268), 軍師(L271/281)。サブセクション: bash(L263/269/270/272/277), deploy(L256/284), 報告(L264), 教訓(L257/260/266/273/275/276), gate(L262/280/282), テスト(L261), 知識(L274), レビュー(L267/283)。L278/L279重複削除 -->
<!-- lesson-sort 2026-03-26: L285-L297の13件を振り分け(12件移動+1件重複削除)。bash(L287/289/290/295/297), deploy(L288), 報告(L291), 教訓(L285), git(L292), 知識(L286/293/294)。L296はL297重複→削除 -->

### カテゴリ別索引（L051-L297）
| カテゴリ | Lesson IDs | 件数 |
|---------|------------|------|
| bash/シェルスクリプト | L059,074,092,096,149,155,156,157,164,169,170,171,183,184,231,263,269,270,272,277,287,289,290,295,297 | 25 |
| git/gitignore/CI/hooks | L064,072,093,109,110,113,116,143,144,150,151,153,172,179,180,186,188,189,190,192,218,220,232,233,377,292 | 26 |
| deploy_task.sh/配備 | L056,057,070,071,073,076,079,088,111,119,181,185,207,219,222,230,256,284,288 | 19 |
| 報告YAML/レポート | L055,060,062,085,091,095,098,120,121,127,131,132,209,210,362,264,291 | 17 |
| 教訓サイクル/lesson | L054,063,080,081,086,087,089,102,106,107,117,126,133,136,137,141,145,147,152,154,165,168,214,217,257,260,266,273,275,276,285 | 31 |
| ゲート/gate_metrics | L097,099,100,101,215,216,262,280,282 | 9 |
| テスト | L142,146,148,158,162,163,191,193,208,234,235,261 | 12 |
| 知識管理/ビルド | L065,066,077,084,090,104,128,135,173,182,206,212,353,274,286,293,294 | 17 |
| レビュー | L061,138,139,140,236,239,375,267,283 | 9 |
| LLM/エージェント/MCP | L051,053,108,130,159,178,201,203,211,213,223,224,225,226,238,400 | 16 |
| UI/Android | L187,195,196,197,198,199,200,202 | 8 |
| → §セクション振り分け済 | L002,004,008,014,018,029,037,043,052,058,067,068,069,082,083,094,103,105,114,118,122,123,124,125,129,134,160,161,166,167,174,175,176,194,204,205,221,227,228,237,258,259,265,268,271,278,279,281,316 | 49 |

→ 詳細(L001-L297の個別記述): `docs/research/infra-lessons-detail.md`
- （L298→§ntfy.sh, L299/L300→§gate強化, L301→§WSL2に振り分け済 2026-03-28）
- L302: pipefailスクリプトでgrep空マッチがexit 1を引き起こす（pipefail,grep,bash,ci）

## 軍師レビュー効果計測（cmd_1144導入）

家老+軍師の品質管理ユニット化（cmd_1144）の効果を定量計測する。

### ベースライン（導入前）
- **GATE CLEAR率**: 直近30cmdの初回GATE CLEAR率をdashboard.mdの戦果セクションから取得
- **Re-review率**: 直近30cmdのうちFAIL→再レビューが発生したcmdの割合

### 導入後計測
- 同指標を継続計測（軍師レビュー導入後30cmd分）
- データソース: dashboard.mdの戦果セクション（完了cmd一覧+karo_workaround記録）

### 判定基準（30cmd後）
| 指標 | 判定 | 結論 |
|------|------|------|
| CLEAR率維持 + Re-review率低下 | 付加価値あり | 軍師レビュー継続 |
| CLEAR率維持 + Re-review率変化なし | 判断保留 | さらに30cmd計測 |
| CLEAR率低下 | 要見直し | 軍師レビュー観点の調整を検討 |

## PD裁定反映（cmd_354同期）

| PD | 裁定 | 反映先 |
|----|------|--------|
| PD-037 | inbox_write.sh HIGH-1(Python直接展開インジェクション)+HIGH-2(パストラバーサル)修正。殿裁定2026-02-25 | L043修正済み。`scripts/inbox_write.sh` |
| PD-038 | ashigaru.md否定指示→案C(ハイブリッド)採用。forbidden_actions構造維持+positive_rule+reason追加。ACE準拠 | `instructions/ashigaru.md` cmd_324実装済み |

## SKILL.md品質基準（7項目チェックリスト）

スキル作成・更新時に必ず確認。発火精度はdescription品質で決まる。
- L069: スキルがsystem-reminderに検出されるにはSKILL.mdにYAMLフロントマター必須（cmd_368）
- L103: skill.md(小文字)はcase-sensitive環境で未検出→SKILL.md(大文字)に統一（cmd_438）
- L122: SKILL.md手順追加時に原則セクションとの矛盾を確認せよ（cmd_490）

| # | 項目 | 基準 | NG例 | OK例 |
|---|------|------|------|------|
| 1 | What | 具体的な出力を明記 | 「ドキュメント処理」 | 「PDFからテーブル抽出しCSV変換」 |
| 2 | When | 使用シーンを明記 | (なし) | 「gate_lesson_health.shのALERT後に使用」 |
| 3 | トリガーワード | 発火キーワードを列挙 | (なし) | 「棚卸し」「監査」「メモリ整理」 |
| 4 | 動詞の具体性 | 「管理」禁止 | 「知識を管理する」 | 「検出・更新提案・実行」 |
| 5 | 長さ | 50-200文字 | 300文字の散文 | 簡潔な1-2文 |
| 6 | 差別化 | 既存スキルとの守備範囲明示 | (なし) | 「/shogun-teireは全層監査、本スキルはMemory MCPのみ」 |
| 7 | 角括弧不使用 | description内で[X]禁止 | 「[PDF]を処理」 | 「PDFを処理」 |

### フロントマター必須フィールド
- `allowed-tools`: 使用ツール制限（未指定=全ツール利用可。意図的な場合のみ省略）
- `argument-hint`: 補完表示（例: `[project-id]`）

### オプションフィールド
- `context: fork`: サブエージェント隔離実行（メインCTX圧迫防止）
- `model`: 実行時モデル指定

### North Star
カスタムフロントマターフィールドはClaude Codeに無視される。
判断基準はMarkdown本文に記載すること。
