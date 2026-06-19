# SSOT Audit Round 1 — 全体横断集約

cmd: `cmd_3458`
担当(集約): tobisaru
作成日: 2026-06-20

---

## 1. 個別偵察ファイル一覧

| 忍者 | ファイル | 担当スコープ | 状態 |
|---|---|---|---|
| hayate | [hayate.md](ssot-audit-round1/hayate.md) | `scripts/lib/**`, `scripts/gates/**` | 完了 |
| kagemaru | [kagemaru.md](ssot-audit-round1/kagemaru.md) | `.claude/**`, `.codex/**`, `scripts/*.sh`, `scripts/*.py`(ルートのみ) | 完了 |
| hanzo | [hanzo.md](ssot-audit-round1/hanzo.md) | daemon/monitor/watch/layout/switch/model系スクリプト | 完了 |
| saizo | — | 未割当(cmd_3458対象外) | なし |
| kotaro | — | 別cmd(cmd_3449_impl)担当 | なし |

---

## 2. AC1: カテゴリ別ハードコード件数 (全体横断)

計測対象: `scripts/`, `.claude/`, `.codex/`, `config/`

| カテゴリ | ファイル数 | 主な発見 | 詳細 |
|---|---:|---|---|
| Agent名(ninja 6名) | 33 | fallback roster、日本語名マッピング等 | hayate #1-6, kagemaru K-01, hanzo D1 |
| tmux window literal | 22 | `shogun:agents`/`shogun:main`/`shogun:2` が複数ファイルに分散 | hayate #7-10, kagemaru K-03/K-04, hanzo D2 |
| 絶対パス (`/mnt/c/tools/...`) | 14 | フックJSON・スクリプト内埋め込み | kagemaru K-05 |
| model/CLI literal | 多数 | `opus`/`sonnet`/`haiku`/`gpt-*`等 | hayate #11-16, kagemaru K-08, hanzo D3 |
| Commander roles (shogun/karo/gunshi) | 多数 | 役割名ハードコード | kagemaru K-02, hanzo (switch_cli_mode等) |
| 外部PJパス (DM-Signal等) | 5+ | `/mnt/c/Python_app/DM-signal`等 | hayate #26-30 |

**最重要 SSOT 参照先**:

| ドメイン | 現行SSOT | 主ヘルパー |
|---|---|---|
| 忍者名リスト | `config/settings.yaml:cli.agents` | `scripts/lib/agent_config.sh:get_ninja_names` |
| 全エージェント | `config/settings.yaml:cli.agents` | `get_all_agents`, `get_allowed_targets` |
| CLI起動コマンド | `config/cli_profiles.yaml:profiles.*.launch_cmd` | `scripts/lib/cli_lookup.sh:cli_launch_cmd` |
| ペインターゲット | live `tmux #{@agent_id}` | `scripts/lib/pane_lookup.sh:pane_lookup` |
| モデルカラー | `scripts/lib/model_colors.sh` | — (消費者は呼び出すだけ) |
| lockファイルパス | `scripts/lib/lock_path.sh:lock_path` | — |
| プロジェクトパス | `config/projects.yaml` | — |

---

## 3. AC2: config配下 YAML 間の二重定義

### 3-1. `gist_url` — 同値3箇所重複

| ファイル:行 | 値 | 対象 |
|---|---|---|
| `config/settings.yaml:58` | `https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c` | グローバル |
| `config/projects.yaml:6` | 同上 | dm-signal |
| `config/projects.yaml:23` | 同上 | infra |

**SSOT候補**: `config/settings.yaml:gist_url` を正本とし、`config/projects.yaml` のプロジェクト個別gist_urlはPJ固有の場合のみ残す。dm-signalとinfraの値がグローバルと同一であれば削除して参照先を統一する。

### 3-2. `launch_cmd` — パス不一致

| ファイル:行 | 値 | 用途 |
|---|---|---|
| `config/settings.yaml:14` (shogunエージェント) | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | shogun agent個別起動 |
| `config/cli_profiles.yaml:16` (claudeプロファイル) | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | claude CLIプロファイル共通 |

**不一致の意味**: `.local/bin/claude` = auto-update版、`bin/claude` = fixed 2.1.87版(CLAUDE.md推奨)。
将軍は手動起動するため`settings.yaml`の`launch_cmd`は将軍ペイン向け。忍者CLIは`cli_profiles.yaml`を経由。
→ 意図的差異の可能性があるが、設計意図がコメントに明示されていない。将軍のsettings.yaml launch_cmdが`.local/bin`を指している場合、version pinが効かないリスクがある。
**統一案**: `settings.yaml` の shogun `launch_cmd` を `bin/claude` (pin版) に統一するか、settings.yaml側のlaunch_cmdを廃止してcli_profiles.yaml一本に集約する。裁定が必要。

