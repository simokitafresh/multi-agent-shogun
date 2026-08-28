---
name: shogun-cli-switch
description: |
  multi-agent-shogun のCLI種別(Claude⇔Codex)とClaude Code version運用を切り替える。全ロールが殿の指示のもとに使用可能。
  switch-to-codex / switch-to-opus / shogun-claude-version-switch の上位互換。
  settings.yaml更新→tmux変数同期→idle paneのみrespawn。in_progress/active paneはスキップして設定だけ反映する。
  TRIGGER: /shogun-cli-switch、Claude auto-update再許可、2.1.87固定へロールバック、ピン留めOpus 4.6 1M、Claude version確認、pinned/latest切替、Claude⇔Codex切替、家老をCodexに、軍師をOpusに、CLI pane respawn、編成切替、忍者モデル編成、一括モデル切替、混成編成、モデル混成、Opus全戻し、決戦モード、全員Codex切替、Codex-only編成、緊急Codex編成、平時編成へ戻す、Codex-only解除、Claude復旧後ロールバック、ペイン死亡復旧、respawnせよ、GPT-5.5にしたい、GPTモデルに変更、モデルをGPTに、モデル変更
  DO NOT TRIGGER: 同一CLI内の /model 操作（Claude系内でOpus↔Sonnet等）、レイアウト全崩壊（scripts/reset_layout.shで復旧）
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-18T14:08:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_batch_b検分: ninja_monitor.sh 5be953b8/b5865875/edb0645a/046e8750/f955d556/e42ffe0c/8dd728a2/483a94ce/a7e7f42cをgit log/show。通知generation dedupe、failed即復帰、task-state fast path、reflux promotion原子予約を確認。CLI切替I/F、settings→tmux同期、dead/idle pane respawn、cli_launch_cmd契約は不変で本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T04:48:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_final_pair_202607180446検分: ninja_monitor.sh b89606cd6はreport通知済み判定をreport/task/parent_cmdのexact identity照合へ強化し、既読report_receivedの偽陽性反復を防止。CLI切替I/F、settings→tmux同期、dead/idle pane respawn、cli_launch_cmd契約には影響なし。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T04:24:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_shogun_cli_switch_refs_202607180425検分: ninja_monitor.sh ed5a31258/30cb653ddはforeign-dirty還流候補のfingerprint付き延期ledger追加と、読取専用走査のyaml.safe_dump→json.dumps置換。いずれもreflux inventory内部変更で、CLI切替I/F、settings→tmux同期、dead/idle pane respawn、cli_launch_cmd契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T03:18:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_freshness_batch検分: ninja_monitor.sh 4a122414/68847eb9/1be952b4/3ac5de57はreflux ledgerのevent化・reconcile・isolated inventory保全。CLI切替、idle/dead pane respawn、settings→tmux同期契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: ninja_monitor.sh 4a122414/68847eb9/1be952b4はreflux ledgerをevent-driven化+legacy一回reconcile。CLI切替/respawn契約不変。 -->
<!-- script_refs_checked_at: 2026-07-16T21:35:00+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_eight_202607162132検分: ninja_monitor.sh 348d1df9c/2a09dc71c/e9a172bad/432d78e71c/7b5a87837をgit showで確認。reflux/speed配備のidle・estimated_minutes・rollback/QUALITY_CONTRACT修正と重複source削除であり、CLI切替、settings→tmux同期、dead/idle pane respawn-pane -k、cli_launch_cmd契約は不変。本文変更不要。 -->

<!-- script_refs_checked_at: 2026-07-16T14:52:00+09:00 -->
<!-- cmd_karo_hotfix_failed_completed_blocked_terminal_202607161446検分: ninja_monitor.sh 3bb11a0a7はfailed taskのcompleted reportを共通report_terminal_state.shでCLOSED_BLOCKED判定し、完結済みBLOCKED偵察への再nudgeを抑止する内部状態分類変更。check_idle、dead pane復旧、cli_launch_cmd、respawn-pane -k、settings→tmux同期、shogun_cli_switch.shのCLI引数契約には影響なし。startup72/72+monitor70/70 PASS、SKIP0。本文変更不要。 -->
<!-- cmd_karo_hotfix_active_dead_pane_recovery_202607161035検分: ninja_monitor.sh a98021ebcはactive/assigned taskのpane_dead=1をdeploy/stall graceより先に検知し、respawn_dead_agent.shのCLI SSOT・dead-only拒否・flockを再利用して自動復旧する。live pane/idle taskは対象外。既存のCLI切替I/Fは不変だが、死亡pane復旧では手動respawnよりmonitor自動復旧を優先し、capture-pane+task statusで再開を確認する契約を本文へ反映。82/82 PASS、SKIP0。 -->
<!-- cmd_karo_hotfix_skill_refs_core_202607152126検分: ninja_monitor.sh 494e2c145/7fb06303bをgit showで確認。stale taskのauto-commit ownership除外と、死亡pane復旧時のCLI ready確認・最大3回retry・成否metrics追加。後者はmonitor自動復旧の信頼性強化であり、`shogun_cli_switch.sh`/`switch_cli_mode.sh`の引数、settings→tmux同期、対象paneの`respawn-pane -k`契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- script_refs_checked_at: 2026-08-01T19:15:00+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_reflux_b_20260801検分: yaml_field_set.sh 7a4748678はtask lease同時更新を追加。ninja_monitor.sh da8993f1d/0f4a9c887はowner transaction startup reconciliationのfail-close化とformal-close済みfailed通知抑止を追加。settings→tmux同期、idle/dead pane respawn、cli_launch_cmd、CLI切替I/Fは不変。 -->
<!-- cmd_karo_hotfix_skill_refs_202607151824検分: yaml_field_set.sh 7042b59e9をgit showで確認。indentless sequence field置換時の残存行防止のみで、settings更新CLI・atomic反映・tmux同期/respawn副作用契約は不変。 -->
<!-- 2026-07-15検分: ninja_monitor.sh 2faecab31はinbox pruning時のmessage_id evidence退避を追加。CLI切替・idle pane respawn・settings同期・respawn-pane -k契約には影響なし。 -->

