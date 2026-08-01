## deploy_task.sh --direct mode（cmd_1672）

deploy_task.shにdirect mode(`--direct`)追加。修行タスク等shogun_to_karo.yaml不在のタスク配備時に、report template生成+stale cleanup+教訓注入を実行可能に。GP-138実装。
使用法: `bash scripts/deploy_task.sh --direct <ninja> <task_id>`
→ `scripts/deploy_task.sh` L31(フラグ解析), L2935(DIRECT_MODE分岐)

## /henseiスキル（cmd_1673）

モデル編成一括切替スキル。`~/.claude/skills/hensei/SKILL.md` + `~/.claude/skills/hensei/scripts/hensei_apply.sh`。
プリセット: `opus-all`(全忍者Opus統一), `mixed`(GPT2+Sonnet2+Opus2混成)。
idle安全機構: in_progress/acknowledged忍者のCLI操作スキップ(settings.yaml更新のみ→次回clear反映)。
⚠ **dry-run未実装(L431)**: テスト時にmodel_switchが本番送信される。テスト時注意。
→ `~/.claude/skills/hensei/`

## Claude CLIモデル指定とコンテキスト（ci_fix_200k）

| 起動方法 | コンテキスト | effort | コスト |
|----------|-------------|--------|--------|
| `claude`(デフォルト、--modelなし) | **1M** | Max利用可 | 1x |
| `claude --model opus` | 200K | Highまで | 1x |
| `claude --model sonnet` | 200K | — | 0.2x |

**修正(b3f55d9)**: `build_cli_command()`でopus時は`--model`スキップ → デフォルト1M起動。sonnet/haikuのみ`--model`指定。
**殿裁定**: high effortで十分(Max=3-10xコスト、レートリミットリスク)。
**モデル切替はrespawn方式**(殿裁定): `/model`コマンドではなくCLI再起動(respawn)が正しい手順。理由: (1)/model opusは200Kになる (2)claude↔codexは/modelで切替不可 (3)respawnならCLAUDE.md/instructions再読込が保証される。/henseiスキルもrespawn方式に再設計要。
**Codex config SSOT貫通(cmd_4109)**: respawn前の`codex_config_apply_agent`がsettings.yamlからconfig.tomlを再生成し、restoreは行わない。restore撤去によりSSOTがライブへ貫通する。
**CLI種別がモデルファミリーを決定（殿指摘2026-06-21）**:
| CLI | モデルファミリー | effort指定 | fast指定 |
|-----|-----------------|-----------|---------|
| Claude CLI (`~/bin/claude`) | Claude系(Opus/Sonnet/Haiku) | `--effort low\|medium\|high` | `/fast`トグル |
| Codex CLI (`codex`) | GPT系(gpt-5.5等) | `config.toml model_reasoning_effort` | `config.toml service_tier=fast` |

**GPT-5.5を使うにはCodex CLIが必要**。Claude CLIで`--model gpt-5.5`を指定しても表示が変わるだけで実際のモデルはClaude系のまま。
**settings.yamlのmodel_nameは表示メタデータ**。CLIの実行モデルを決定しない。実モデルはCLI種別+起動設定で決まる。
**anti-pattern（殿指摘）**: 動いているCLIに`/model`コマンドを送る、settings.yamlだけ変更する、は全て失敗する。正道=paneを殺す→正しいCLI+設定で起動。
**Codex exit 2根因（2026-06-21解決）**: Claude CLIのターミナル設定がrespawn-pane -k後も残留→Codexが不正ターミナル状態で起動→exit 2。対策=switch_cli_mode.shがrespawn前に`reset`実行+cooldown 5秒。双方向6連続100%成功で検証済み。
**codex CLI**: デフォルト272K。1Mには`~/.codex/config.toml`に`model_context_window=1000000`+`model_auto_compact_token_limit=900000`必要。デフォルトモデル=gpt-5.5(旧gpt-5は廃止名)。effort=config.tomlの`model_reasoning_effort`。
→ `lib/cli_adapter.sh` L88 | 詳細: `docs/research/gunshi-cli-model-context.md`（respawn手順/セレクタの罠/effort優先順位/codex config設定方法）

### Codex multi-CLI統合(2026-05-11確立)

**2026-06-24上書き原則**: CLI固有hook設定(`.claude/settings.json` / `.codex/hooks.json`)を安全網の正本にするな。正本は共通イベント層(`config/cli_events.yaml`)とし、同一実装の押し付けではなくCLI能力に合わせたadapterへ落とす。Codex最新版は`SessionStart`/`UserPromptSubmit`/`Stop`を公式サポートするが、Codex同一event hookは並行実行されるため、順序依存処理は単一adapterに合成する。Codex Stop block系は旧事故があるため未検証のまま戻さず、daemon/gate/scriptで等価保証する。詳細設計: `docs/research/multi-cli-hook-event-commonization-design_20260602.md`。因果: [[multi_cli_hook_gap]] -> [[codex_stop_block_loop]] -> [[cli_capability_adapter_required]]。

**因果確認L0-L7**: hook/gate/daemon/semantic/search等を変更する前に、git log/blame、教訓、設計書、semantic/causal linksで「なぜ現在の実装がそうなっているか」を確認する。multi-CLI前提のため、因果確認の強制もClaude/Codex固有hookではなく、`cmd_save.sh`、`deploy_task.sh`、`gate_report_format.sh`、task/report YAML、memory DB、semantic index、daemon/gateを正本にする。詳細: `docs/research/causal-verification-l0-l7-design_20260602.md`。因果: [[semantic_search_timeout_infra_bug]] -> [[past_design_intent_unchecked_risk]] -> [[causal_verification_l0_l7_required]]。

