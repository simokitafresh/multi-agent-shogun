<!-- semantic-links: [[Hook自動化フレームワーク]], [[編成管理]], [[デーモン監視と復旧]], [[ローカル記憶DB]], [[三層記憶アーキテクチャ]], [[因果確認L0-L7]] -->

# Multi-CLI Hook/Event Commonization Design — 2026-06-02

## 0. Summary

Claude Code CLIとCodex CLIを同一軍規で運用するには、CLI固有hook設定を直接正本にしてはならない。

現状はClaude Codeの`.claude/settings.json`が実質的な安全網の正本で、Codexの`.codex/hooks.json`は一部移植に留まる。これにより、CLI切替時に「paneはCodexだが安全網はClaude前提」「Claudeでは止まる操作がCodexでは通る」「Codex Stop hookを戻すと無限ループする」という構造穴が残る。

解決策は、hookをCLI別設定ファイルで管理するのではなく、共通イベント層を正本化し、各CLIで使えるイベントはhookとして生成し、使えないイベントはdaemon/gate/scriptで補完すること。

2026-06-02追加原則: multi-CLI徹底とは「Claude hookをCodexへ移植する」ことではない。CLIが違っても同じ規律が成立するよう、正本をCLI外の共通script/gate/template/DBへ置き、hookは使えるCLIでの早期検出に留める。因果確認L0-L7も同じ原則に従い、設計意図確認をhook専用にしてはならない。

2026-06-24追加裁定: Codex最新版の公式manualで `SessionStart` / `UserPromptSubmit` / `Stop` supportを確認済み。旧記述「CodexにUserPromptSubmit相当なし」は破棄する。ただし、Codexは同一eventに複数matching hookがあると並行実行するため、Claude型のhook列をそのまま移植してはならない。共通化対象はhook実装ではなく軍規イベントであり、CLIごとの実行モデルへadapterする。実装正本は `config/cli_events.yaml`、Codex prompt/session adapterは `scripts/hooks/codex_user_prompt_submit.sh` / `scripts/hooks/codex_session_start.sh`。Codex Stopはevent自体の存在とblock/re-prompt安全性を分け、block系Stop hookは未検証のためdaemon等価保証のまま維持する。因果: [[codex_manual_update]] -> [[old_hook_assumption_invalidated]] -> [[cli_capability_adapter_required]]。

三層記憶への貫通:

- 全文/DB層: 本設計書とlive memory eventに保存する。
- Obsidian層: 本ファイル冒頭の `semantic-links` で [[Hook自動化フレームワーク]] / [[編成管理]] / [[デーモン監視と復旧]] / [[ローカル記憶DB]] へ接続する。
- セマンティック層: `docs/semantic-index/index.md` の `multi_cli_event_commonization` から本設計書へ到達できるようにする。
- 因果確認層: `docs/research/causal-verification-l0-l7-design_20260602.md` と相互参照し、CLI差分対策の前に「なぜ現在の実装がそうなっているか」を確認する。

## 1. Trigger

才蔵の中枢Codex切替調査で、`switch_cli_mode.sh` / `shutsujin_departure.sh` / `switch_all_codex.sh` / `restart_watchers.sh` に切替上の穴が見つかった。

家老検分で追加判明した上位穴:

- `.claude/settings.json` と `.codex/hooks.json` のイベント覆盖範囲が大きく違う。
- CodexにClaude Stop hookを単純移植すると、既存分析どおり無限ループ/CLI死亡リスクがある。
- `restart_watchers.sh` はwatcher再起動gateとして重要だが、`--help`非対応で実行され、flock fd継承により一時的に再起動不能に見える挙動がある。
- CLI切替後の検証はpane metadataだけでは足りず、settings / pane process / watcher / hook coverage / reset semanticsの5点を同時に見る必要がある。

## 2. Primary Evidence

### 2.1 ClaudeとCodexのhook差分

Claude Code側 `.claude/settings.json`:

| Event | Representative behavior |
|---|---|
| `SessionStart` | `session_start_inject.sh` |
| `PreToolUse` | state active, pre-bash, read tracker, write/edit guards, PI inject, skill guard |
| `PostToolUse` | inbox check, post-bash, bulletin read check, search completeness, post write/edit |
| `Stop` | state idle, terminal response log, lint gate, inbox check |
| `SessionEnd` | clear/session end check |
| `UserPromptSubmit` | state active, terminal input log, prompt state inject |

Codex側 `.codex/hooks.json`:

| Event | Current behavior |
|---|---|
| `PreToolUse` | Bash guard, Write/Edit guard |
| `PostToolUse` | Bash guard |

Codex側にない、または現状未移植の重要安全網:

- SessionStart recovery injection
- Stop時のidle化
- Stop時のterminal response保存
- Stop lint gate
- Stop inbox check
- UserPromptSubmit state active
- prompt_state_inject
- Read-before-Write tracker
- Search completeness guard
- Post Write/Edit guard
- Skill project guard

### 2.2 Codex Stop hookの既知制約