<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_after_infra_202607151211: yaml_field_set.sh 6dd44d13fはlist item内の後置id探索を追加。settings更新・tmux同期・respawnの既存契約は維持。 -->

<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- cmd_3948検分: yaml_field_set.sh/ninja_monitor.sh直近差分はparse削減・terminal再開明示化。切替CLI契約不変。 -->
<!-- 検分: yaml_field_set.sh 386cb6bb(lock統一)、ninja_monitor.sh 6034dd0d/4a7c6f38/b2a69a65/066d4f06(容量guard、stage保全、終端FAIL dedupe)。CLI切替引数・respawn副作用・設定→実態確認順序は不変 -->
<!-- Script refs verified 2026-07-13 shogun復帰時: checked_at以降の変更(yaml_field_set wrapped scalar保持fix de3df4b83, deploy_task parent AC contract dbcb20aa2, ninja_monitor journal+flock 93f8c898e/16f16e699, db_capability_launcher scoped credential 84231a01c)をgit logで確認。全て内部強化で呼出し契約・出口文言不変 -->

Script refs verified: 2026-07-13 将軍検分. checked_at以降の変更: `yaml_field_set.sh` 692b6c8d8(post-write検証統一+安全エスケープ、契約不変)、`ninja_monitor.sh` dafb63d60等(通知timestamp durable化+完了gap formal approval連動=内部監視ロジック。親AC偽CLEAR hotfix RC継続中のため次回commit時に再検分される)。切替手順の書き換え不要。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: ninja_monitor.sh 3de92b6b/11047811/35d42cac。Codex respawn時のagent別config適用、明示pauseのSTALL除外、再配備前reportのAUTO-DONE除外はいずれもmonitor内部防御。switch scriptの引数・CLI切替・idle pane respawn契約は不変 -->
<!-- 検分: cli_lookup.sh/ninja_monitor.sh 未commit差分(2026-07-10時点ワーキングツリー、要再検証)を確認。(1)cli_lookup.shに`codex_config_apply_agent()`/`codex_config_restore()`を追加。settings.yamlのper-agent`model_name`が`gpt-*`の場合、末尾suffix(low/medium/high/xhigh)を`model_reasoning_effort`、`service_tier`を`~/.codex/config.toml`へ一時適用しrespawn後に復元する。(2)`cli_model_display()`に`gpt-5.6-sol/terra/luna`等の表示ラベルを追加。(3)ninja_monitor.shの`safe_send_clear()`(idle /clear等の自動respawn経路)と`check_ninja_cli_dead()`(死亡pane自動復旧経路)がrespawn-pane直前直後に上記2関数を呼ぶよう変更。`shogun_cli_switch.sh`本体(`switch_cli_mode.sh`のrespawn-pane呼出し=Step2手動切替経路)には未接続で、Options/Step2/Step4記載の呼び出し契約・idle判定・respawn-pane -k実行手順は変更なし。下記「per-agent effort回避策」の揮発性注記のみ影響あり(該当箇所に追記) -->

<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: ninja_monitor.sh edc86c525(reflux promotion候補除外の教訓ID正規表現をLS限定からLS/LK/LG/L全prefix対応へ拡張)+2734ed518(check_karo_completion_notify_gap追加=軍師LGTM後に家老がbulletin/将軍inboxへ通知しない場合を検知する新規チェック)。いずれもreflux/completion通知検知系の内部追加で、idle判定(check_idle)、respawn-pane -k実行手順、cli_launch_cmd()/cli_lookup.sh経由の起動契約、CLI/version切替契約には無関係 -->

<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: ninja_monitor.sh 82291e12a(reflux deploy rollback修正)+ed73c6e60(fix_known reflux insight優先ディスパッチ)+4c07cb037(修行doc参照リンク)。いずれもreflux/修行系の内部変更。idle判定、respawn-pane -k、cli_launch_cmd()/cli_lookup.sh経由の起動契約は不変 -->
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: ninja_monitor.sh 0c73c7d1(cmd_3761) check_and_update_done_task()にtask done_at自動記録(既存なら上書きしない)を追加。throughput計測用の内部フィールド追加のみ。idle判定、respawn-pane -k、cli_launch_cmd()/cli_lookup.sh経由の起動契約は不変 -->
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: ninja_monitor.sh 5b84066d8 lesson backlog warning通知文調整。idle判定、respawn-pane -k、cli_launch_cmd()/cli_lookup.sh経由の起動契約は不変 -->
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_3642 / commit ba8b94d0e. `scripts/lib/cli_lookup.sh` 直近変更は `cli_model_display()` が `sonnet-5-xhigh` / `opus-4-8-xhigh` 等の非 `claude-` 接頭辞モデル名と effort suffix を表示名へ反映する修正。`shogun_cli_switch.sh` / `switch_cli_mode.sh` の呼び出し契約、`cli_launch_cmd()` のper-agent `launch_cmd` override契約、SKILL本文の実行手順に変更なし。切替後確認で表示名に effort が出る場合がある。