### 3-3. `skill.save_path` / `skill.local_path` — 同値の二重定義

| ファイル:行 | フィールド | 値 |
|---|---|---|
| `config/settings.yaml:5` | `skill.save_path` | `/mnt/c/tools/multi-agent-shogun/skills/` |
| `config/settings.yaml:6` | `skill.local_path` | `/mnt/c/tools/multi-agent-shogun/skills/` |

**統一案**: どちらかを正本とし、もう一方を削除または参照にする。使用箇所をgrepして確認の上、不要な方を除去する。

### 3-4. `effort` — ドメイン差異 (SSOT問題なし)

| ファイル | 値 | ドメイン |
|---|---|---|
| `config/settings.yaml:56` | `effort: high` | CLI起動effortレベル |
| `config/projects.yaml:projects.{0,4,6}.priority` | `high` | プロジェクト優先度 |

**評価**: 文字列が同じだが意味が異なる。SSOT問題ではない。

---

## 4. 横断優先修正リスト

個別mdの推奨と全体集約を統合した優先順:

| 優先度 | 修正内容 | 根拠 | 対応個別md |
|---|---|---|---|
| **P1** | `scripts/lib/known_ninjas.sh` を `agent_config.sh` に統合 | 忍者リストのSSOTが2本存在。drift直行 | hayate P1 |
| **P1** | tmux window名を一か所に集約 (`shogun:agents` vs `shogun:2` fallback) | 22ファイルに分散。resolver不在 | hayate P1, kagemaru K-03/K-04, hanzo D2 |
| **P1** | `gate_ninja_workaround_rate.sh` 日本語名reverse mappingを `get_japanese_name` に置換 | 忍者ID+日本語名の二重埋め込み | hayate P1 |
| **P2** | `agent_config.sh` に `get_system_agents`, `get_core_agents` helperを追加 | shogun/karo/gunshi+ninjaの配列が各スクリプトで再構成されている | kagemaru K-02, hanzo D1 |
| **P2** | DM-Signal絶対パスdefaultをプロジェクト設定から読むよう修正 | `/mnt/c/Python_app/DM-signal`と`DM-Signal`のcase差も存在 | hayate P2 (#26-30) |
| **P2** | hookの運用YAMLガードパターンを1か所に集約 | 5hookが独立正規表現でpath setを定義 | kagemaru K-10 |
| **P2** | model family分類を `model_resolve.sh` に統一 | reset_layout/ninja_monitor/model_analysisが独自分類 | hanzo D3 |
| **P2** | `watcher supervision` を `daemon_supervisor.sh` 中心に整理 | restart_watchers/daemon_watchdog/ninja_monitorが重複管理 | hanzo D4 |
| **P3** | `config/settings.yaml:gist_url` vs `config/projects.yaml` の重複解消 | dm-signal/infraのgist_urlがグローバルと同値 | hayate P3, 本集約 AC2-3-1 |
| **P3** | `settings.yaml:shogun.launch_cmd` のバイナリパス整合 | `.local/bin`(auto) vs `bin/`(pin)の不一致 | 本集約 AC2-3-2 |
| **P3** | `skill.save_path` / `skill.local_path` 二重定義解消 | 同一値の重複フィールド | 本集約 AC2-3-3 |

---

## 5. AC4: 未統合個別md の状況

| 対象 | 理由 | 対応 |
|---|---|---|
| saizo.md | saizo はcmd_3458偵察に未割当。別タスク担当 | 次周回で偵察スコープ追加時に作成 |
| kotaro.md | kotaro は cmd_3449_impl 担当でcmd_3458対象外 | 次周回で偵察スコープ追加時に作成 |

**次に統合すべきファイル**: saizo偵察(スコープ未定義)をP2として設定し、`skills/**`, `tests/**`, `queue/**`ディレクトリのSSOT調査を追加することを推奨する。

---

## 6. 参照

- `docs/research/ssot-audit-round1/hayate.md` — scripts/lib + gates (30項目)
- `docs/research/ssot-audit-round1/kagemaru.md` — .claude + .codex + root scripts (10グループ)
- `docs/research/ssot-audit-round1/hanzo.md` — daemon/monitor/watch/layout/switch/model (4重複グループ)
