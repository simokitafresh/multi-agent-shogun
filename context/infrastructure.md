# インフラコンテキスト
<!-- last_updated: 2026-03-06 cmd_604 docs/config整合修正 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。Codex忍者=/new、Claude忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

## 直近改善（cmd_181〜cmd_255）

| cmd | 改善 | 結論 |
|-----|------|------|
| 181 | acknowledged status | assigned→acknowledged→in_progress遷移でゴースト配備誤判定解消 |
| 183 | ペイン消失検知 | remain-on-exit=on + ninja_monitor自動回復 |
| 188 | inbox re-nudge | @inbox_unread表示 + monitor自動再ナッジ |
| 189 | inbox_mark_read.sh | flock+atomic writeで既読化経路統一（Edit tool禁止） |
| 191 | idle家老auto-nudge | pending cmd検知時にmonitorが家老へ自動ナッジ |
| 192 | grep -c改行バグ | awk代替で単一数値返却に統一 |
| PD-016/239 | 裁定伝播遅延検出 | context_synced:false自動付与→gate WARNING（非ブロッキング） |
| PD-017/239 | 知識鮮度警告 | deploy時last_updated検査→14日超WARNING（非ブロッキング） |

→ `docs/research/infra-details.md` §2

## 直近改善（cmd_336〜cmd_541）

| cmd | 改善 | 結論 |
|-----|------|------|
| 337 | dashboard_update.sh | GATE CLEAR時にダッシュボード自動更新 |
| 338 | auto_deploy_next.sh | サブタスク完了時に次自動配備。idle検知依存で最大25秒ラグ(L057) |
| 339 | F007ゲート迂回防止 | cmd_complete_gate.sh以外のstatus変更をブロック |
| 348 | lesson_tracking.tsv | 教訓注入・参照の追跡ログをTSV永続化(L060解決) |
| 349 | タグベース教訓注入 | タスクtags[]×教訓tags[]マッチング |
| 350 | lesson_deprecate.sh | deprecated教訓を注入から除外 |
| 351 | shogun-teire観点⑧ | 教訓効果監査 |
| 528 | lesson_candidate検証 | フォーマット旧形式→BLOCK |
| 529 | lesson_done_source調査 | 根本原因特定(L136/L137) |
| 530 | ac_version照合 | stale作業検知(タスクYAML版管理) |
| 531 | **量→質転換** | MAX_INJECT=5 + 自動退役 + 効果率監視 |
| 533 | 教訓detail注入改善 | related_lessons.detail注入精度向上 |
| 537 | git addエラー防止 | ashigaru.md明文化+pre-commitフック |
| 541 | 家老情報源修正 | ダッシュボード効果率表示バグ修正+PDサマリー自動化 |
| 543 | **context未更新ゲート** | cmd YAML context_update指定→last_updated検査→stale時BLOCK |
| 544 | **CMD年代記** | archive時にcmd-chronicle.md自動追記。直近50件初期populate |

→ 各スクリプト実装: `scripts/` 配下

## 直近改善（cmd_602〜cmd_612）

| cmd | 改善 | 結論 | 参照 |
|-----|------|------|------|
| 607 | review品質機械検査 | `cmd_complete_gate.sh` が review verdict二値・AC対応evidence・lesson_candidate・self_gate_check を機械検証し、欠落時BLOCKする | `scripts/cmd_complete_gate.sh`, `context/cmd-chronicle.md` |
| 609 | ntfy_listener dual watchdog | stream activityとmessage activityを分離し、実メッセージ停滞をwatchdogで再接続対象にした。手動復旧は `restart_ntfy_listener.sh` に集約 | `scripts/ntfy_listener.sh`, `scripts/restart_ntfy_listener.sh`, `context/cmd-chronicle.md` |
| 611 | lesson_impact feedback修復 | `cmd_complete_gate.sh` が `lesson_impact.tsv` へ `result(CLEAR/BLOCK)` と `referenced` を再書込し、cmd_500以降の学習フィードバック断絶を解消した | `scripts/cmd_complete_gate.sh`, `logs/lesson_impact.tsv`, `context/cmd-chronicle.md` |
| 612 | 旧terminology一掃 | 進化監査で見つかった旧編成 terminology 残存5ファイルと MEDIUM所見3件を修正し、インフラ記述とCLI編成の用語衛生を回復した | `context/cmd-chronicle.md`, `config/settings.yaml` |

