# インフラコンテキスト
<!-- last_updated: 2026-02-26 cmd_354 context鮮度更新 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
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

## 直近改善（cmd_336〜cmd_351）

| cmd | 改善 | 結論 |
|-----|------|------|
| 337 | dashboard_update.sh | cmd_complete_gate.sh GATE CLEAR時にダッシュボード自動更新。手動更新漏れ排除 |
| 338 | auto_deploy_next.sh | サブタスク完了時にninja_monitorが次サブタスク自動配備。idle検知依存で最大25秒ラグ(L057) |
| 339 | F007ゲート迂回防止 | cmd_complete_gate.sh以外のstatus変更をブロック。教訓循環のゲート迂回を防止 |
| 348 | lesson_tracking.tsv | 教訓注入・参照の追跡ログをTSV永続化。タスクYAML上書き問題(L060)を解決 |
| 349 | タグベース教訓注入 | deploy_task.shがタスクtags[]と教訓tags[]をマッチング。関連教訓の自動注入 |
| 350 | lesson_deprecate.sh | deprecated教訓を注入対象から除外。非活性教訓の淘汰機構 |
| 351 | shogun-teire観点⑧ | 教訓効果監査。inject/ref比率・deprecated率・未タグ率を検査 |

→ 各スクリプト実装: `scripts/` 配下

## ninja_monitor.sh

idle検知+/clear送信、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
auto-done判定: parent_cmdだけでなくtask_idも一致チェック必須。Wave間で誤done発生実績あり(L048)。
auto_deploy統合(cmd_338): auto-done後にauto_deploy_next.sh自動発火。次サブタスク自動配備。
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
→ `docs/research/infra-details.md` §5

## tmux設定

prefix=Ctrl+A。session=shogun、W1=将軍、W2=agents(家老+忍者9ペイン)。形式: shogun:2.{pane}
上忍: hayate kagemaru hanzo saizo kotaro tobisaru / 下忍: sasuke kirimaru。CLI→`config/settings.yaml`

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
→ `queue/reports/saizo_report.yaml`(API仕様詳細) / `queue/reports/kirimaru_report.yaml`(マルチアカウント方式)

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8

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
<!-- last_synced_lesson: L102 -->
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

## PD裁定反映（cmd_354同期）

| PD | 裁定 | 反映先 |
|----|------|--------|
| PD-037 | inbox_write.sh HIGH-1(Python直接展開インジェクション)+HIGH-2(パストラバーサル)修正。殿裁定2026-02-25 | L043修正済み。`scripts/inbox_write.sh` |
| PD-038 | ashigaru.md否定指示→案C(ハイブリッド)採用。forbidden_actions構造維持+positive_rule+reason追加。ACE準拠 | `instructions/ashigaru.md` cmd_324実装済み |