Script refs verified: 2026-06-20. `shogun_cli_switch.sh` は `status/pin-2.1.87/unpin-latest/to-claude/to-codex/--agent/--scope/--dry-run/--settings-only` を契約にする。CLI切替は `scripts/switch_cli_mode.sh`、Claude version切替は `config/cli_profiles.yaml` の `profiles.claude.launch_cmd` と個別 `settings.yaml launch_cmd` を正本にする。
Script refs verified: 2026-06-20 L821. `switch_cli_mode.sh` にstale active補正追加(@agent_state=active+task空→idle強制)。I/F変更なし。Codex sandbox環境でStop hookブロック→active残留→respawnスキップのインフラバグ修正。
Script refs verified: 2026-06-21. `switch_cli_mode.sh` relaunch方式をCtrl-C+send-keys→`respawn-pane -k`に変更(殿指摘2026-06-21: CLIごと再起動が基本)。ハングCLIにCtrl-Cが効かず再起動不能だった問題を根治。I/F変更なし。
Script refs verified: 2026-06-21T13:58. CLI種別とモデルの関係セクション追加(殿指摘2026-06-21)。GPT-5.5はCodex CLI必須、Claude CLIで`--model gpt-5.5`は表示のみ変更。TRIGGER拡張(モデル変更系キーワード追加)。DO NOT TRIGGER明確化(同一CLI内の/modelは対象外)。
Script refs verified: 2026-06-21T15:06. switch_cli_mode.sh 4修正(殿指示2026-06-21): (1)CLI種別変更時respawn強制(active判定バイパス) (2)model_nameファミリー不整合リセット (3)respawn前reset追加(Codex exit 2根因修正) (4)cooldown 5秒(高速連続respawn防止)。pre-bash-combined.sh Guard 9b簡素化(respawn-pane通過、model_switchのみBLOCK)。session_start_inject.sh cli_switch_pending待機状態追加。CLAUDE.md Step 0待機判定追加。双方向6連続100%成功+3人同時切替検証済み。
Script refs verified: 2026-06-24T00:35. switch_cli_mode.sh model_name SSOT修正系列(c3d290416→5972c7c34→d796b5a43)確認済み。現行契約は「CLI種別変更時に不整合model_nameを空へリセットし、settings.yaml/tmux変数同期とrespawnを行う」。gpt-5.5-low等のper-agent model_name確定値は必要時にyaml_field_setで明示設定する。I/F変更なし。
Script refs verified: 2026-06-24T08:25. `switch_cli_mode.sh` から `shutsujin_departure.sh` 呼出しを削除。理由: shutsujin_departureはセッション起動時の平時デフォルト復元であり、CLI切替直後に呼ぶとsettings.yamlをデフォルト層へ巻き戻して切替を打ち消す。post-switch verification(settings.type + tmux @agent_cli)を追加し、不一致なら成功表示せずexit 1。
Script refs verified: 2026-06-24T09:12. `switch_cli_mode.sh` 最新commit 78e46781d を確認。08:25追随内容(出陣リセット呼出し削除 + post-switch verification)のI/F変更なし。skill手順変更不要、mtime追随のみ。

# Shogun CLI Switch

Argument hint: `[status|to-claude|to-codex|pin-2.1.87|pin-opus-4.6-1m|unpin-latest|probe-codex] [--agent AGENT] [--scope core|all|csv]`

## ピン留めOpus 4.6 1M（専用action以外を使うな）

「ピン留めOpus 4.6 1M」は次の一コマンドだけで実行する。

```bash
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh \
  pin-opus-4.6-1m --agent <name>
```

このactionは、Claude Code 2.1.87確認、canonical `model_name=claude-opus-4-6`、
固定版Opus high起動、`/model default`、実プロセス確認を順序保証する。
既に正しい場合はrespawnもコマンド送信も行わず即時PASSする。切替が必要な場合は
`@cli_switch_pending=true` を設定して重いRecoveryをスキップする。Recovery完了待ちで
速度を稼ぐ設計は禁止する。
次の二表示が揃わなければ非ゼロ終了し、完了扱いしない。

- `Opus 4.6 (1M context) with high effort`
- `Set model to Opus 4.6 (1M context) (default)`

`pin-2.1.87`単独はCLI版しか固定せず、デフォルトSonnetで起動しうる。
`--model opus`単独も1M確定ではない。独自の`model_name`を作るな。

2026-07-27実測（影丸）: Sonnet 5 low→ピン留めOpus 4.6 1M highは6.18秒、
同一状態への再実行は0.35秒。これを大幅に超える場合は待機せず実装バグとして扱う。

Quality metric: 将軍系CLI/version切替cmdの`cmd_save.sh`チェック通過率（q1-q4 BLOCKなしで保存できた割合）。

## Overview

multi-agent-shogun の指揮官/指定agentを Claude Code と Codex CLI の間で切り替え、必要に応じて Claude Code の pinned/latest version も切り替える。
旧 `/switch-to-codex` と `/switch-to-opus` は本スキルへ統合済み。旧 `/shogun-claude-version-switch` の機能も保持する。

## 殿の指示→実行フロー（誰でも・いつでも・何回でも）