`docs/research/gunshi_idle_codex_hook_analysis_20260511.md` の結論:

- Codex CLIのStop hookで `{"decision":"block"}` 相当を返すと、reason文がプロンプトとして再実行され無限ループする。
- よって `.codex/hooks.json` にClaude型Stop block hookを戻してはならない。
- CodexではStop相当の強制を、block hookではなくdaemon/gate/pane state補正へ逃がす必要がある。

### 2.3 中枢切替スクリプトの穴

才蔵指摘は採用する。

| Finding | Status |
|---|---|
| `shutsujin_departure.sh` L46-L58がshogun/karo/gunshiの`type: codex`を`claude`へ戻す | valid |
| `switch_all_codex.sh` が `switch_cli_mode.sh` 実行後に `cli.default=codex` を `yaml.safe_dump` で書く | valid and unsafe |
| `switch_cli_mode.sh` default scope `core=shogun,karo` にgunshiが含まれない | valid |
| `restart_watchers.sh` はpane `@agent_cli` を読むためmetadata不一致に弱い | partially mitigated by `inbox_watcher.sh` runtime lookup, but verification still needed |
| watcher count/gateが必要 | valid |

追加所見:

- `inbox_watcher.sh` は第3引数を無視し、実送信時はpane `@agent_cli` 優先、settings fallbackで解決する。したがって「watcher argvの第3引数が古い」だけなら致命傷ではない。
- ただし watcher 起動ログ、pane metadata、settings、実プロセスが不一致になると運用判断が混乱するため、切替gateでは全て照合する。

## 3. Design Goal

同じ役割のagentは、Claude Code / Codex / Copilot / Kimi のどのCLIで起動しても、以下の軍規が同じ意味で保証されること。

この要件は忍者だけでなく、将軍・家老・軍師にも適用する。現状は将軍/家老/軍師がClaude中心でも、Claude API障害や編成変更でCodexへ切り替わるため、roleを限定した設計は禁止。

1. 作業開始時に正しい復帰手順へ入る。
2. tool実行前後の禁止操作が同じ粒度で検査される。
3. Read-before-Writeなどの状態依存ガードがCLI差異で抜けない。
4. ターン終了時またはそれに相当する時点で、idle化・inbox確認・lint/report検査が行われる。
5. CLI resetは各CLIの安全な手段へ変換される。
6. 切替後にsettings / pane / process / watcher / event coverageが一致していると機械的に確認できる。

Non-goal:

- CodexへClaude Stop block hookをそのまま戻すこと。
- 全CLIに同じhookイベント名を要求すること。
- hookだけで全安全網を実現すること。
- 因果確認や安全網をClaude専用hook/Codex専用hookのどちらか片方に閉じ込めること。

## 3.1 Cross-CLI Enforcement Principle

multi-CLIの徹底では、各安全網に必ずCLI非依存の成立点を置く。

| Safety rule | CLI-independent source of truth | CLI-specific layer |
|---|---|---|
| Bash/YAML破壊防止 | common scripts + `cmd_save.sh` / report gate | PreToolUse hookは早期検出 |
| Read-before-Write | common read tracker policy + report/task gate | Claude/Codex hookは補助 |
| Stop/idle/inbox確認 | `ninja_monitor.sh`, `inbox_watcher.sh`, startup/complete gates | Claude Stop hookは補助。Codex Stop blockは禁止 |
| 因果確認L0-L7 | `deploy_task.sh`, `cmd_save.sh`, `gate_report_format.sh`, task/report YAML, semantic index, memory DB | hookは事前表示/早期WARNのみ |
| CLI切替検証 | `gate_multi_cli_switch.sh` | generated hook config check |

判定基準:

- PASS: hookが無効/未対応のCLIでも、同じ禁止・確認・記録が共通gate/template/daemonで成立する。
- FAIL: `.claude/settings.json` または `.codex/hooks.json` のどちらかにしか存在せず、共通script/gateで検出できない。

## 3.2 Causal Verification Integration

CLI共通化そのものも過去の経緯を壊しやすい領域である。`respawn-pane -k`、Codex Stop hook禁止、watcher metadata、`yaml.safe_dump`禁止などは、一見不合理でも過去事故から生まれた設計意図を持つ。

変更前の必須確認:

1. 対象scriptの `git log --oneline -- <file>` と必要行の `git blame` を見る。
2. `projects/infra/lessons_*.yaml` と `docs/research/*design*` / `*analysis*` を検索する。
3. `semantic_search.sh` と `causal_backlinks.sh` で関連概念・因果辺を確認する。
4. 「導入理由」「守るべき設計意図」「今回壊れている因果」をcmd/reportへ残す。

この確認もmulti-CLI非依存で強制する。実装先は `docs/research/causal-verification-l0-l7-design_20260602.md` のL0-L7表に従う。

## 4. Proposed Architecture

### 4.1 Common Event Spec

正本ファイルを新設する。

Proposed path:

- `config/cli_events.yaml`

Confirmed schema (2026-06-02 将軍裁定):