→ 実装・完了履歴: `context/cmd-chronicle.md` 03-06 / 具体実装は `scripts/` と `config/settings.yaml`

## 知識サイクル現状（cmd_531/533/541 反映）

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

## ninja_monitor.sh

idle検知+コンテキストリセット送信（Codex=/new, Claude=/clear）、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
auto-done判定: parent_cmdだけでなくtask_idも一致チェック必須。Wave間で誤done発生実績あり(L048)。
auto_deploy統合(cmd_338): auto-done後にauto_deploy_next.sh自動発火。次サブタスク自動配備。
DEPLOY-STALL強化(cmd_461): 家老通知(L712-715)、再STALLエスカレーション(STALL_COUNT連想配列)、Codex stall_debounce=180s(cli_profiles.yaml)。
cmd_500(2026-03-03): check_stall()を再設計。`STALL_NOTIFIED`を5分デバウンス再通知へ変更、in_progress停滞時に本人へ`task_assigned`再送+`STALL-RECOVERY-SEND`ログ、同一subtask複数回で`stall_escalate`送信（「差し替え必須」明記）。Codex向け`in_progress_stall_min`を`config/cli_profiles.yaml`から読取（未設定時20分fallback）。
L112対応履歴: `task_id || subtask_id` フォールバック適用済み。調査記録は `docs/research/cmd_462_codex-stall-analysis.md`、実装記録は `docs/research/cmd_500_codex-stall-enforcement.md`
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
2026-03-03 運用修正: Codexで`@agent_state=active`残留時はcapture-paneでidle/busyを再判定し補正。BUSY deferはretry消費しない。`profiles.codex.inbox_busy_max_defer_sec`(既定30秒)超過で強制nudge。
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
→ `docs/research/infra-details.md` §5

## tmux設定

prefix=Ctrl+A。session=shogun、W1=将軍、W2=agents(家老+忍者9ペイン)。形式: shogun:2.{pane}
Opus4: kagemaru/hanzo/kotaro/tobisaru / Codex4: sasuke/kirimaru/hayate/saizo。CLI→`config/settings.yaml`

| pane | 名前 | pane | 名前 | pane | 名前 |
|------|------|------|------|------|------|
| 1 | karo | 4 | hayate | 7 | saizo |
| 2 | sasuke | 5 | kagemaru | 8 | kotaro |
| 3 | kirimaru | 6 | hanzo | 9 | tobisaru |

ペインレベル環境変数は存在しない。ペイン別CLAUDE_CONFIG_DIRはrespawn-pane -e or send-keys注入(L041)。
capture-paneバナー解析: モデル名+バージョン番号の精密パターン必須。コマンドテキスト自体のfalse positiveに注意(L046)。
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
→ `docs/research/cmd_314_usage_api_verification.md` / `docs/research/cmd_314_account_switching_procedures.md`

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8

## 競合調査

6スタイル+我らの定点観測レポート。毎回検索するな、ここを参照せよ。
我ら(57pt) > OpenAI(46) > OpenClaw(42) > ACE(40) > Teams(36) > Vercel(32)。
優位: 3層階層、6層知識、2重安全防御、インフラ構造保証。劣位: 外部可視性、セットアップ容易性。
→ `docs/research/competitive-landscape.md`

五者対比図(われら/ACE/Vercel/おしお/Claude Teams): 10軸×5者の詳細対比+系譜図+参考文献。
殿の厳命「われらはACEもVercelもOpenClawも内包し上回る」の根拠文書。
→ `docs/research/five-system-comparison.md`

## Infra教訓索引