殿の指示を受けたら以下のフローで手順を導出し実行せよ。

### Step 1: モデルファミリー判定

| 殿の指示に含まれるキーワード | モデルファミリー | 必要なCLI |
|---------------------------|----------------|----------|
| GPT-5.5, GPT | GPT系 | **Codex CLI** |
| Opus, Sonnet, Haiku, Claude | Claude系 | **Claude CLI** |

### Step 2: CLI種別切替（必要な場合のみ）

```bash
# 現状確認
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh status

# GPT系に切替（1人）
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --agent <name>

# Claude系に切替（1人）
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-claude --agent <name>

# 複数人同時（CSV指定）
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --scope hayate,kagemaru,saizo
```

### Step 3: effort/fast設定

| 項目 | Claude CLI | Codex CLI |
|------|-----------|-----------|
| **model** | `respawn-pane -k "claude --dangerously-skip-permissions --model sonnet --effort low"` | `~/.codex/config.toml` の `model = "gpt-5.5"` (**全Codex共有**) |
| **effort** | `--effort low\|medium\|high`（起動引数） | `config.toml` の `model_reasoning_effort = "low"` → respawn (**全Codex共有**) |
| **fast** | respawn後に `/fast` → Tab → Enter | `config.toml` の `service_tier = "fast"` → respawn (**全Codex共有**) |

**Codex注意**: config.tomlは全Codex忍者共有。変更は全Codex忍者に影響するが、respawnした忍者のみ反映。

**Claude Opus 5 コンテキスト指定(2026-07-25実験実証)**:
- `--model opus` = `claude-opus-5` (200Kコンテキスト)。1Mにはならない
- `--model 'claude-opus-5[1m]'` = opus 5 1Mコンテキスト。明示指定必須
- バナーで判別: 200K=`Opus 5 with low effort · Claude Max` / 1M=`Opus 5 (1M context) with low effort`
- **Claude Max はサブスクプラン名であり1Mの証拠ではない**
- launch_cmd例: `$HOME/.local/bin/claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort low`
- v2.1.220のlatest CLI必須（pinned 2.1.87はopus 5未対応）

**Codex CLI引数の実証結果(2026-07-20軍師実証)**:
- `--model gpt-5.6-sol`: 有効。config.tomlの`model`値を上書き
- `--effort low/medium/high`: **無効(exit 2)**。Codex CLIに`--effort`引数は存在しない
- `--fast`: **無効(exit 2)**。Codex CLIに`--fast`引数は存在しない
- `-c model_reasoning_effort=medium`: tmux respawn-pane経由だとquotingが崩れ無効化されることがある
- config.toml `model = "gpt-5.6-sol"`: **有効だがexit 2になるモデル名あり**。gpt-5.6-solは`--model`経由でのみ動作する環境がある

**正本(2026-07-27更新)**: per-agentのCLI/model/effortは
`config/settings.yaml` を正本とし、`scripts/agent_respawn.sh` に起動コマンドを生成させる。
共有 `~/.codex/config.toml` のagent別書換えや直接 `tmux respawn-pane` は通常運用に使わない。
`/effort`コマンドは存在しない(実験実証6/6)。`/model`はインタラクティブメニューのみ
(引数不可)であり、作業中は使用しない。

**モデル実験はactive worker paneで行わない（2026-07-21）**: モデル/effortの組合せ検証は `shogun_cli_switch.sh probe-codex --model <model> --effort <level>` を使う。この経路は `codex exec --ephemeral --ignore-user-config` のisolated processで実行し、共有config checksum不変・全pane PID変化0を同時検証する。workerのtask中にself-respawnしてはならない。実運用の切替だけ、idle paneへ既存respawn経路を使う。

### per-agent CLI/model切替の唯一の正規順（2026-07-27実機確認）

`to-codex` はCLI種別を切り替えるが、切替前のClaude系 `model_name`（例: `sonnet-5-low`）が
settings/tmuxへ残る場合がある。`to-codex` の成功表示だけでモデル変更完了と判断するな。

```bash
# 1. 現状確認とdry-run
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh status
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh \
  to-codex --scope hayate,kotaro --dry-run

# 2. CLI種別をCodexへ切替（設定のみ。旧model_nameでの中間respawnを防ぐ）
#    既に対象全員がCodexならこの段階だけ省略可
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh \
  to-codex --scope hayate,kotaro --settings-only

# 3. per-agent正本を更新（settings.yamlへsedを使わない）
for agent in hayate kotaro; do
  bash scripts/lib/yaml_field_set.sh config/settings.yaml \
    "$agent" model_name gpt-5.6-sol-low
done

# 4. 正本値から起動コマンドを再生成してrespawn
for agent in hayate kotaro; do
  bash scripts/agent_respawn.sh "$agent"
done

# 5. settings/tmux → 最新banner → 現在processの順で一次確認
```

`agent_respawn.sh` の出力に
`-c model_reasoning_effort=low -c service_tier=default` が含まれることを確認する。
完了条件は次の3点が全て一致すること:

1. settings/tmux: `cli=codex model=gpt-5.6-sol-low`
2. banner: `model: gpt-5.6-sol low` または最下部 `gpt-5.6-sol low`
3. process: 現在のpane子プロセスがCodexで、起動引数に `model_reasoning_effort=low`