**hook速度偵察(cmd_3189)**: Bash no-op実測はPre 90.8ms(2 forks)+Post 76.8ms(3 forks)=167.6ms/呼出し。設計方針は品質チェック削除ではなくdispatcher統合で、PreToolUse 6設定→`pretool-dispatch.sh`、PostToolUse 4設定→`posttool-dispatch.sh`へ寄せ、95-115ms/呼出しを目標にする。実装時の必須リスク確認: permissionDecision出力順序、不要tool dispatch、Read→Write順序、DM-Signal PI混入、Claude/Codex設定差分。

| 項目 | 設定 | 正本 |
|------|------|------|
| config | `~/.codex/config.toml` | `project_doc_max_bytes=131072`(87KB超対応)。`[features] hooks=true`必須(`codex_hooks`は非推奨) |
| hooks | `.codex/hooks.json`(プロジェクトレベル) | Codex公式hookをCLI能力adapterとして使う。`SessionStart`→`scripts/hooks/codex_session_start.sh`、`UserPromptSubmit`→`scripts/hooks/codex_user_prompt_submit.sh`。Codexは同一event内hookを並行実行するため、`log_terminal_input.sh`と`prompt_state_inject.sh`を別hookに分けるな。Stop block系は未検証のため戻さずdaemon補完 |
| hook BLOCK | `emit_deny()`内で**exit 2** | exit 1=hookエラー(CLIクラッシュ)。exit 2=意図的BLOCK(CLI続行)。Claude Codeはexit 1でも続行するがCodexは死ぬ |
| hook承認 | 対話paneは`/hooks`でtrust。自律tmux paneは外部hook/schema Gate通過後、Codex公式automation用`--dangerously-bypass-hook-trust`を`cli_profiles.yaml`のCodex `launch_args`から付与 | hook定義hash変更のたび対話UIで全pane停止するため。手動launch_cmd直書きは禁止し、共通profileで全Codex paneへ適用 |
| skills | `~/.codex/skills/` → プロジェクト正本symlink | 独立コピー禁止。`ln -s /mnt/c/tools/multi-agent-shogun/skills/{name}`でsymlink。skill_auto_improve.shの改善が即反映 |
| Skill tool | Codex CLIは`/skills`コマンドでスキル一覧表示・実行可能 | Claude CodeのSkill toolと同等機能 |
| doc読込制限 | `project_doc_max_bytes` | AGENTS.md+CLAUDE.md合計が制限超→切り捨て。128KB以上を推奨 |
| セッションリセット | `/new`(セッション新規) | config.toml変更反映にはCLI再起動(respawn-pane)が必要。`/new`ではconfig再読込されない |
| **Stop hook** | `{"decision":"block"}`の挙動差異 | **Claude Code**: メッセージ表示+ターン停止。**Codex**: reason文をプロンプトとして再実行=**無限ループ**。忍者done/completed時はblockせずidle flag+exit 0。quoting脆弱性検証→ [[cmd_1755_stop_hook]] (`docs/research/cmd_1755_stop_hook.md`) |
| **launch_cmd** | `cli_profiles.yaml` | Codexは**絶対パス必須**(`/home/.../bin/codex`)。respawn-paneは.bashrc未読込→nvm PATHなし→`codex: command not found` |
| **respawn方式** | `ninja_monitor.sh safe_send_clear()` | Codex再起動は`tmux respawn-pane -k`方式。Ctrl-C方式はcodex=PID 1終了→pane dead→relaunch届かない |
| **clear/dead/CLI-dead共通復旧境界** | `scripts/lib/respawn_recovery.sh` | pane PID+`/proc/<pid>/stat` starttimeのgeneration変化、pane live、CLI banner、CTX0を共通ready条件にし、task identityを維持したままrecovery通知をexactly-once配送する。`cmd_karo_hotfix_respawn_resume_exactly_once_202607191154` / `26eb1742a` |
| **monitor/deploy同一agent境界** | `scripts/ninja_monitor.sh` + `queue/locks/deploy_ninja_<agent>.lock` | AUTO-DONEとdeployを同一lockで直列化し、idle-cycle通知もsnapshot後に全agentのlive task YAMLを同lock下で再検証する。assigned/in_progressが1件でもあれば通知0、真の全idleだけ通知1。`cmd_karo_hotfix_monitor_deploy_lock_atomic_202607191207` / `842b982b1` |
| **利用量モニタリング** | `usage_monitor.sh` + `usage_status.sh` | upstream ratelimit_check.sh(tmux capture方式)との比較→SQLite直接集計方式が安定。[[cmd_1756_ratelimit]] (`docs/research/cmd_1756_ratelimit.md`) |
| **Codex idle時も respawn-pane -k 必須** | 設計意図(殿裁定2026-05-20) | `/new`はCodex CLI内部状態が「task in progress」だと拒否される。ninja_monitorがidle判定しても、CLI内部はsession activeのまま→`/new`非互換。respawn-pane -kはCLI内部状態に関係なくpaneプロセスを殺して再起動するため唯一確実なリセット手段。cmd_2904/2906で/new経路に変更→3忍者CTX滞留(51%/55%/43%)で実証。一見乱暴だが理由がある設計。198回/日ループの真因は発火条件(デバウンス/idle判定頻度)側であり、respawn手段を変えるべきではない。因果: [[cmd_2904_overfix]] -> [[codex_new_rejected]] -> [[respawn_is_correct_design]]。カタログ: `docs/research/gunshi_idle_infra_design_intent_catalog_20260520.md` |