| ID | 結論 | 区分 | 出典 |
|---|---|---|---|
| L001 | Write前Read必須 | CLI | cmd_125 |
| L002 | FG bashでnudge不可 | inbox | cmd_125 |
| L003 | MD更新=稼働中反映なし | CTX | cmd_125 |
| L004 | pane変数空≠未配備 | tmux | cmd_092 |
| L005 | ashigaru→roles/参照 | build | cmd_134 |
| L006 | lesson重複チェック欠如 | 教訓 | cmd_134 |
| L007 | whitelist gitignore注意 | git | cmd_140 |
| L008 | WSL2新sh→CRLF混入 | WSL2 | cmd_143 |
| L009 | commit前git status確認 | git | cmd_143 |
| L010 | status行^先頭マッチ | 報告 | cmd_145 |
| L011 | core.hooksPath確認 | git | cmd_147 |
| L012 | aliasでpipeブロック不可 | bash | cmd_147 |
| L013 | L005のkaro版 | build | cmd_150 |
| L014 | grep exclude WSL2不安定 | WSL2 | cmd_151 |
| L015 | CONFIG_DIR切替 | OAuth | saizo |
| L016 | OAuthトークン競合 | OAuth | tobisaru |
| L017 | 入口門番→再配備自己ブロック | 配備 | cmd_158 |
| L018 | Edit tool flock未対応 | inbox | cmd_189 |
| L019 | grep -c‖echo 0二重出力 | bash | cmd_192 |
| L020 | 設定パス環境変数共有 | script | cmd_208 |
| L021 | declare -A→-gA scope | bash | cmd_208 |
| L022 | flock内python retry誤発動 | script | cmd_220 |
| L023 | 自動化は報告スキーマ先行 | 教訓 | cmd_231 |
| L024 | 報告アーカイブ不在 | 報告 | cmd_231 |
| L025 | =L027 draft版 | 報告 | cmd_236 |
| L026 | 14%陳腐化→deprecation | 知識 | cmd_237 |
| L027 | 統合タスクでreport上書き | 報告 | cmd_236 |
| L028 | CI Run#とSHA整合確認 | CI | cmd_248 |
| L029 | nudge嵐=二重経路合流 | inbox | cmd_255 |
| L030 | current_project死コード | 知識 | cmd_258 |
| L031 | PJ固有=CLAUDE.mdの4% | 知識 | cmd_258 |
| L032 | PJセクション境界=## | 知識 | cmd_258 |
| L033 | confirmed時status欠落 | 教訓 | cmd_262 |
| L034 | YAMLインデント変動 | ゲート | cmd_279 |
| L035 | gate検証で副作用発火 | ゲート | cmd_279 |
| L036 | git checkout -- SSOTで未コミット教訓消失 | git | cmd_310 |
| L037 | WSL2 Write tool .sh→CRLF確定(L008拡張) | WSL2 | cmd_311 |
| L038 | gate実行で本番lessonsにdraft副作用(L035実害) | ゲート | cmd_311 |
| L039 | 教訓参照怠り(自動生成) | 教訓 | cmd_310 |
| L040 | WSL2 Usage API応答5秒超→timeout≥10秒 | WSL2 | cmd_314 |
| L041 | tmuxペインレベル環境変数なし→respawn-pane -e | tmux | cmd_314 |
| L042 | 統合タスクでreport上書き実害(L025+L027統合) | 報告 | cmd_310 |
| L043 | inbox_write.sh Python展開にインジェクション脆弱性 | inbox | cmd_317 |
| L044 | reports YAML扁平/ネスト2構造混在→パーサー両対応必須 | 報告 | cmd_317 |
| L045 | AC達成状況フィールド名3種混在(acceptance_criteria/ac_status/ac_checklist) | 報告 | cmd_317 |
| L046 | capture-paneバナー解析のfalse positive防止(モデル名+版数精密パターン) | tmux | cmd_320 |
| L047 | deploy_task.sh Python -cにシェル変数直接埋込→インジェクション危険 | セキュリティ | cmd_317 |
| L048 | ninja_monitor auto-done誤判定→parent_cmd+task_idチェック必須 | monitor | cmd_317v2 |
| L049/L050 | コードレビューで既存対策見落とし共通パターン→全行+コメント精読必須 | レビュー | cmd_317v2 |
- L051: Sonnet 4.6はMUST/NEVER/ALWAYSをリテラルに従わず文脈判断でオーバーライドする。否定指示は肯定形+理由付き、絶対禁止は条件付きルーティング(IF X THEN Y)に変換すると遵守率向上。Pink Elephant研究で学術裏付け
- L052: ninja_monitorのDESTRUCTIVE検出でcapture-pane履歴にsend-keysが残る誤検知あり。DESTRUCTIVE判定ログ(kill/rm等)はcapture-pane結果に他エージェントのsend-keys内容が混入する可能性を考慮すべき
- L053: Claude 4.x CRITICAL/MUST/NEVERがovertriggering副作用（cmd_324）
<!-- last_synced_lesson: L185 -->
- L054: lesson_write.shのcontextロック失敗が非致命でSSOTとcontext不整合を許容（cmd_323）
- L055: report YAML構造混在に対するフォールバック必須（cmd_337）
- L056: タスクYAML上書き問題: auto_deploy時の全サブタスク永続化（cmd_338）
- L057: cmd_338（check_and_update_done_task()はhandle_confirmed_idle()→is_task_deployed()内でのみ発火。忍者がidle確認後にしかauto-done判定されない。報告YAML→idle遷移まで最大20秒+CONFIRM_WAITのラグ存在。将来report YAML inotifywatchに移行すればラグ解消可能）
- L058: WSL2の/mnt/c上でClaude CodeのWrite toolを使うと.shファイルにCRLF改行が混入する。bash -nで構文エラーになるため、新規.shファイル作成後は必ず sed -i 's/\r$//' で修正すること。（common.sh新規作成時にCRLF混入でbash -n失敗した実体験）
- L059: 共通スクリプトのリファクタ後はインタフェース契約の確認が必要。usage_status.shは引数なし統合出力設計だがusage_statusbar_loop.shが引数付き2回呼出しで重複表示バグ。呼出し側と被呼出し側のI/F整合を検証せよ。（usage_statusbar_loop.sh重複表示バグの修正体験）
- L060: タスクYAML/報告YAMLの上書き式がメトリクスデータ永続性を阻害（cmd_344）
- L061: 統合設計レビューではソースコード実地確認が必須（cmd_344）
- L062: acceptance_criteriaフィールドはdict/str混在のためjoin前に型変換が必要（--tags）
- L063: lessons.yamlはdict構造(lessons:キー配下リスト)。for lesson in dataはdictキーをイテレート→誤り。data['lessons']で取得せよ（cmd_351）
- L064: gitignore whitelist未登録は実行テストで検出不可（cmd_359）
- L065: テンプレート定義とvalidation対象の一致確認義務（cmd_360）
- L066: reset_layout.shのような複数スクリプトを横断する機能では、依存APIのYAMLキー名を実データと突合せよ。settings.yamlのmodel_name vs get_agent_model()のmodelのようなキー不一致はdry-runでは正常終了するが実行結果が誤る（cmd_361）
- L067: ペイン背景色は@model_name更新と連動していない(reset_layout.shのみで設定)（cmd_365）
- L068: shutsujin_departure.shが2ファイル存在(root+scripts/)で背景色ロジック不整合（cmd_365）
- L069: スキルがsystem-reminderに検出されるにはSKILL.mdにYAMLフロントマター(---/name/description/allowed-tools/---)が必須（cmd_368）
- L070: deploy_task.shはタスクYAMLの2スペースインデントを6箇所で固定仮定。YAML構造変更で沈黙死（cmd_370）
- L071: SCRIPT_DIR設計パターンが2系統混在(リポルート基準 vs scripts/自身基準)で新規スクリプト作成時に混乱リスク（cmd_370）
- L072: git-ignoredスクリプトがwhitelist漏れで現役使用されるリスク — clone後に動作不全（cmd_368）
- L073: タスク指示のパス相対指定は実ファイル位置で必ず検証せよ（path-resolution,task-instruction-verification,security-boundary）
- L074: bash ((var++))はvar=0時にset -eで即exit — $((var+1))を使え（bash,set-e,arithmetic,trap）
- L075: L075（cmd_378）
- L076: deploy_task.sh旧Python -cブロックにL047違反が残存（cmd_384）
- L077: Vercel構造分離では全セクション移動先マッピングを事前作成せよ（cmd_383）
- L079: deploy_task.sh再配備でrelated_lessons.reviewedがfalseに戻る→入口門番BLOCK（cmd_387）
- L080: sync_lessons.sh新フィールド追加時はパース+キャッシュ保持の2箇所を更新必須（cmd_385）
- L081: 追記型YAMLファイルのフォーマット変更時は既存データのマイグレーションも必須（cmd_388）
- L082: Codexは~/.codex/を全エージェント共有。分離機構なし（cmd_390）
- L083: bypass-approvals-and-sandboxフラグ漏れで全操作が権限確認停止（cmd_390）
- L084: roles/ashigaru_role.mdは現在不存在 — build_instructions.shがashigaru.md直接処理（cmd_392）
- L085: 報告YAML命名変更はCLAUDE.md自動ロード+common/ビルドパーツ+全スクリプトの横断更新が必須（cmd_392）
- L086: auto_draft_lesson.shがlesson_write.shをCMD_ID空で呼ぶためlesson.done未生成（cmd_391）
- L087: 教訓効果メトリクスΔはBLOCKリトライ行膨張+構造BLOCK混入で歪む — cmd単位dedup+品質BLOCK分離が必須（cmd_397）
- L088: deploy_task.shタグ推定パターンが広すぎて平均4.6タグ→フィルタリング無効化。lesson_tags.yamlの汎用語(環境,注入等)を除去しmax 3タグ制限が必要（cmd_397）
- L089: universal教訓がdm-signalで30件(23%)に膨張し注入枠10件中5件を固定占有 — タスク固有教訓枠を圧迫して精度低下（cmd_397）
- L090: build_instructions.sh派生ファイル(gitignore対象)はCLAUDE.md修正だけではgit diffに現れない（cmd_403）
- L091: L085再発(派生ファイル未更新): CLAUDE.md変更時は全派生ファイルをACスコープに含めよ（cmd_403）
- L092: awk state machine複数エージェント属性パース時のリセット位置（cmd_404）
- L093: impl忍者のgit add漏れ — 新規ファイル作成時のcommit忘れ（cmd_404）
- L094: scripts/shutsujin_departure.sh(session設定)にモデル名ハードコード残存（cmd_405）
- L095: archive_dashboard()のgrep戦果行パターン不一致 — AUTO移行後は常にno-op（cmd_406）
- L096: preflight_gate_flags()でlocal変数をif/else跨ぎで参照する場合、両ブロックのどちらが実行されても参照可能なスコープ（関数先頭等）で宣言・初期化すべき。bashのlocalは関数スコープだが、宣言がif内にあると実行されないelseブロックでは未初期化になる。（cmd_407）
- L097: cmd_complete_gate.shのresolve_report_file()がgrep直書きでreport_filename取得 — L070除外対象外（cmd_410）
- L098: L_archive_mixed_yaml（yaml,archive,parsing,resilience）
- L099: backfill対象ログファイルのフォーマット事前確認の重要性（cmd_413）
- L100: gate_metrics task_type遡及の最適データソース（cmd_413）
- L101: gate_metrics.logはTSV形式(YAMLではない)（cmd_413）
- L102: lesson_tracking.tsvのデータソース相違 — タスク記述はqueue/gate_metrics.yamlだが実在はlogs/lesson_tracking.tsv（cmd_414）
- L103: skill.md(小文字)でスキル配置するとLinux native環境やCI等case-sensitive環境でClaude Codeがスキルを検出できない。WSL2はcase-insensitiveで動作するが移植性なし。SKILL.md(大文字)への統一が必要。該当: building-block-addition, fof-pipeline-troubleshooting（draft）
- L104: 本家参照時のパス揺れ — tree確認後に取得を標準化（cmd_438 sasuke）
- L105: E2Eテストでtmux pane-base-index依存は明示固定せよ（cmd_438 kirimaru）
- L106: lesson_impact_analysis.shのload_lesson_summariesパス誤り（cmd_444）
- L107: dedupログ仕様は文言と0件時出力条件をAC文字列と厳密一致させる（cmd_446）
- L108: compact_stateの長さ未制限による500文字超過リスク（cmd_452）
- L109: git commit時のstaging巻き込み防止（cmd_452）
- L110: settings.local.jsonはwhitelist外、並行レビューでcommit重複リスク（cmd_449）
- L111: ACに含めるテストファイルは配備時に実在確認が必要（cmd_460）
- L112: ninja_monitorのcheck_stall()がtask_idフィールドを参照するが現行タスクYAMLはsubtask_idのみ（cmd_462）
- L113: タスク指定ファイルが.gitignore whitelist外だとcommit要件を満たせない（cmd_463）
- L114: safe_send_clear独自idle判定(tail -3)がCLIステータスバーで❯を見落とし永久CLEAR-BLOCKED。idle判定は必ずcheck_idle()に一本化せよ。同一判定の重複実装は片方が必ず腐る（ninja_monitor,idle_detection,safe_send_clear）
- L116: .gitignore whitelist-basedリポジトリでは新規スクリプト作成時に必ずwhitelist追加が必要（cmd_466）
- L117: lesson_referenced→lessons_usefulリネーム時に全派生ファイル(generated/4本+roles/+templates/)を漏れなく更新する必要がある（cmd_466）
- L118: tmux set-optionのtargetがsession指定だとwindow optionが意図せずcurrent windowのみ更新されることがある（cmd_468）
- L119: deploy_task.shのpostcondファイル経由でbash→Pythonのデータ受け渡しパターンが確立（cmd_470）
- L120: report gateの存在判定はprefix検索+archive探索が必要（cmd_482）
- L121: YAML回転処理でヘッダ保持を欠くと後続appendが既存履歴を失う（cmd_490）
- L122: SKILL.md手順追加時に原則セクションとの矛盾を確認せよ（cmd_490）
- L123: tmuxターゲットにウィンドウINDEXを使用するな — NAME(固有名)を使え（cmd_494）
- L124: paste-bufferの-dフラグはタイムアウト時に発動しない — 明示的delete-buffer必須（cmd_494）
- L125: paste-buffer注入先はagent_id検証で防御せよ(defense-in-depth)（cmd_494）
- L126: [自動生成] 有効教訓の記録を怠った: cmd_497（cmd_497）
- L127: 再配備前に先行commit/reportの存在を確認すべき（cmd_494）
- L128: OSS参照タスクはcanonical repository解決を初手に入れる（cmd_506）
- L129: WSL2 Python3.12環境では外部feed偵察時にvenv未整備ケースがある（cmd_506）
- L130: Get-Clipboard -Format Imageは非画像時にnullを返す（cmd_508）
- L131: archive_completed.sh sweep modeはparent_cmd完了チェック必須（cmd_510）
- L132: dashboard_update.shは完了報告専用、進捗メモはEdit toolで記録すべき（cmd_511）
- L133: injection_countがlessons.yamlで全件0(未同期)（cmd_514）
- L134: NINJA_MONITOR_LIB_ONLYガードでbashスクリプトの関数テストが可能に（cmd_519）
- L135: build_instructions.sh は --help 指定でも生成処理を実行する（cmd_523）
- L136: preflight_gate_flags upgradeのhas_found_trueスコープ不整合でlesson_done_source BLOCKが頻発（cmd_529）
- L137: lesson_done先行生成とpreflight upgradeの設計的不整合（cmd_529）
- L138: レビューcmdは要求範囲外差分をBLOCK対象として明示判定すべき（cmd_528）
- L139: scope外変更のrevert確認では、正味diff(HEAD~N..HEAD)と個別commit diffの両方を突合すべき（cmd_528）
- L140: レビューFAIL指摘時はrevert対象を明示し、scope内差分を保持した最小修正で再提出すべき（cmd_528）
- L141: lesson_deprecation_scan.shの自動退役はsubprocessで外部スクリプト呼出のため、大量教訓がある場合に遅くなる可能性（cmd_531）
- L142: 飛猿報告のテスト8件はbatsテスト2件のみ — テスト件数根拠明示義務（cmd_532）
- L143: gitignoreエラーはgateログに記録されず暗数化する — 15日間で最低11件、モデル非依存（cmd_534）
- L144: git add失敗の頻度分析にはgate_metricsではなく専用guardログが必要（cmd_534）
- L145: ashigaru.md生成はbuild_instructions.shで行われる→source filesを修正すべき(L005の実践確認)（cmd_533）
- L146: AC6系レビューは実配備YAML確認だけでなく一時環境での再現実行を必須にすべき（cmd_533）
- L147: related_lessons.detail注入はlessons.yamlスキーマ依存 — 現行スキーマではAC6未達（cmd_533）
- L148: AC文言は値参照元変更以外(例: コメント追記)の許容範囲を明示すると判定ブレを防げる（cmd_532）
- L149: shellスクリプトでrgを使うな、grepを使え（cmd_537）
- L150: git commit --dry-runではpre-commitが走らずAC誤判定になる（cmd_537）
- L151: Git hook導入時はスクリプト内容だけでなく executable bit(100755) のコミット有無を必須確認（cmd_537）
- L152: KM_JSON_CACHEの無効化条件にlessons.yaml変更が含まれない（cmd_541）
- L153: レビューACにpush条件がある場合は事前に ahead/behind を確認する（cmd_546）
- L154: [自動生成] 有効教訓の記録を怠った: cmd_546（cmd_546）
- L155: lib/配下の共通関数は呼出し元の環境変数依存を明示バリデーションすべき（cmd_546）
- L156: set -e環境で共通関数の非0戻り値を直接受けると即時終了する（cmd_545）
- L157: 追記型YAMLの上限制御はappend直後に同一トランザクションで実施すべき（cmd_547）
- L158: ローテーション機能レビューでは境界値テストに加えて過剰初期データの実地検証が有効（cmd_547）
- L159: 大規模偵察タスクの並列Agent活用パターン（cmd_548）
- L160: ntfy添付DLはAUTH_ARGS再利用でprivate topicでも同一認証経路を維持できる（cmd_551）
- L161: 画像添付MIME整合改善の必要性
- L162: フックスクリプトテストではsymlink構造でSCRIPT_DIRリダイレクトするモック手法が有効（testing）
- L163: MAX_ENTRIES等の定数変更時は既存テストの前提値も同時更新が必要（testing）
- L164: Claude Code Hooksのshスクリプトはset -euのみ使用しpipefail禁止（hooks）
- L165: 教訓効果率は『未解決負債』だけでなく『仕組み化後の未退役』でも低下する（cmd_567）
- L166: ストリーミング受信デーモンは起動側pkillに依存せず、受信側でも単一起動ロックを持つべし（cmd_571）
- L167: ストリーム購読系デーモンは singleton lock + message idempotency を必須セットで実装すべき（cmd_571）
- L168: auto_draft_lesson.shのIF-THEN引数にスペース含む値を渡すと切り詰められる（cmd_575）
- L169: YAMLへの追記をheredoc直書きすると引用符/改行で構造破壊する（cmd_578）
- L170: terminalログ保存でバイト切り詰め(head -c)を使うとUTF-8破損が混入する（cmd_578）
- L171: Python呼出しパイプパターンexit code喪失 + bash→Python変数受渡しos.environ統一（cmd_585）
- L172: レビューでは『履歴位置確認』を先に行うと push 可否の誤判定を防げる（cmd_590）
- L173: build_instructions.sh再生成時はCLAUDE.md正本も同期→AGENTS系の旧表記残存を防止（cmd_604）
- L174: cmd_608（ストリーム購読デーモンのwatchdogがkeepalive/open行のread成功でも活動時刻を更新していたため、ntfyのkeepalive(45秒間隔)が流れ続けるとwatchdogが永遠延命され、実メッセージ停滞を30分で検知する設計が無効化された。LAST_STREAM_ACTIVITYとLAST_MESSAGE_ACTIVITYを分離し、message処理成功時のみ後者を更新すべき。2名独立一致）
- L175: ストリームwatchdogが任意の受信バイトで更新されるとkeepaliveで実メッセージ断を見逃す（cmd_608）
- L176: watchdogの活動時刻は『read成功』ではなく『意味のあるイベント処理成功』で更新すべし（cmd_608）
- L177: 追跡ログのキーをproducer/consumerで変える時は両側同時に整合させよ（cmd_611）
- L178: Claude Codeドキュメントのホスト移行（docs.anthropic.com→code.claude.com）（cmd_630）
- L179: 忍者がcommit未実施でdone報告するケース（cmd_648）
- L180: whitelist型.gitignore配下では新規ファイルのstage前にgit check-ignoreを確認する（cmd_649）
- L181: タスク記述と実際のgit状態の乖離確認（cmd_652）
- L182: 設定UIで保存した値が実行経路で読まれているか別経路まで確認せよ（cmd_658）
- L183: bashrc export検証は対話シェル前提を確認せよ（cmd_664）
- L184: set -u配下で任意引数を追加するbash関数は既存呼び出し互換を守れ（cmd_667）
- L185: report_path 注入だけで報告テンプレート未生成→忍者が手動補完（cmd_675）

## PD裁定反映（cmd_354同期）

| PD | 裁定 | 反映先 |
|----|------|--------|
| PD-037 | inbox_write.sh HIGH-1(Python直接展開インジェクション)+HIGH-2(パストラバーサル)修正。殿裁定2026-02-25 | L043修正済み。`scripts/inbox_write.sh` |
| PD-038 | ashigaru.md否定指示→案C(ハイブリッド)採用。forbidden_actions構造維持+positive_rule+reason追加。ACE準拠 | `instructions/ashigaru.md` cmd_324実装済み |

## SKILL.md品質基準（7項目チェックリスト）

スキル作成・更新時に必ず確認。発火精度はdescription品質で決まる。

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