capture-paneの上部に以前の失敗
`error: unexpected argument '--effort' found`
が残っていても、それだけで現在の起動失敗と判定するな。paneの開始コマンド、最新banner、
現在PIDの3点で判定する。今回の実機確認では旧エラー残像がありながら、両paneの現行bannerと
processは `gpt-5.6-sol low` で一致した。

**実行順の不変量**:
- CLI変更と最終モデル変更を同時に行う場合は、`to-codex/to-claude --settings-only`を先に行う。
- 次に `yaml_field_set.sh` でagent別の `model_name`（必要なら`service_tier`）を確定する。
- 最後に `agent_respawn.sh` を実行する。正本更新前のrespawnは禁止。
- `--settings-only`を省くと、旧model_nameで1回、確定model_nameで1回の二重respawnになる。
  2026-07-27の3名一括切替で不要な中間respawnが3回発生したため、モデル併用切替では設定のみを正規経路とする。
- CLI種別だけを変え、モデル名を変更しない依頼では従来どおり`to-codex/to-claude`単独でよい。
- active/in_progress paneは殿の即時切替指示がない限りrespawnせず、設定反映を次の安全な再起動まで保留する。
- 完了判定は settings/tmux・最新banner・現在process の3点一致だけで行う。

### Step 4: 一次確認（必須）

```bash
# 1) settings.yamlは固定行sed禁止。YAMLパースで対象agentだけ確認
python3 - <<'PY'
import yaml
agent = "<agent>"
print(yaml.safe_load(open("config/settings.yaml"))["cli"]["agents"][agent])
PY

# 2) tmux変数確認
tmux display-message -t shogun:2.<pane> -p 'agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name} state=#{@agent_state} task=#{@task_id} current=#{pane_current_command} start=#{pane_start_command}'

# 3) バナーで実モデルを確認（設定変更≠反映。一次確認が必須）
tmux capture-pane -t shogun:2.<pane> -p -S -60 | tail -30

# 4) 実プロセス確認（pane_current_command=bashでも子プロセスにclaude/codexがいる場合がある）
pid=$(tmux display-message -t shogun:2.<pane> -p '#{pane_pid}')
ps -o pid,ppid,stat,comm,args --forest -g "$pid" | sed -n '1,40p'
```

### 実行例

```bash
# 例1: 「hanzoをGPT5.5 low fastonに」
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --agent hanzo --settings-only
bash scripts/lib/yaml_field_set.sh config/settings.yaml hanzo model_name gpt-5.5-low
bash scripts/lib/yaml_field_set.sh config/settings.yaml hanzo service_tier fast
bash scripts/agent_respawn.sh hanzo
tmux capture-pane -t shogun:2.5 -p | tail -2  # → gpt-5.5 low fast 確認

# 例2: 「saizo をSonnet low に」(既にClaude CLIなら)
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-claude --agent saizo --settings-only
bash scripts/lib/yaml_field_set.sh config/settings.yaml saizo model_name sonnet-5-low
bash scripts/agent_respawn.sh saizo
tmux capture-pane -t shogun:2.6 -p | head -3  # → Sonnet 4.6 with low effort 確認

# 例3: 「hayateとkagemaruを同時にCodexに」
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --scope hayate,kagemaru --settings-only
for a in hayate kagemaru; do
  bash scripts/lib/yaml_field_set.sh config/settings.yaml "$a" model_name gpt-5.6-sol-low
  bash scripts/agent_respawn.sh "$a"
done

# 例4: version切替
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh pin-2.1.87      # 全員2.1.87固定
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest     # 全員最新版

# 例5: 「karoをGPT5.5 medium fast onに」
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --agent karo --settings-only
bash scripts/lib/yaml_field_set.sh config/settings.yaml karo model_name gpt-5.5-medium
bash scripts/lib/yaml_field_set.sh config/settings.yaml karo service_tier fast
bash scripts/agent_respawn.sh karo
tmux capture-pane -t shogun:2.1 -p | tail -2  # → gpt-5.5 medium fast 確認
```

# 例6: 「karoをOpus 5 1M lowに」(2026-07-25実証)
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-claude --agent karo --settings-only
bash scripts/lib/yaml_field_set.sh config/settings.yaml karo model_name opus-5-1m-low
bash scripts/lib/yaml_field_set.sh config/settings.yaml karo launch_cmd "$HOME/.local/bin/claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort low"
bash scripts/agent_respawn.sh karo
sleep 8 && tmux capture-pane -t shogun:2.1 -p -S -60 | grep -i "opus\|context"  # → Opus 5 (1M context) 確認

# 例7: 「karoをGPT5.5 medium、忍者6名をGPT5.5 low fastに」(一括切替 2026-06-23実証)
# Step1: CLI種別を先にCodexへ統一
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --scope karo,hayate,kagemaru,hanzo,saizo,kotaro,tobisaru --settings-only
# Step2: settings.yamlのagent別正本を確定
bash scripts/lib/yaml_field_set.sh config/settings.yaml karo model_name gpt-5.5-medium
for a in hayate kagemaru hanzo saizo kotaro tobisaru; do
  bash scripts/lib/yaml_field_set.sh config/settings.yaml "$a" model_name gpt-5.5-low
  bash scripts/lib/yaml_field_set.sh config/settings.yaml "$a" service_tier fast