### 直近24日間の主要裁定/実装（2026-05-01〜2026-05-24）

| 領域 | 結論 | 根拠 |
|------|------|------|
| Codex reset | Codex idle時も`tmux respawn-pane -k`必須。`/new`経路へ戻すな | cmd_2904/2906/2907、殿裁定2026-05-20 |
| 記憶DB | lord_conversationはJSONL/アーカイブを一次データ、SQLiteを検索層として扱う | cmd_2963〜2982、cmd_3001/3002 |
| target filter | 殿発言検索は`direction=inbound`の前にtarget/agentスコープを必ず確認 | cmd_3008/3009/3017/3028、L689/L698 |
| CI並列隔離 | 並列Bats/CIでは共有状態を4系統で隔離: (1) per-test `TEST_TMPDIR`、(2) lock/cacheをTMPDIR配下、(3) script_dir基準の絶対パス、(4) repo内scriptはgit実行権限または`bash script.sh`呼出 | cmd_2663/2975、L477/L488/L535/L536/L690/L691/L694 |
| 新スクリプトCI | 新規script追加時はscript_dir絶対パス、git mode 100755またはbash経由テスト、既存実行パターン踏襲の3点確認 | `logs/archive/gunshi_review_log_20260524a.yaml` の `idle_ci_red_chain_new_script_20260523` |

## Claude Code バージョン固定と復帰

現在v2.1.87に固定。`config/cli_profiles.yaml`の`launch_cmd`が正本。

| 操作 | launch_cmd | 備考 |
|------|-----------|------|
| **v2.1.87固定** | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | 現在の状態 |
| **auto-update復帰** | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | updater管理symlink |

切替手順(全体): launch_cmd変更 → `bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru` でrespawn。backup3本(`~/bin/claude`, `claude.pinned`, `claude-2.1.87-stable`)で復元可能。
切替手順(pane単位): `bash skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest --agent hayate` で特定paneだけ最新版。`pin-2.1.87 --agent hayate` でピン止めに戻す。settings.yamlの個別launch_cmdをcli_lookup.shがオーバーライド。
**重要**: `pin-2.1.87` / `unpin-latest` が切り替えるのは Claude Code の版だけであり、model/effort とは別軸。`unpin-latest` だけでは `Opus 4.8 xhigh` にならない。最新版の Opus 4.8 xhigh にしたい時は、(1)`unpin-latest --agent <name>` で最新版バイナリへ寄せる → (2)`settings.yaml` の `model_name=opus-4-8-xhigh` と `launch_cmd="~/.local/bin/claude --dangerously-skip-permissions --model opus --effort xhigh"` を設定 → (3)idle pane を `tmux respawn-pane -k` で再起動、の三段で行う。確認も `settings.yaml` / `launch_cmd` / `capture-pane` バナーの三点照合が正本。
→ `docs/research/claude-code-version-runbook.md`（全手順+緊急ロールバック+復元方法）
→ `skills/shogun-cli-switch/SKILL.md`（スキル詳細）

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
- L958: cmd_complete_gate.sh(set -e)でbare呼出しされるGATE CLEAR後処理関数は末尾コマンドの失敗が関数外へ伝播しないことを保証せよ（cmd_karo_hotfix_task_idle_transition_verify_202607041407）
- L962: verdict missingはverdict欄ではなくbinary_checks未記入を疑う（cmd_training_L1_report-write_20260704141831）
- L963: context freshnessは発火ログとsource差分を分けて報告する（cmd_karo_hotfix_ga178_dm_signal_ops_context_freshness_2026070500）
- L966: WAログ品質ゲートをCLEAR cmd集合で再フィルタすると直近WAを隠す（cmd_karo_hotfix_ninja_wa_rate_zero_202607051012）
- L968: context freshness taskは外部commit path headingsを注入せよ（cmd_karo_hotfix_ga180_context_freshness_202607060126）
- L969: lesson_health未振り分けは閾値前から将軍/lesson-sort入力を自動生成する（cmd_karo_hotfix_ga182_lesson_health_202607060248）
- L970: dm-signal分割context5ファイルは独立last_updated+閾値3跨ぎで時間差連鎖ALERTする(バグではない)（cmd_karo_hotfix_ga181_context_freshness_202607060242）
- L971: lesson_health同型ALERTの重複recon配備はGA-166(L934)の未実装で根治しない（cmd_karo_hotfix_lesson_health_ga183_202607060939）
- L972: GA再発連鎖はLevel5実装で初めて閉じた（cmd_karo_hotfix_ga184_lesson_health_early_route_202607061018）
- WA重複判定は`cmd_id+ninja`だけで同一視しない。check/fix双方をcanonical原因単位（`root_signature`、legacyは`category/detail/root_cause` fingerprint）へ揃え、異根共存・同根後勝ち・clean優先をfixtureで固定する。→ `scripts/gates/gate_wa_data_quality.sh` / `tests/unit/test_gate_meta_quality.bats`（cmd_karo_hotfix_wa_duplicate_identity_data_restore_202607140312）
- WAの`category=clean`は`--clean`専用であり、通常/`--wa`経路はlock・write前にBLOCKする。品質ゲートは`workaround=true && category=clean`をdetail非依存で検出し、既存atomic replace経路で`workaround=false`へ修復する。→ `scripts/karo_workaround_log.sh` / `scripts/gates/gate_wa_data_quality.sh` / `tests/unit/test_gate_wa_data_quality.bats`（cmd_karo_hotfix_wa_clean_contradiction_202607191718、fixture 9→0・FP0/FN0・48/48 PASS）
→ `scripts/cmd_complete_gate.sh` / `scripts/gates/gate_dc_duplicate.sh`