```yaml
# config/cli_events.yaml — confirmed schema v3
# This is the authoritative event spec. CLI-specific hook configs are generated from this.
events:
  session_start:
    required: true
    claude:
      hook_event: SessionStart
      mode: hook
    codex:
      mode: daemon_or_startup_prompt
    actions:
      - id: startup_inject
        command: bash scripts/hooks/session_start_inject.sh
        blocking: warn

  pre_bash:
    required: true
    claude:
      hook_event: PreToolUse
      matcher: Bash
      mode: hook
    codex:
      hook_event: PreToolUse
      matcher: Bash
      mode: hook
    actions:
      - id: pre_bash_combined
        command: bash .claude/hooks/pre-bash-combined.sh
        blocking: deny

  post_bash:
    required: true
    claude:
      hook_event: PostToolUse
      matcher: Bash
      mode: hook
    codex:
      hook_event: PostToolUse
      matcher: Bash
      mode: hook
    actions:
      - id: post_bash_combined
        command: bash .claude/hooks/post-bash-combined.sh
        blocking: warn

  pre_write_edit:
    required: true
    claude:
      hook_event: PreToolUse
      matcher: Write|Edit
      mode: hook
    codex:
      hook_event: PreToolUse
      matcher: Write|Edit
      mode: hook
    actions:
      - id: pre_write_edit_combined
        command: bash .claude/hooks/pre-write-edit-combined.sh
        blocking: deny

  post_write_edit:
    required: true
    claude:
      hook_event: PostToolUse
      matcher: Write|Edit
      mode: hook
    codex:
      hook_event: PostToolUse
      matcher: Write|Edit
      mode: hook
    actions:
      - id: post_write_edit_combined
        command: bash .claude/hooks/post-write-edit-combined.sh
        blocking: warn

  stop_equivalent:
    required: true
    claude:
      hook_event: Stop
      mode: hook
    codex:
      mode: daemon
      daemon_host: ninja_monitor.sh
      reason: "Codex Stop block semantics can re-prompt and loop (殿裁定2026-05-20). ninja_monitor.sh handles idle detection, inbox check, and auto-clear for Codex."
    actions:
      - id: mark_idle
        command: scripts/hooks/common/mark_agent_idle.sh
      - id: stop_check_inbox
        command: bash scripts/hooks/stop_check_inbox.sh
        blocking: claude_only
```

  # === 軍師覚醒レビュー指摘で追加 (2026-06-02 19:58) ===

  session_end:
    required: true
    claude:
      hook_event: SessionEnd
      mode: hook
    codex:
      mode: daemon
      daemon_host: ninja_monitor.sh
      reason: "Codex SessionEnd不在。ninja_monitorのauto-clear/auto-commitが等価処理"
    actions:
      - id: session_end_clear_check
        command: bash scripts/hooks/session_end_clear_check.sh
        blocking: warn

  user_prompt_submit:
    required: true
    claude:
      hook_event: UserPromptSubmit
      mode: hook
    codex:
      mode: unsupported
      reason: "Codex CLIにUserPromptSubmit相当なし。prompt_state_inject+log_terminal_inputはClaude専用。Codexではstartup prompt内で代替"
    actions:
      - id: prompt_state_inject
        command: bash scripts/hooks/prompt_state_inject.sh
        blocking: warn
      - id: log_terminal_input
        command: bash scripts/hooks/log_terminal_input.sh
        blocking: info

  post_search:
    required: false
    claude:
      hook_event: PostToolUse
      matcher: Grep|Glob
      mode: hook
    codex:
      hook_event: PostToolUse
      matcher: Grep|Glob
      mode: hook
    actions:
      - id: post_search_completeness_guard
        command: bash .claude/hooks/post-search-completeness-guard.sh
        blocking: warn

  post_all:
    required: false
    claude:
      hook_event: PostToolUse
      matcher: ALL
      mode: hook
    codex:
      hook_event: PostToolUse
      matcher: ALL
      mode: hook
    actions:
      - id: post_shogun_inbox_check
        command: bash .claude/hooks/post-shogun-inbox-check.sh
        blocking: info

  pre_read_tracker:
    required: true
    claude:
      hook_event: PreToolUse
      matcher: Read
      mode: hook
    codex:
      hook_event: PreToolUse
      matcher: Read
      mode: hook
    actions:
      - id: pre_write_read_tracker
        command: bash .claude/hooks/pre-write-read-tracker.sh
        blocking: info

  pre_edit_pi_inject:
    required: true
    claude:
      hook_event: PreToolUse
      matcher: Edit
      mode: hook
    codex:
      hook_event: PreToolUse
      matcher: Edit
      mode: hook
    actions:
      - id: pre_edit_pi_inject
        command: bash .claude/hooks/pre-edit-pi-inject.sh
        blocking: warn

  pre_skill_project_guard:
    required: true
    claude:
      hook_event: PreToolUse
      matcher: Skill
      mode: hook
    codex:
      mode: gate_or_skill_registry
      reason: "Codex skill invocation does not share Claude Skill hook coverage. Skill role/project guards must be enforced by common skill metadata/gate, not Claude-only hook."
    actions:
      - id: pre_skill_project_guard
        command: bash .claude/hooks/pre-skill-project-guard.sh
        blocking: warn