done
# Step3: 正本値から各paneを再生成
for a in karo hayate kagemaru hanzo saizo kotaro tobisaru; do bash scripts/agent_respawn.sh "$a"; done
# Step4: settings/tmux・banner・processを一次確認
sleep 8 && for p in 1 3 4 5 6 7 8; do echo "pane $p: $(tmux capture-pane -t shogun:2.$p -p | grep -o 'gpt-5.5[^·]*')"; done
```

**実績**: 回1(3分/1名)→回3(2分/7名)。Step1-4を順序実行すれば全員2分で切替可能。

### anti-pattern（殿指摘2026-06-21）

**動いているCLIを弄ろうとするな。paneを殺す→正しいCLI+設定で起動が正道。**

| ❌ 間違い | ✅ 正しい |
|----------|----------|
| `/model gpt-5.5` で Claude→GPT変更 | `to-codex --agent <name>` |
| settings.yaml model_name変更のみ | respawn-pane -k + 起動引数 |
| `--effort low` を Codex CLI に渡す | config.toml の `model_reasoning_effort` |
| Claude CLI で `/fast` → Sonnet fast | `/fast` は Opus 4.6 に強制変更される |
| `codex --full-auto` で起動 | `codex` 単体起動(0.141.0でexit 2) |
| switch_cli_mode.sh後にsettings.yaml未確認 | 切替後に`grep type settings.yaml`で一次確認必須(2026-06-23: tmux変数のみ更新しsettings未反映の事故) |
| `to-codex`成功表示だけでGPTモデル反映済みと判断 | settingsの旧Claude model_name残存を確認し、yaml_field_set→agent_respawn→banner/tmux/process三点確認 |
| capture-pane内の過去`--effort`エラーだけで現行起動失敗と判断 | pane_start_command・最新banner・現在PIDを照合して残像と現行状態を分離 |
| CLI切替後に`shutsujin_departure.sh`実行 | セッション起動時だけ実行。切替中に呼ぶとsettings.yamlを平時デフォルトへ巻き戻す |
| `sed -n '27,33p' config/settings.yaml`など固定行で対象agent確認 | YAMLパースで`cli.agents.<agent>`を直接読む |
| `--model opus` でOpus 5 1Mと判断 | `--model 'claude-opus-5[1m]'` と明示指定。バナーに`(1M context)`表示を確認 |

## Safety

- まず `status` か `--dry-run` を実行せよ
- `active` / `assigned` task中に `pane_dead=1` を検知した場合は、`ninja_monitor.sh` がdeploy/stall graceより先に `respawn_dead_agent.sh` でdead-only自動復旧する。手動respawnを重ねず、`capture-pane -S -30` とtask statusで復旧・再開を確認せよ。live paneとidle taskは自動復旧対象外。
- CLI/version 切替は設定変更だけでは不十分。**idle paneのrespawnが必須**
- `active` / `in_progress` 相当のpaneはスキップし、設定だけを次回起動へ反映する
- `--settings-only` は、CLI+モデルを同時変更して最後に`agent_respawn.sh`を1回だけ行う場合、
  または次回respawnまで反映を保留する場合に使う。`scripts/switch_cli_mode.sh --no-relaunch`に対応する
- **切替後にsettings.yamlのtype/model_nameが正しいか`grep`で一次確認必須**。switch_cli_mode.shがtmux変数のみ更新しsettings未反映の事故あり(2026-06-23 LK007)
- **固定行sedでsettings確認禁止**。行番号は差分で動く。必ずPython/YAMLで `cli.agents.<agent>` を読む
- **切替後に実pane確認必須**。`tmux display-message`、`capture-pane`、必要時は`ps --forest -g #{pane_pid}`で「実CLI/実モデル/実プロセス」を確認する
- **shutsujin_departure.shはruntime CLI switchで実行禁止**。これはセッション起動時のデフォルト復元スクリプトであり、切替状態を巻き戻す
- 正本ランブックを先に読む: `docs/research/claude-code-version-runbook.md`
- Codex切替の前提: `~/.codex/config.toml` に `model_context_window = 1000000`、`model_auto_compact_token_limit = 900000`、hooks有効化があること
- Codexロール指示: `instructions/generated/codex-{role}.md` と AGENTS.md Recovery手順を使う
- 将軍切替時は殿が将軍ペインにいるため、別paneから実行せよ

## Options

```bash
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh <status|pin-2.1.87|unpin-latest|to-claude|to-codex> [--agent <name>] [--scope <core|all|csv>] [--repo <path>] [--dry-run] [--settings-only]
```

## Notes

- `pin-2.1.87` / `unpin-latest` の対象は **Claude 系 pane のみ**
- `to-claude` / `to-codex` は `settings.yaml` の `type` を変更し、tmux `@agent_cli` / `@model_name` を同期する
- 2.1.87 固定資産が欠けている場合は停止して報告する
- `--agent` 指定時: CLI切替では単一agentの `type` を変更、version切替では個別 `launch_cmd` を操作（cli_lookup.sh のオーバーライド機構を利用）
- `--agent` + `pin-2.1.87`: 個別オーバーライドを削除しプロファイルデフォルト(ピン止め)に戻す
- shutsujin再起動時は指揮官(shogun/karo/gunshi)をデフォルトClaude/Opusへ戻す。Codex切替は手動実行時のみの一時状態である

### per-agent launch_cmd によるバージョン個別切替（2026-07-01 実装）

**「いつでも誰でも個別もしくは複数をピン留めや最新版に自由自在に切り替えられる」** 仕組み。