## 知識サイクル現状（cmd_531/533/541/1111/1113/1117 反映）

教訓の蓄積→注入→参照→淘汰を自動で回す仕組み。家老が健全性を問われたらここを読め。

### 稼働中の仕組み

| 仕組み | 実装先 | 導入cmd | 動作 |
|--------|--------|---------|------|
| MAX_INJECT=5 | deploy_task.sh | cmd_531 | タスクあたり注入上限5件。helpful_count降順で優先。超過分はwithheldとしてlesson_impact.tsvに記録 |
| タグベース注入 | deploy_task.sh | cmd_349 | タスクtags[]と教訓tags[]をマッチングし関連教訓を自動注入 |
| 自動退役 | lesson_deprecation_scan.sh + lesson_write.sh --retire | cmd_531 | 有効率10%未満×注入10回以上→SSOTへretired記録。ファイル消滅教訓も自動退役。GATE CLEAR時に自動実行 |
| 効果率監視 | gate_lesson_health.sh | cmd_531 | 直近30cmdの効果率計算。50%未満→WARN(ntfy)、30%未満→ALERT(ntfy+ダッシュボード) |
| lesson_candidate検証 | cmd_complete_gate.sh | cmd_528 | 報告YAMLのlesson_candidateフォーマットをゲートで検証。旧形式(リスト)→BLOCK |
| lesson_tracking.tsv | cmd_complete_gate.sh | cmd_348 | 教訓注入・参照の追跡ログをTSV永続化 |
| PDサマリー自動更新 | pending_decision_write.sh | cmd_541 | PD書込み/resolve時にpending_decisions.yaml冒頭のtotal/resolved/pending件数を自動更新 |
| context未更新ゲート | cmd_complete_gate.sh + deploy_task.sh | cmd_543 | cmd YAMLにcontext_update指定→deploy時に忍者タスクへ伝播→GATE時にlast_updated検査→stale時BLOCK |
| context鮮度監視整合 | context_freshness_check.sh + gate_context_freshness.sh | cmd_1889 | dashboard WARNとgateの監視対象を統一。直近completed cmdがあるactive projectのcontextのみ監視し、放置WARNの対象を一次データ基準へ揃える |
| CMD年代記 | archive_completed.sh | cmd_544 | cmd完了→archive時にcontext/cmd-chronicle.mdへ1行自動追記。月別セクション+flock排他 |
| Read追跡hook | settings.json hook | cmd_1044 | Write/Edit前に未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| タスク/報告YAML hook強制 | settings.json hook | cmd_1065/1067 | queue/tasks/*.yaml, queue/reports/*.yamlへの直接Write/Editを無条件deny。deploy_task.sh/report_field_set.sh経由のみ許可 |
| 家老教訓自動ロード | instructions/karo.md | cmd_1111 | /clear Recovery手順にlessons_karo.yaml読込を追加。教訓参照漏れ防止 |
| gate穴検出3問トリガー | gate_improvement_trigger.sh | cmd_1113 | GATE CLEAR時に3問で防御層の穴を自動検出。ninja_monitor定期巡回に統合(cmd_1114) |
| hook失敗自動記録 | 報告テンプレート+ashigaru.md | cmd_1117 | hook_failures欄で失敗を構造化記録。穴検出3問と自動連鎖。詳細テンプレート→ [[ashigaru-detail]] (`docs/research/ashigaru-detail.md`) |
| 自動トリム | archive_completed.sh | cmd_1119/1120 | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive時に自動トリム |

### 現行メトリクス（2026-03-30時点）

| 指標 | 値 | 備考 |
|------|------|------|
| 教訓総数(SSOT) | 152件(退役5件) | tasks/lessons.md |
| 教訓参照率 | 82.4% | lesson_tracking.tsv（391タスク中322件が参照） |
| 注入/除外比 | injected:1398 / withheld:763 | MAX_INJECT=5の効果。35%がフィルタリング |
| 初回CLEAR率 | **84.6%**(+21.9pt, cmd_1543計測) | gate_metrics.log。cmd_1532-1543改善効果 |
| 手戻り率 | 1.3% (1/77cmd) | fixes付きcmd |

### 設計思想

helpful/harmful手動評価に依存しない。注入回数と参照率を代理指標として自動で品質制御する。
- L418: ランブック品質はdb-operations-runbook以外極めて低い。28件中22件監査、21件が教訓参照ゼロ。ランブック品質底上げにはlesson索引セクション追加とPIの明示的組込みが必要（cmd_1094）
- L247: found:falseは教訓を探さなかった証拠。全タスクに学びがある。no_lesson_reason必須化+家老差し戻しルール追加（cmd_1104）
- L249: 教訓還流の仕組み変更は3層同時修正必須: ashigaru.md+deploy_task.sh+karo.md（cmd_1104）

## SessionStart hook — startup gate自動実行（cmd_2683）

session_start_inject.shが全ロールのstartup gateをセッション開始時に自動実行し、結果をadditionalContextに注入。
旧裁定(2026-04-12: /clear後gate自動実行禁止)は殿裁定(2026-05-12)で解除。前提変更: debounce 300-600秒+report_gate+safe_send_clearで/clear誤発火が改善済み。
対象: shogun→gate_shogun_startup.sh, karo→gate_karo_startup.sh, gunshi→gate_gunshi_startup.sh。exit 0固定(BLOCKしない設計)。

## 二重配備防止3層防御（cmd_2681/2682/2684）

| 層 | スクリプト | 防御ポイント | 方式 |
|----|-----------|-------------|------|
| L1 | deploy_task.sh | 配備時(事前阻止) | flock排他+完了報告YAML検知→BLOCK |
| L2 | ninja_monitor.sh | 巡回時(事後回収) | 先行完了検知→後発auto-void(idle化+/clear) |
| L3 | inbox_write.sh | 全配備経路(統一ガード) | task_assigned時に同一parent_cmd検査→BLOCK |

根因: cmd_2678-2680で同一cmdに2名配備→先行完了→後発空報告→レビュー+クリーンでトークン浪費(3連続)。

## 暗黒物質Phase 2: 高優先度60関数（cmd_2777）

cmd_2775偵察でcontext未記載だった238関数のうち、他エージェントの運用フロー・状態遷移に直接影響する60関数を受動知識化。調査時は関数名でgrepして到達せよ。

### ninja_monitor.sh: 状態管理・配備・監視・自動化（26件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 状態管理 | `write_karo_snapshot` | 家老復帰用の陣形図を生成し、cmd・忍者状態・報告状況を集約する。重い監視処理より前に早期発行し、temp file + mvでatomic publishする。 |
| 状態管理 | `check_idle` | pane実態から忍者/家老がidleかを判定し、誤clearや誤配備を防ぐ入口になる。 |
| 状態管理 | `handle_confirmed_idle` | idle確定後の通知・auto-clear・auto-deployなど後続処理を統括する。 |
| 状態管理 | `handle_busy` | busy中paneの監視状態を更新し、idle向け処理を発火させない。 |
| 状態管理 | `update_inbox_counts` | tmux pane変数へ未読inbox数を反映し、nudge欠落時の復元材料にする。 |
| 状態管理 | `discover_panes` | tmux上のagent paneを探索し、監視対象一覧を更新する。 |
| clear制御 | `safe_send_clear` | CLI種別とreport gateを考慮して安全に/newまたは/clearを送る中核。 |
| clear制御 | `send_karo_clear` | 家老paneへ復帰用clearを送信し、陣形図付き復帰を成立させる。 |
| clear制御 | `check_karo_clear` | 家老clearの必要性を判定し、pending状態との競合を避ける。 |
| clear制御 | `can_send_clear_with_report_gate` | report未完了・未処理状態を見てclear送信可否を判定する防御層。**status=done専用**(failedは対象外でrespawnを止めない、意図的)。 |
| clear制御 | `_failed_task_needs_karo_notice` | task status=failedのninjaについて、GATE CLEAR済み/軍師review済み/parent_cmdなしを除外し家老通知が必要かを判定する(cmd_karo_hotfix_failed_report_clear_notify_gap)。 |
| clear制御 | `_notify_failed_respawn_result` | failed taskのrespawn実行結果(成功/失敗)を起点に`notify_karo_durable`でkaroへdurable通知する。**respawn自体はBLOCKしない**(殿裁定2026-07-12)。 |
| clear制御 | `notify_karo_durable` / `flush_karo_notify_outbox` | karo通知をinbox_write経由で試行し、配送失敗時はoutbox(`$STATE_DIR/karo_notify_outbox.tsv`)へ永続化して次サイクルでretryする。paneを止めて代替放置を作らない設計。**契約(2026-07-12明確化)**: direct成功またはoutbox永続化成功はreturn 0、outbox append自体の失敗のみreturn 1。 |
| clear制御 | `_karo_pending_work_already_notified` / `_karo_pending_work_mark_notified` / `_karo_pending_work_clear_marker` | `check_inbox_renudge`のpending_work通知(karo inbox未読0時のdone/failed未処理検出)を世代fingerprint(worker+task_id+parent_cmd+status+report内容md5)単位で`$STATE_DIR/karo_pending_work_notice.tsv`へdurable dedupeする。判定は副作用なし比較のみ、確定は`notify_karo_durable`成功後のみ、pending集合0件化時はmarkerをclearする(cmd_karo_hotfix_pending_work_generation_dedupe_202607121023)。 |
| pending/cmd監視 | `check_karo_pending_cmd` | 家老が処理すべきcmdの滞留を検出し、再nudge判断に使う。 |
| pending/cmd監視 | `check_karo_pending` | 家老pending全般を確認し、idle家老への復帰・再通知を制御する。 |
| pending/cmd監視 | `check_undeployed_cmds` | 未配備cmdを検出し、配備漏れを家老へ通知する。 |
| pending/cmd監視 | `check_stale_cmds` | 古いcmd状態を検出し、stale作業や放置を表面化する。 |
| 整合性回収 | `check_report_done_idle_mismatch` | 報告doneとpane/task状態の不一致を検出し、ghost状態を回収する。 |
| 整合性回収 | `auto_void_if_parent_cmd_completed` | parent cmd完了後に残る後発タスクを自動voidし、二重配備被害を止める。分割配備では `subtask_id` を `task_id`/`_ac_task_id` より優先して照合し、同一parent_cmd内の別担当taskを他忍者の完了報告で誤voidしない（cmd_3515/LK010）。 |
| handler | `_handle_auto_clear` | auto-clear条件成立時の実処理を担う内部handler。 |
| handler | `_handle_idle_notify` | idle通知の送信・抑制を扱う内部handler。 |
| handler | `_handle_deploy_stall` | 配備後STALLを検知し、本人/家老への回復通知へつなぐ。 |
| 修行自動化 | `_training_condition_met` | training自動配備の発火条件を判定する。 |
| 修行自動化 | `_handle_training_auto_deploy` | training候補をidle忍者へ自動配備する処理を担う。設計正本は[[training-cycle.md]]。 |
| bash速度修行 | `tools/bash_speed_training.sh` + `logs/script_speed_training_ledger.yaml` + `_handle_speed_training_auto_deploy` | scripts配下254本を非破壊`bash -n` baselineで台帳化し、pendingがあれば既存training_autoより先にidle忍者へ配備する。停止/再開はledgerの`global_status: running/paused`。 |

**script-speed台帳writer不変量**: init・reserve/assignment・re-enqueue・global-status・結果更新を含む全writerは、同一lockの`flock`保持中に一時YAMLをparse検証し、同一filesystem上のatomic renameでのみ公開する。entry子要素のindentは親entryから相対算出し、Bashの`errexit`挙動に依存せずparse/公開失敗をfail-closedで返す。monitorはtask `idle`確認後にのみreserveし、deploy失敗時は同じ所有者の予約をlock内で`pending`へrollback、成功時だけ`assigned`を維持する。生成taskは`estimated_minutes: 5`を持ち、非dry-runの成功・失敗とも一時taskを削除する。→ `tools/bash_speed_training.sh` / `scripts/ninja_monitor.sh` / `tests/unit/test_bash_speed_training.bats` / `tests/unit/test_ninja_monitor_stall.bats`（commits `a7185f98b`, `e9a172bad`, `a7de056a6`）
| 修行計測 | L772 | tracked限定のリンク集計では未tracked対象の改善が見えない。全対象の改善率を計測するにはtracked/untracked両方を含むメトリクスが必要（cmd_training_L1_report_write_20260625_kagemaru） |
| 健全性監視 | `check_ninja_cli_dead` | 忍者CLI死亡を検知し、pane復旧や通知判断につなげる。 |
| 健全性監視 | `check_loop_health` | 監視ループ自体の健全性を確認し、停止や劣化を検出する。 |
| 健全性監視 | `check_inbox_renudge` | 未読inboxが放置されたpaneへ再nudgeする。 |
| 健全性監視 | `check_inbox_watcher_health` | inbox_watcherの稼働を確認し、通知経路の断絶を検出する。 |
| 健全性監視 | `check_ntfy_listener_health` | ntfy_listenerの稼働を確認し、殿通知経路の断絶を検出する。 |

**通知→clear順序不変量(cmd_karo_hotfix_failed_report_clear_notify_gap, 2026-07-12)**: `check_inbox_renudge`のKARO-PENDING検出は`status=done`専用だと`failed`報告(cmd_3861実例: report完成→task failed→無通知でCodex respawn)がpending work検知から漏れる。修正: done/failed両対象化(既存のGATE CLEAR済み/軍師review済み/parent_cmdなし抑止は維持)。一方`can_send_clear_with_report_gate`はstatus=done専用のまま変更せず、failed taskのrespawnは意図的に止めない(殿裁定2026-07-12 08:43: 「通知失敗でrespawnをBLOCKするな。BLOCKは別形態の放置を作る」)。正しい不変量は**auto-respawn実行結果を起点にしたdurable通知**(成功→clear済み+未完了report通知、失敗→respawn失敗通知)であり、配送失敗はoutbox(`notify_karo_durable`/`flush_karo_notify_outbox`)へ永続化してretryする。詳細→`docs/research/gunshi_idle_codex_respawn_loop_nazenaze_20260520.md`(関連事故の先行分析)。

**terminal report publish不変量(cmd_karo_hotfix_report_publish_review_ready_202607191728, 2026-07-19)**: `report_field_set.sh --batch`が`status=completed`をatomic公開した時点で、同一report fingerprintのcanonical completion parentと軍師review childを同期永続化する。atomic replace直後のpane dead/respawn窓はcompleted report自体をdurable outboxとし、`setsid+nohup`でpane process groupから分離したfast reconcilerが5秒以内に再送、`ninja_monitor.sh`はactive taskだけを後段修復する。`inbox_write.sh`のfingerprint transactionへ全retryを収束させ、steady terminalはpublisher 0とする。一次実測: report→notify中央値82.4秒→isolated p50 0.271秒/p95 0.302秒、failpoint復旧0.419秒、FP0/FN0/SKIP0、live inbox delta 0。→ `scripts/report_field_set.sh` / `scripts/ninja_monitor.sh` / `tests/unit/test_report_field_set_batch_throughput.bats` / `tests/unit/test_ninja_monitor_report_notify_alias.bats`

**二相review latency境界(cmd_karo_hotfix_review_gate_arrival_coalescing_202607191755, 2026-07-19)**: SG7生成→review中央値74.1秒は人のLGTM/ACCEPT判断を含むため、system待ちと分離して扱う。isolated全順序実測では両承認到着→triggerは正常397–899ms・逆順434–686ms・同時367–569ms、各trigger 1、同一承認retry後も1、revisionは片側新承認で旧count維持・両側新fingerprint承認後のみ次世代trigger、FP0/FN0/SKIP0・live write 0。既存のflock + fingerprint-bound approvals + manifest noclobber triggerで5秒SLOを満たすためsystem側の追加実装は不要であり、Karo ACCEPTを自動生成して人判断待ちを隠してはならない。→ `scripts/review_approval.sh` / `scripts/lib/review_approval.sh` / `scripts/cmd_complete_gate.sh`

**pending_work通知の世代dedupe不変量(cmd_karo_hotfix_pending_work_generation_dedupe, 2026-07-12)**: 上記のdone/failed両対象化後、`check_inbox_renudge`のKARO-PENDING通知は`RENUDGE_LAST_SEND[karo]`の120秒in-memoryスロットルのみで抑止しており、同一pending集合(worker+task_id+parent_cmd+status+report内容が全て不変)が続く限り2分周期で同一通知が再送され続けた(実運転RC、fixture再現で修正前10/10cycle通知)。修正: pending集合全体のcanonical世代fingerprintを`$STATE_DIR/karo_pending_work_notice.tsv`へ永続化し、同一世代はmonitor cycle・inbox既読化・monitor再起動を跨いで通知1回に抑える(修正後1/10cycle)。集合変化・report内容変化・0件化後の同一世代再出現(軍師review/GATE CLEARで一度解消→RC/reopen)はいずれも新世代として即時再通知する。判定(`_karo_pending_work_already_notified`)は副作用なしの比較のみとし、確定(`_karo_pending_work_mark_notified`)は`notify_karo_durable`が成功(direct成功またはoutbox永続化成功、戻り値0)を返した後にのみatomic tmp+mvで行う。先書きするとdirect失敗+outbox永続化失敗の場合に通知が永久に失われたまま抑止され続けるため、この順序を厳守する。

### deploy_task.sh: 注入・ゲート・配備制御（20件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 配備入口 | `deploy_task_main` | deploy_task.sh全体の入口で、配備前検査からtask/report生成までを統括する。 |
| 配備入口 | `check_idle` | 配備先paneがidleか確認し、作業中忍者への上書き配備を防ぐ。 |
| stale防止 | `reset_stale_fields` | 前task由来の残留フィールドを初期化し、stale contaminationを防ぐ。 |
| 注入 | `inject_related_lessons` | 関連教訓をtask YAMLへ注入し、忍者の受動知識を増やす。 |
| 注入 | `inject_ac_version` | ACハッシュをtask/reportへ注入し、AC差替えや古いtask実行を検出可能にする。 |
| 注入 | `inject_ninja_weak_points` | 忍者別WA傾向をtaskへ注入し、頻出失敗を作業前に可視化する。 |
| 注入 | `inject_task_id` | task_idを正規化して注入し、report/gate/monitorの照合キーを揃える。 |
| 注入 | `inject_semantic_concepts` | semantic mapから関連概念をtaskへ注入し、必要contextへの到達を補助する。 |
| 注入 | `inject_standard_skills` | report-write/verdict-check等の標準スキルをtaskへ注入する。 |
| 注入 | `inject_production_invariants` | PJの本番不変量をtaskへ注入し、実装前の違反を防ぐ。 |
| 注入 | `inject_checklist_constraints` | PJチェックリストや制約をtaskへ注入し、手順飛ばしを防ぐ。 |
| 注入 | `inject_growth_loop_defense` | 学習ループ防御情報をtaskへ注入し、計測→還流を強制する。 |
| 注入 | `inject_engineering_preferences` | PJ固有のengineering_preferencesをtaskへ注入する。 |
| report生成 | `generate_report_template` | 忍者報告YAMLテンプレートを生成し、提出形式を固定する。 |
| cmd解決 | `resolve_cmd_to_task` | cmd情報からtask化に必要なID・AC・scopeを解決する。 |
| gate | `check_entrance_gate` | 配備入口条件を検査し、危険な配備を事前に止める。 |
| gate | `check_scout_gate` | 偵察タスク向けの要件を検査し、低品質偵察を防ぐ。 |
| gate | `preflight_gate_artifacts` | 配備前に必要artifactやgate前提を確認する。 |
| postcondition | `postcondition_lesson_inject` | 教訓注入後の成立条件を確認し、注入漏れを表面化する。 |
| mutation | `deploy_task_apply_task_mutations` | task YAMLへの各種mutationを一箇所で適用する。 |

### inbox_write.sh: メッセージ管理・重複検出（9件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 書込み | `inbox_append_message_locked` | flock下でinboxへメッセージを追記し、lost updateを防ぐ正規経路。 |
| 書込み | `inbox_append_message_fast_locked` | 高速経路でinbox追記を行い、同時配信時もロック内で整合性を保つ。 |
| 重複配備防止 | `find_active_peer_deployments` | 同一parent cmdで稼働中のpeer配備を検出する。 |
| 重複配備防止 | `notify_karo_duplicate_deploy_block` | 重複配備BLOCKを家老へ通知し、配備判断を止める。 |
| unread管理 | `inbox_unread_count` | 対象inboxの未読数を数え、nudgeや復帰判断の材料にする。 |
| gate連携 | `trigger_cmd_complete_gate_background` | 完了報告受信後にcmd_complete_gateを背後で起動する。 |
| 宛先解決 | `list_active_ninjas` | 稼働中忍者一覧を取得し、通知対象や重複検査に使う。 |
| レビュー連携 | `forward_gunshi_review_result_to_active_ninjas` | 軍師レビュー結果を該当する稼働中忍者へ転送する。 |
| 件数確認 | `inbox_message_count` | inbox内メッセージ総数を数え、配送・既読化検証に使う。 |

Canonical report identity v2: 新規reportは配備世代UUIDをtask/report双方へ保存し、legacyはcanonical relative path SHA-256で読取時解決する。報告通知は`report_id/report_path/task_id/parent_cmd`を構造化伝搬し、v2欠落・不一致・別path再利用はBLOCKする（live 289/289 resolved・unique、duplicate 0、9/9 PASS・SKIP 0）。→ `scripts/lib/report_unique_identity.py` / `scripts/deploy_task.sh` / `scripts/inbox_write.sh` / `tests/unit/test_report_unique_identity.bats`（commit `3a305a0f5`）

No-code report identity: `commit_contract.required=false`かつtree不変を証明した報告はcommit identityをN/Aとし、code変更は従来どおりfull hashでfail-closedにする。同一generationのfull validationはfingerprint出口で1回に固定し、偽BLOCK 17→0・正当BLOCK漏れ0・検証2→1、31/31 PASS・SKIP 0。→ `scripts/lib/report_commit_identity.py` / `scripts/gates/gate_report_format.sh` / `scripts/report_field_set.sh`（commit `e7ab41112`）

### cmd_save.sh: 品質ゲート補助（5件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 終了制御 | `handle_cmd_save_exit` | cmd_save終了時のBLOCK/WARN表示や学習ループ連鎖を統括する。 |
| summary | `show_quality_summary` | cmd品質ゲート結果を要約表示し、将軍が修正点を把握できるようにする。 |
| hook検査 | `check_gate_hook_action_conversion` | gate発火後に行動変換へつながる記述があるかを確認する。 |
| 学習ループ | `parse_structured_environment_change` | environment_changeを構造化して読み取り、BLOCK後の環境改善を検証する。 |
| red flag | `check_bundle_red_flag` | SG7 bundle等の赤旗条件を検出し、cmd保存前に警告/BLOCKする。 |

**Phase 3リファクタ完了(cmd_3608〜3614)**: 113関数中82check関数を設計思想カタログ化済み。A層(40named funcs: うち27保護+13抽象化helper化)、B層(33inline checks→関数化)、C層(9名称乖離→名称修正済み)。全関数のorigin・防御対象・severity・教訓逆引きを一覧化。
**設計思想カタログ**: `docs/research/cmd_save_gate_catalog.md` — check関数のoriginと防御対象を逆引きできる中間レイヤー。教訓→カタログ→個別check関数の3段構造により、起票時にcheck関数の設計意図を確認可能。セマンティクス概念: `cmd_save_gate_catalog`

## ninja_monitor.sh

idle検知+コンテキストリセット送信（Codex=/new, Claude=/clear）、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
karo_snapshot/task completionのfast pathはpane待機・reflux・auto-commit等の重いmaintenanceより前に実行し、`task_status`と`runtime_state`を別列で発行する。done認識15分09秒+再巡回7分15秒の逐次loopを分離し、10秒maintenance敵対fixtureを含む3/3 PASS・SKIP 0。→ `scripts/ninja_monitor.sh` / `tests/unit/test_ninja_monitor_stall.bats` / `tests/unit/test_ninja_monitor_reflux_ledger.bats`（commit `8dd728a22`）
karo_snapshotは重いmaintenance/gate処理より前に早期発行し、temp file + mvでatomic publishする。古い表示残り/監視詰まりの再発防止はL851を参照。
実装正本は[[ninja_monitor.sh]]。修行自動配備の設計根拠は[[training-cycle.md]]、詳細仕様は[[infra-details.md]] §3を参照。
プルーン網羅検証(cmd_3744): `tests/unit/test_ninja_monitor_training_auto.bats` が `ninja_monitor.sh` の常駐連想配列を `_cleanup_stale_keys` のプルーン対象または理由付き除外へ分類し、未登録配列追加の境界入力でexit 1を確認する。個別リーク後追いではなく、配列追加時の漏れをCIで検出する。
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
- L956: ninja_monitorライブラリ関数はdaemon初期化変数に依存させない（cmd_karo_hotfix_dashboard_snapshot_stale_status_202607041407）
- L961: lib-only関数はdaemon初期化グローバルを直接参照しない（cmd_karo_hotfix_dashboard_snapshot_karo_pane_init_202607041426）
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
`queue/inbox` はClaude Code auto-memory連携のため意図的にsymlinkとして維持する。実体ディレクトリへ置換するとinbox_watcherが旧inode/別経路を監視し続け、未読ナッジが滞留する。symlinkを触る前に `ls -ld queue/inbox` とwatcher再起動要否を確認し、`rm`/`unlink`/`mv`/`mkdir`/`cp` で `queue/inbox` を操作する場合はpre-bash hookがWARNを出す(cmd_3453)。
プロセス構造: 親=本体(inotifywait+メインループ)、子=MTIME_POLLサブシェル(L960)。WSL2 DrvFsでinotifywaitがinode置換でhangする問題への対策として、stat mtimeポーリングを子プロセスで並列実行しmtime変化検知時にinotifywaitをkillする。psで2プロセス見えるのは正常（親子関係。二重起動ではない）。
2026-03-03 運用修正: Codexで`@agent_state=active`残留時はcapture-paneでidle/busyを再判定し補正。BUSY deferはretry消費しない。`profiles.codex.inbox_busy_max_defer_sec`(既定30秒)超過で強制nudge。
- L002: FG bashでnudge不可（cmd_125）
- L018: Edit tool flock未対応→inbox既読化はinbox_mark_read.sh必須（cmd_189）
- L029: nudge嵐=二重経路合流（cmd_255）
- L043: inbox_write.sh Python展開にインジェクション脆弱性（cmd_317）
- cmd_3828: `pre-write-edit-combined.sh` が `queue/inbox` の論理パスとsymlink解決先へのWrite/Edit/MultiEditをdeny。flock正規経路(`inbox_write.sh`/`inbox_mark_read.sh`/`inbox_archive.sh`)を強制し、inbox lost updateを構造封鎖。詳細→ `docs/research/cmd_3828_inbox_lost_update_guard.md`
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
殿への直接依頼で「通知が届くこと」自体が成果物の時は、引数は増やさず `NTFY_SYNC=1 NTFY_MIN_INTERVAL_SECONDS=0 bash scripts/ntfy.sh "msg"` で送信し、`logs/ntfy.log` の `http=200` を確認してから完了報告する。通常の fire-and-forget は exit 0 でも配送完了の証明ではない。
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