```

Schema status: **confirmed v3** (v2→v3, 家老現物突合レビュー反映 2026-06-02). 6→12→13 event定義。Claude全hook event/actionカバー。v2の穴: `.claude/settings.json` の `PreToolUse matcher: Skill` / `pre-skill-project-guard.sh` がschema外だった。

### 4.1.1 Codex Stop warn実験 (Open Investigation)

軍師発見: Codex 0.136.0のconfig.tomlにstop:0:0のtrusted_hash痕跡 → StopイベントがCodexでサポートされている可能性。

§2.2のblock→無限ループリスクは**blockレスポンス**の問題であり、Stop event自体の不在ではない。**warnレスポンス**なら安全かもしれない。

実験計画:
1. idle状態のCodex忍者pane(kotaro等)で `.codex/hooks.json` にStop eventをwarnレスポンスで追加
2. 忍者にダミータスク配備→完了→Stop発火確認
3. warn時の挙動確認: (a)正常停止 (b)re-prompt (c)無限ループ (d)CLIクラッシュ
4. 結果によりstop_equivalent定義を更新: warnでOK→`mode: hook`に昇格。NG→`mode: daemon`維持

**重要**: この実験は殿承認後に実施。Codex CLIの挙動変更は全忍者に影響するためTier 2(STOP-AND-REPORT)相当。

### 4.1.2 UserPromptSubmit Codex代替設計 (軍師覚醒レビュー3往復目+将軍拡張)

UserPromptSubmitはClaude専用で3機能を担う:
1. **state active設定**(tmux metadata) → ninja_monitor pane検知で代替済み(既存)
2. **log_terminal_input**(殿入力ログ) → Codex代替なし。殿の入力が記録されない
3. **prompt_state_inject**(semantic検索→スキル推薦+inbox nudge検出) → Codex代替なし。入力ごとの動的推薦が完全欠落

project_docは静的(起動時1回)。殿入力テキストに応じた動的検索は入力ごとに異なる結果を返す。project_docでは不可。

代替案評価:

| 案 | 方式 | 実現性 | 品質 | 100億年テスト |
|----|------|--------|------|---------------|
| A | ninja_monitor pane content diff | 高(既存インフラ) | 中(タイミング問題: 入力後 vs CLI処理後) | 条件付きPASS |
| B | Codex plugin/MCP API | 低(API仕様未確認) | 高(CLIネイティブ) | PASS(存在すれば) |
| C | Codex UserPromptSubmit追加待ち | 低(ロードマップ不明) | 高 | PASS(実装されれば) |
| **D'** | **tmux send-keys入力検知+非同期enqueue処理** | **高** | **中〜高** | **条件付きPASS** |

**将軍追加案D'（家老レビュー修正）**: ninja_monitorが既にpane監視をしている。Codex忍者への殿/家老入力はtmux send-keysで行われる。send-keys実行直後にinbox_watcher等がpane変化を検知→その時点でpane contentを取得→最新入力行を抽出→prompt_state_inject同等処理を**同期実行せず、軽量queueへenqueue**する。pane content diffではなく**inbox_watcher/ninja_monitorのsend-keys検知タイミングに相乗り**する。タイミング問題を構造的に回避するが、nudge経路を重くしてはならない。

実装先: inbox_watcher.sh内のsend-keys後処理（既にnudge送信で入力検知している箇所）に「prompt_state_inject相当queue enqueue」を追加。実処理は別workerまたはninja_monitor低頻度drain。同期semantic_search禁止、timeout必須、dedup必須、失敗時はnudge配送を絶対に止めない。

Queue正本:
- PASS: queueはrepo/state配下など再起動後も残るファイルベースに置く（例: `queue/prompt_state_inject_queue/`）。`/tmp`のみは禁止。
- PASS: enqueueはatomic write (`*.tmp`→rename) + fingerprint dedup。
- PASS: ninja_monitor/worker再起動後に未処理queueを再drainできる。
- FAIL: tmux/inbox watcherプロセスのメモリ、またはtmpfsのみへ保存する。

案D'の二値条件:
- PASS: send-keys/nudge処理の追加遅延p95が100ms未満。
- PASS: semantic_search/DB/cacheがtimeoutしてもinbox nudgeは送達される。
- PASS: 同一pane同一入力fingerprintはdedupされる。
- PASS: queue backlogが閾値超過時はdropまたはWARNし、watcherを詰まらせない。
- FAIL: prompt_state_inject/semantic_searchをinbox_watcher内で同期実行する。

**Open**: この案DのPoC検証は§10 impl前に1忍者で実験すべき。

Key rule:

- `actions` が正本。
- CLI別設定ファイルは生成物。
- CLIでhook化できないeventは `mode: daemon` として補完対象にする。

### 4.2 Generated Hook Configs

新設:

- `scripts/generate_cli_hooks.sh`

Responsibilities:

1. `config/cli_events.yaml` を読む。
2. Claude用 `.claude/settings.json` のhooks部分を生成または検証する。
3. Codex用 `.codex/hooks.json` を生成または検証する。
4. `unsupported but required` のeventを `daemon_requirements` として出力する。
5. `yaml.safe_dump` / JSON round-tripで既存設定を壊さないよう、生成対象を限定する。

Implementation constraint:

- 運用YAMLは `yaml.safe_dump` で丸ごと上書きしない。代替手段:
  - **フィールド単位更新**: `bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>` (flock付き、既存hookでBLOCK強制済み)
  - **セクション追記**: `cat >>` or Edit tool (Read before Write必須)
  - **config/cli_events.yaml**: 読み取り専用正本のため書込み不要。生成スクリプトが読むだけ
- JSONは生成対象ファイルがJSON正本ならPython `json.dump` 可。ただし `.claude/settings.json` のpermissions/spinner等を巻き込む全書き換えは禁止。代替手段:
  - **部分更新**: `python3 -c "import json; d=json.load(...); d['hooks']['...'] = ...; json.dump(d, ...)"` でhooksブロックのみ更新
  - **検証のみ(Phase 1)**: `--check` で差分検出。書込みなし
- `switch_all_codex.sh` のYAML更新(§2.3): `yaml_field_set.sh` でsettings.yamlのCLI種別フィールドのみ更新。yaml.safe_dumpによる全書き換え禁止

Drift guard:
- `scripts/hooks/post_cli_hook_drift_guard.sh` を新設し、`.claude/settings.json` / `.codex/hooks.json` / `config/cli_events.yaml` の変更後に `scripts/generate_cli_hooks.sh --check` を自動実行する。
- `scripts/gates/gate_multi_cli_event_coverage.sh --check` は「settings/hooksに存在するがcli_events.yamlにないhook」をBLOCKする。
- 理由: 実運用ではhook追加cmdが`.claude/settings.json`を直接編集しがちで、正本→生成物の因果が逆転する。PostToolUse guardでドリフトを即検出し、正本追従漏れを残さない。
- 初期実装は `--check` only で差分検出から始める。

### 4.3 Common Hook Wrappers

CLI差異をhook本体に散らさない。

Proposed paths:

- `scripts/hooks/common/pre_bash.sh`
- `scripts/hooks/common/post_bash.sh`
- `scripts/hooks/common/pre_write_edit.sh`
- `scripts/hooks/common/mark_agent_active.sh`
- `scripts/hooks/common/mark_agent_idle.sh`
- `scripts/hooks/common/stop_equivalent.sh`

Existing `.claude/hooks/*.sh` は当面 wrapper として残し、内部で common script を呼ぶ。

Example:

```bash
#!/usr/bin/env bash
exec bash /mnt/c/tools/multi-agent-shogun/scripts/hooks/common/pre_bash.sh "$@"
```

Return semantics adapter:

| CLI | deny/block behavior |
|---|---|
| Claude Code | existing Claude hook JSON / exit behavior |
| Codex | exit 2 for intentional block, never Codex Stop block loop |

The common layer returns normalized result:

```text
RESULT=allow|deny|warn
REASON=...
```

The CLI adapter converts that result into Claude/Codex-safe output.

### 4.4 Daemon Compensation Layer

Codexでhook eventがない/危険な場合、daemonがevent相当を保証する。

Compensation targets:

| Missing/unsafe event | Compensation |
|---|---|
| Codex `SessionStart` | launch prompt + startup gate check + pane boot verifier |
| Codex `Stop` idle marking | `ninja_monitor.sh` / `inbox_watcher.sh` pane state reconciliation |
| Codex Stop inbox check | `inbox_watcher` unread fingerprint + stop-equivalent scan on idle prompt detection |
| Codex Stop lint gate | `cmd_complete_gate.sh` / report gate / pre-commit gateに寄せる |
| UserPromptSubmit state active | `inbox_watcher` nudge send時 + pane prompt injection時にactive化 |
| Read tracking absence | Pre Write/Edit hookでread logがない場合のWARN/BLOCK policyをCLI別に定義 |

Important:

- Codex Stop hook blockは禁止。
- Codexで「turn終了を検知したい」場合は、hookで止めるのではなく、pane状態観察と次回行動前gateで捕捉する。

### 4.5 Switch Verification Gate

新設:

- `scripts/gates/gate_multi_cli_switch.sh`

Checks:

1. `config/settings.yaml` target agents type matches expected CLI.
2. pane `@agent_cli` matches settings.
3. pane current command matches CLI class.
   - Claude: `claude`
   - Codex: `node` or codex binary process under pane
4. `@model_name` matches resolved display for settings.
5. watcher count equals expected agent count.
6. watcher effective CLI matches pane metadata at runtime.
7. `.claude/settings.json` and `.codex/hooks.json` coverage matches `config/cli_events.yaml`; config外のClaude-only hook（例: Skill guard）があればBLOCK。
8. reset command mapping is correct.
   - Claude: `/clear`
   - Codex: `/new` only when command reset is intended; `respawn-pane -k` remains required for idle Codex hard reset.
9. forbidden operation smoke tests pass:
   - report YAML direct Write/Edit blocked or warned as intended.
   - destructive bash dry sample blocked.
   - YAML dump pattern blocked.
10. Codex Stop hook is absent or non-blocking.

Gate output:

```text
PASS: all target agents are CLI-consistent and event coverage is complete
WARN: non-critical mismatch
BLOCK: settings/pane/process/watcher/event coverage mismatch
```

### 4.6 Switch Script Changes

Modify `scripts/switch_cli_mode.sh`:

- Add `--scope central` = `shogun,karo,gunshi`.
- Keep `core` for backward compatibility but stop using it in all-codex skill.
- Add `SHOGUN_ALLOW_COMMANDER_CODEX=1` when calling `shutsujin_departure.sh`, or skip `shutsujin_departure.sh` and call only safe layout/sync routines.
- Run `gate_multi_cli_switch.sh --target <cli> --scope <scope>` after relaunch.

Modify `scripts/shutsujin_departure.sh`:

- Commander Opus restore must be conditional.
- Proposed guard:

```bash
if [[ "${SHOGUN_ALLOW_COMMANDER_CODEX:-0}" != "1" ]] && settings default is not codex; then
  restore shogun/karo/gunshi to claude
fi
```

Modify all-codex skill script:

- Never use `yaml.safe_dump` to rewrite `config/settings.yaml`.
- Set `cli.default` and explicit agent `type` via field setters or a purpose-built settings updater.
- Run order:
  1. normalize settings to all codex
  2. switch/relaunch with commander restore disabled
  3. restart watchers
  4. run switch verification gate
  5. post bulletin result

Modify `scripts/restart_watchers.sh`:

- Add `--help`.
- Prevent flock fd inheritance into child watcher processes.
- Verify parent watcher process and child inotify process separately.
- Make `EXPECTED_WATCHER_COUNT` derive from `get_all_agents + shogun`, not hardcoded `9`.

## 5. Risk Analysis

### Risk A: Codex Stop hook loop returns

Cause:

- Someone sees missing Stop hook and re-adds Claude Stop block semantics to `.codex/hooks.json`.

Mitigation:

- `gate_multi_cli_switch.sh` blocks Codex Stop hook with blocking behavior.
- `config/cli_events.yaml` marks Codex stop as `mode: daemon`.
- Keep `docs/research/gunshi_idle_codex_hook_analysis_20260511.md` linked in the spec.

### Risk B: Hook coverage looks complete but daemon compensation absent

Cause:

- Spec says Codex event is daemon-compensated but no daemon check exists.

Mitigation:

- Every `mode: daemon` event must include `daemon_check`.
- `gate_multi_cli_switch.sh` verifies the script/function exists and has a smoke test.

### Risk C: Settings and runtime diverge

Cause:

- settings updated without respawn; pane metadata stale; watcher restarted from stale pane metadata.

Mitigation:

- Runtime switch requires pane respawn/relaunch.
- `--settings-only` must print `INCOMPLETE_RUNTIME_SWITCH`.
- Gate checks settings/pane/process/watcher together.

### Risk D: Safe-dump destroys settings comments or unsupported structure

Cause:

- Python YAML round-trip rewrites `config/settings.yaml`.

Mitigation:

- Use existing field setter or build a scoped updater.
- Test preserves comments and key order where operationally relevant.

### Risk E: Common layer adds latency to hot hooks

Cause:

- Every tool call invokes wrappers.

Mitigation:

- Keep common wrappers shell-light.
- Avoid `jq`/Python in hot path unless necessary.
- Reuse `docs/research/codd_spec_bash_state_hook_20260418.md` optimization pattern.

### Risk F: Hot pathに重い同期I/Oが戻る

Cause:

- inbox/report/gate/deployの経路にmemory DB live insert、semantic_search、causal_backlinks、広域git走査を同期で戻す。
- `deploy_task.sh` は1配備あたり多数の記憶・概念処理を呼び得るため、watcher同様hot path扱いにする。

Hot path対象:

- `scripts/inbox_watcher.sh`
- `scripts/inbox_write.sh`
- `scripts/bulletin_write.sh`
- `scripts/report_field_set.sh`
- `scripts/gates/gate_report_format.sh`
- `scripts/gates/gate_gunshi_report_precheck.sh`
- `scripts/cmd_save.sh`
- `scripts/cmd_complete_gate.sh`
- `scripts/deploy_task.sh`
- `scripts/ninja_monitor.sh`

Mitigation:

- `scripts/gates/gate_hot_path_no_sync_io.sh` で重い同期I/OをBLOCKする。
- memory DB live insertはasync queue、semantic/causal/gitはtimeoutまたは非同期/キャッシュ経由。
- UserPromptSubmit代替D'もwatcher内同期実行は禁止。

## 6. Implementation Plan

### Phase 1: Audit and Spec

Deliverables:

- `config/cli_events.yaml` draft with current Claude/Codex events.
- `scripts/gates/gate_multi_cli_event_coverage.sh --check`.
- Baseline report showing current gaps.

Acceptance criteria:

- The gate reports the current known gaps without modifying files.
- It flags Codex missing SessionStart/Stop/UserPromptSubmit/Read/Search/PostWrite guards.
- It flags Codex Stop block as forbidden if present.

### Phase 2: Generate/Verify Hook Configs

Deliverables:

- `scripts/generate_cli_hooks.sh --check`.
- Optional `--write` for `.codex/hooks.json` only at first.
- Tests for JSON validity and expected hook entries.

Acceptance criteria:

- `.codex/hooks.json` can be regenerated from spec without manual drift.
- `.claude/settings.json` can be checked without rewriting unrelated permissions/spinner sections.

### Phase 3: Common Wrappers

Deliverables:

- `scripts/hooks/common/*`.
- Existing Claude hook scripts delegate to common wrappers.
- Codex hooks call the same common wrappers via adapter-safe output.

Acceptance criteria:

- Existing unit tests for pre/post bash and write/edit hooks pass.
- Codex pre/post hooks still block known unsafe commands without CLI crash.

### Phase 4: Daemon Compensation

Deliverables:

- Codex stop-equivalent checks in `ninja_monitor.sh` or a dedicated daemon helper.
- Pane active/idle reconciliation that does not rely on Codex Stop hook.
- Smoke tests for idle prompt detection and unread inbox handling.

Acceptance criteria:

- Codex agent reaching idle with unread inbox is nudged or marked for processing without Stop hook block.
- Codex done/completed does not enter hook loop.

### Phase 5: Switch Gate and Script Hardening

Deliverables:

- `scripts/gates/gate_multi_cli_switch.sh`.
- `switch_cli_mode.sh` scope `central`.
- commander restore guard in `shutsujin_departure.sh`.
- all-codex skill script order and safe settings update fixed.
- `restart_watchers.sh --help` and fd inheritance fix.

Acceptance criteria:

- Dry-run reports exact target agents.
- All-Codex execution ends only if gate passes.
- A deliberate mismatch in pane `@agent_cli` or settings causes BLOCK.
- A deliberate Codex Stop block hook causes BLOCK.

## 7. Test Plan

Unit tests:

- `tests/unit/test_multi_cli_event_coverage.bats`
- `tests/unit/test_generate_cli_hooks.bats`
- `tests/unit/test_gate_multi_cli_switch.bats`
- `tests/unit/test_restart_watchers_lock.bats`

Smoke tests:

```bash
bash scripts/gates/gate_multi_cli_event_coverage.sh --check
bash scripts/generate_cli_hooks.sh --check
bash scripts/switch_cli_mode.sh codex --scope central --dry-run
bash scripts/gates/gate_multi_cli_switch.sh --target codex --scope central --dry-run
```

Runtime tests:

1. Switch only `karo` to Codex in a controlled pane.
2. Send recovery inbox.
3. Verify nudge, `/new` mapping, active/idle state, and unread clearance.
4. Run watcher restart and verify parent watcher + child inotify processes.
5. Revert to peacetime allocation and verify gate passes.

E2E responsibility:

- E2Eは家老が担当する（Test Rules）。Unitだけでmulti-CLI成立を完了扱いにしない。
- 家老E2E: idle忍者1名をCodexへ切替→13 event coverage check→D' queue enqueue/drain→inbox nudge送達→元CLIへrollback→dashboard/掲示板へ結果記録。timeout 300秒(5分)でhang時は自動脱出する。

Rollback plan:

1. `gate_multi_cli_event_coverage.sh` / `gate_hot_path_no_sync_io.sh` は初期導入をWARNにする。連続PASS確認後にBLOCKへ昇格。
2. `.codex/hooks.json` はgenerated block単位で戻せるようにし、既存手書きhookを巻き込まない。
3. `.claude/settings.json` はPhase 1ではcheck-only。rollback時は生成物を書いていないため、guard/gateを無効化するだけで戻せる。
4. `config/cli_events.yaml` を削除/無効化する場合は、先に `generate_cli_hooks.sh --check` とdrift guardをWARN化し、全忍者idle確認後に撤去する。
5. 稼働影響が出た場合は既存CLI復旧手順を優先し、hook共通化実装を後退させる。稼働中忍者のpane respawnは家老判断で直列に行う。
6. rollback後に `gate_multi_cli_event_coverage.sh --check` を再実行し、Claude状態でPASSを確認する。

## 8. Success Metrics

Binary metrics:

- `event_coverage_pass`: yes/no
- `switch_gate_pass`: yes/no
- `codex_stop_block_absent`: yes/no
- `settings_pane_process_watcher_match`: yes/no
- `unsafe_command_blocked_on_claude`: yes/no
- `unsafe_command_blocked_on_codex`: yes/no

Quantitative metrics:

- Hook drift count by CLI.
- daemon compensation count.
- switch failure count per 10 runs.
- watcher restart success count.
- Codex hook crash count.

## 9. Open Decisions

1. Should `.claude/settings.json` hooks be generated fully, or should generation be limited to a managed hooks block to avoid touching permissions/spinner settings?
   **Status: OPEN.** Initial impl uses `--check` only (§4.2). Full generation is Phase 2.
2. Should `config/cli_events.yaml` support Copilot/Kimi immediately, or start with Claude/Codex and require explicit unsupported entries for the others?
   **Status: DECIDED.** Start with Claude/Codex only. Other CLIs get `mode: unsupported` entries when added. Reason: 今よりマシか+長期問題なし。2 CLI confirmed schema v1で十分に正の複利。
3. Should Codex stop-equivalent checks live in `ninja_monitor.sh` or a smaller dedicated `cli_event_daemon.sh`?
   **Status: DECIDED (将軍裁定 2026-06-02).** `ninja_monitor.sh` に配置する。Reason: 既存インフラに乗せる原則(殿原則)。ninja_monitorは既にCodex idle検知/respawn/auto-clear/修行トリガーを管理しており、Stop等価処理の自然な配置先。新daemon=不要な複雑さ+新たな状態管理。
   **追加要件(軍師覚醒レビュー)**: ninja_monitorダウン時のfallback。restart_watchers.shのself_health_checkが既にninja_monitor再起動を担うが、ninja_monitor自体のSTALL検知(heartbeat file + cron watchdog)を§10 implで追加すべき。
4. Should all-codex switch be allowed for all roles by default, or require explicit `--scope all` plus a confirmation gate because it consumes subscription limits differently?
   **Status: OPEN.** 現行は将軍スキル(/hensei)で制御。gate追加は§10 impl内で判断。

## 10. Recommended Next Cmd

Purpose:

> multi-CLI event commonization foundationを作り、Claude/Codexのhook coverage差分を機械検出できるようにする。

Acceptance criteria (軍師最終覚醒レビュー反映 2026-06-02 v4):

1. `config/cli_events.yaml` が§4.1 Confirmed schema **v3** (13 event)に従い作成されている（Claude全event+Codex coverage+補完方式が定義）
2. `scripts/gates/gate_multi_cli_event_coverage.sh --check` が13 eventに対して現在の差分を検出し、Codex Stop block forbiddenとschema外Claude hookを検査する
3. `scripts/generate_cli_hooks.sh --check` が `.codex/hooks.json` と `.claude/settings.json` の現物に対してcoverage PASS/WARN/BLOCKを出す
4. `.claude/settings.json` / `.codex/hooks.json` 変更時にPostToolUse guardが `generate_cli_hooks.sh --check` を実行し、schema外hookと正本未追従をBLOCKする
5. `scripts/gates/gate_multi_cli_switch.sh` がswitch前に5点検証（settings/pane process/watcher/hook coverage/reset semantics）を実行する
6. `switch_all_codex.sh` のYAML更新が `yaml_field_set.sh` 経由に変更されている（yaml.safe_dump排除）
7. ninja_monitorのheartbeat file + cron watchdog(STALL検知)が実装されている
8. UserPromptSubmit Codex代替は案D'（永続queue非同期enqueue）として実装され、inbox_watcherのnudge送達遅延**N=50以上の計測でp95<100ms**・semantic timeout時も送達PASS・ninja_monitor再起動後drain PASSをbatsで検証する
9. `gate_hot_path_no_sync_io.sh` がhot path対象10ファイルに対し、重い同期I/O混入を初期WARN→**10セッション連続PASS後にBLOCK昇格**の段階導入で検査する
10. 家老E2E検証計画が実行される: idle忍者1名をCodexへ切替→13 event coverage check→D' queue enqueue/drain→inbox nudge送達→元CLIへrollback。**timeout 300秒(5分)でhang時自動脱出**。結果をdashboard/掲示板に記録する
11. rollback手順（guard/gate WARN化、generated block rollback、全忍者idle確認、直列pane復旧）が設計書に明記されている。**rollback後に `gate_multi_cli_event_coverage.sh --check` を再実行しClaude状態でPASSを確認する**
12. 上記1-11のbats/E2Eテストが追加されている

Not in scope:

- 実際の全軍Codex切替
- Codex Stop hookの復活
- `.claude/settings.json` 全体の生成化（Phase 1は `--check` only）

## 11. References

- `docs/research/gunshi_idle_codex_hook_analysis_20260511.md`
- `context/infrastructure.md` §Codex multi-CLI統合
- `.claude/settings.json`
- `.codex/hooks.json`
- `scripts/inbox_watcher.sh`
- `scripts/restart_watchers.sh`
- `scripts/switch_cli_mode.sh`
- `scripts/shutsujin_departure.sh`
- `~/.codex/skills/shogun-all-codex-switch/scripts/switch_all_codex.sh`