**仕組み**:
- `config/cli_profiles.yaml` の `claude.launch_cmd` = `~/bin/claude` (ピン留め2.1.87) がデフォルト
- `config/settings.yaml` の per-agent 設定に `launch_cmd:` を追加するとその agent だけ上書き
- `scripts/lib/cli_lookup.sh` の `cli_launch_cmd()` がこの値を読んで起動コマンドを決定
- `scripts/ninja_monitor.sh` が respawn 時に `cli_launch_cmd()` を呼ぶため、設定後は次回 /clear 時に自動反映

**個別に最新版へ切替**:
```bash
# tobisaru を最新版(~/.local/bin/claude)に切替
bash scripts/lib/yaml_field_set.sh config/settings.yaml tobisaru launch_cmd "~/.local/bin/claude --dangerously-skip-permissions"

# 確認: cli_lookup で正しく読めるか
source scripts/lib/cli_lookup.sh && cli_lookup tobisaru && echo "launch: $(cli_launch_cmd tobisaru)"
```

**固定版へ戻す**:
```bash
# launch_cmd 行を削除すると cli_profiles.yaml のデフォルト(~/bin/claude)に戻る
python3 -c "
import yaml, re
with open('config/settings.yaml') as f: txt = f.read()
# launch_cmd 行を per-agent ブロックから除去
# ※ yaml_field_set.sh で空文字設定後に手動削除、または下記で直接編集
print('手動でsettings.yaml の tobisaru.launch_cmd 行を削除')
"
```

**ninja_monitor が 2.1.87 に巻き戻す問題の根因と防止**:
- 旧 `cli_lookup.sh` は `settings.yaml` の `launch_cmd` を読まず `cli_profiles.yaml` のみ参照していた
- 修正 (2026-07-01): `_cli_launch_read_settings()` に `launch_cmd:` ブランチと `_CLI_LAUNCH_CMD_OVERRIDE` 変数を追加
- これにより settings.yaml per-agent `launch_cmd` が最優先で適用される
- 検証: `source scripts/lib/cli_lookup.sh && cli_launch_cmd tobisaru` → `~/.local/bin/claude ...` であれば OK

### 最新版とピン留めは版、Opus 4.8 xhigh はmodel/effort（2026-07-01）

- `pin-2.1.87` / `unpin-latest` が切り替えるのは **Claude Code の版** だけ。
- `pin-2.1.87` = `$HOME/bin/claude` = 固定版2.1.87。
- `unpin-latest` = `$HOME/.local/bin/claude` = 最新版追随。
- `Opus 4.8 xhigh` は **起動時の `--model opus --effort xhigh` と `model_name` 表示** で決まる。`unpin-latest` だけでは `Opus 4.8 xhigh` にならない。

**最新版 + Opus 4.8 xhigh を特定agentへ反映する正道**:
```bash
# 1) まず最新版バイナリへ切替
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest --agent <agent>

# 2) model_name と per-agent launch_cmd を明示
bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> model_name opus-4-8-xhigh
bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> launch_cmd "$HOME/.local/bin/claude --dangerously-skip-permissions --model opus --effort xhigh"

# 3) 正本値からidle paneをrespawn
bash scripts/agent_respawn.sh <agent>
```

**確認は3点セット**:
- `settings.yaml` に `model_name=opus-4-8-xhigh`
- `launch_cmd` が `~/.local/bin/claude --model opus --effort xhigh`
- `tmux capture-pane -S -40` のバナーが `Claude Code v2.1.197` かつ `Opus 4.8 with xhigh effort`

**やってはいけないこと**:
- `unpin-latest` だけで「最新版Opus 4.8 xhighになった」と判断する
- staleしうる pane label だけで version/model を確定する

### 最新版 + Opus 5 1M を特定agentへ反映する正道（2026-07-25実証）

**重要**: `--model opus` は `claude-opus-5` (200K) に解決される。1Mには `claude-opus-5[1m]` の明示指定が必須。

```bash
# 1) settings.yaml更新
bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> type claude
bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> model_name opus-5-1m-low
bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> launch_cmd "$HOME/.local/bin/claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort low"

# 2) respawn (agent_respawn.sh経由必須)
bash scripts/agent_respawn.sh <agent>

# 3) バナー確認 — 「(1M context)」表示が必須
sleep 8 && tmux capture-pane -t shogun:2.<pane> -p -S -60 | grep -i "opus\|context"
# 正: Opus 5 (1M context) with low effort
# 誤: Opus 5 with low effort · Claude Max  ← これは200K
```

**確認は3点セット**:
- `settings.yaml` に `model_name=opus-5-1m-low`
- `launch_cmd` に `--model 'claude-opus-5[1m]'`
- バナーに `Opus 5 (1M context)` 表示（`Claude Max`だけではサブスクプラン名で1Mの証拠にならない）

## 実践検証結果（2026-06-21 殿指示で検証）

| # | 操作 | 方法 | 結果 | 知見 |
|---|------|------|------|------|
| P1 | Codex→Claude | `to-claude --agent` | ✅ | スキルが設定+respawn一括実行 |
| P2 | Opus→Sonnet(同一CLI) | `/model sonnet` | ✅ | 同一CLI内は`/model`でOK |
| P3 | Claude→Codex | `to-codex --agent` | ✅ | 根因修正済み(reset+cooldown)。双方向6連続成功 |
| P4 | effort変更(Claude) | `respawn-pane -k --model --effort` | ✅ | pane殺す→起動引数指定が正道 |
| P5 | effort変更(Codex) | config.toml→respawn | ✅ | config.toml変更は即時反映されない。respawn必須 |
| P6 | fast off(Codex) | config.toml service_tier→respawn | ✅ | service_tier=default/fast。respawnで反映 |
| P7 | fast toggle(Claude) | `/fast` Tab Enter | ✅ | fast ONはOpus 4.6に強制変更。Sonnet fastは不可 |
| C1 | 2人同時切替 | `--scope hayate,kagemaru` | ✅ | CSV指定で一括切替 |
| C2 | 3人同時切替 | `--scope hayate,kagemaru,saizo` | ✅ | CLI種別変更はrespawn強制(active判定バイパス) |

**修正済みの問題と対策**:
- **Codex exit 2 (pane dead)**: 根因=Claude CLIのターミナル設定残留。対策=respawn前にreset実行+5秒cooldown。双方向6回連続100%成功で検証済み
- **CLI種別変更時のrespawnスキップ**: 根因=@agent_state=active残留。対策=current_cli≠TARGET_CLIならstale/busy判定スキップ
- **model_nameファミリー不整合**: 根因=to-claude時にGPT model_nameが残留。対策=CLI種別変更時に不整合model_nameを自動リセット
- **CLI switch後の自動recovery**: 対策=@cli_switch_pending→CLAUDE.md Step 0でrecovery全スキップ→CTX:0%待機

**運用注意**:
- config.toml(effort/service_tier)は全Codex忍者共有。変更は全員に影響するがrespawnした忍者のみ反映
- Claude `/fast` ONはモデルをOpus 4.6に強制変更する。Sonnet fastは存在しない

## 関連スキル

- [[shogun-all-codex-switch]] — 全忍者をCodex CLIに一括切替（モデル系ではなくCLI種別の切替）
- [[shogun-peacetime-rollback]] — CodexからClaude（平時編成）への一括ロールバック
- [[hensei]] — 忍者モデル編成切替
Script refs verified: 2026-06-28 75aac6a10. `yaml_field_set.sh` 直近変更は既存ブロックへ新規fieldを追加する際の挿入位置修正。settings.yaml更新・tmux変数同期・respawn手順の契約は変更なし。

Script refs verified: 2026-07-01T04:10:00+09:00. `cli_lookup.sh` に `_CLI_LAUNCH_CMD_OVERRIDE` 追加(per-agent launch_cmd対応)。`settings.yaml` per-agent `launch_cmd:` フィールドが `cli_profiles.yaml` デフォルトより優先される。ninja_monitor respawn時に自動反映。検証: `source scripts/lib/cli_lookup.sh && cli_launch_cmd <agent>` で確認。
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `cli_lookup.sh`/`switch_cli_mode.sh`/`ninja_monitor.sh` 直近変更(58c729dc/23b16810/c9ba1ff9/befd7ca4/9fa6e089/8e26308/7f3b9ca/897470d/6c6bd607)はsettings-only許可、launch_cmd overrideの追加/解除、runtime model検出、monitor hot-reloadとclear loop抑制の内部制御で、`shogun_cli_switch.sh status|pin-2.1.87|unpin-latest|to-claude|to-codex`、`--agent`、`--scope`、`--dry-run`、`--settings-only` の契約は変更なし。

Script refs verified: 2026-07-02 cmd_3642 / commit ba8b94d0e. `cli_lookup.sh` の `cli_model_display()` は `sonnet-5-xhigh` / `opus-4-8-xhigh` 等のsettings由来model_nameを表示名+effortへ正規化するようになった。`cli_launch_cmd()`、per-agent `launch_cmd` override、`shogun_cli_switch.sh` のI/Fは変更なし。

Script refs verified: 2026-07-04T20:11:54+09:00 cmd_training_skill_refs_shogun_cli_switch_202607042005。`ninja_monitor.sh` の2026-07-02T13:21:30以降の差分(a85cbf481/bb140170d/842dd276c/d3f1938e5/33d39ffce)をgit showで確認: (1)未使用`count_unread_messages()`削除(死コード、呼び出し元ゼロ) (2)`write_karo_snapshot()`/`refresh_karo_snapshot_fast_path()`にNINJA_NAMES/PREV_STATE/REDISCOVER_EVERYの未設定フォールバックガード追加(karo_snapshot生成のlib-only呼び出し耐性強化) (3)`write_state_file()`/`check_model_names()`にKARO_PANE/PANE_TARGETSの未設定フォールバックガード追加(pane_lookup経由でkaroペイン解決) (4)(5)将軍`idle_analysis_trigger`クールダウンを`/tmp/.shogun_idle_trigger_last`へ永続化し、ninja_monitor再起動(respawn)を跨いでcooldownを維持。いずれも`check_idle()`のidle判定ロジック、`respawn-pane -k`実行手順、`cli_launch_cmd()`/`cli_lookup.sh`経由の起動コマンド解決には変更なし。shogun-cli-switchのidle pane判定・respawn契約・monitor連携は現行記載のまま有効。

Script refs verified: 2026-07-07T18:19:00+09:00 (shogun復帰時WARN解消). `ninja_monitor.sh` 直近変更(1d800fd96)をgit showで確認。還流insight自動配備(`_handle_reflux_auto_deploy`)にtarget_path active衝突スキップを追加する内部制御のみで、`check_idle()`のidle判定、`respawn-pane -k`実行手順、`cli_launch_cmd()`/`cli_lookup.sh`経由の起動コマンド解決、CLI切替契約には変更なし。
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-16T07:35:59+09:00 -->
