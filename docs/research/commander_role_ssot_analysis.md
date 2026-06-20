# Commanderロール SSOT分析 — cmd_3470

作成日: 2026-06-20T15:40:17
担当: saizo
根拠: `queue/tasks/saizo.yaml` cmd_3470 / 殿指摘「洗脳の証拠」2026-06-20 15:16

## 背景

殿指摘: Commanderロール(shogun/karo/gunshi)が86ファイルに直書き。最大の未保護概念。
忍者名はすでに `config/settings.yaml` → `agent_config.sh` → Guard16 のSSOT chain確立済み。
Commanderロールには同等の保護がない。本文書はパターン分類とSSOT設計方針を確定する。

## 計測条件

- 対象: `scripts/` (sh + py)
- コマンド: `rg -l '\b(shogun|karo|gunshi)\b' scripts/ -g '*.sh' -g '*.py'`
- 実測: 92ファイル (殿指摘の86は概算)
- 実測日時: 2026-06-20T15:38 JST

## 参照: SSOT Registry ([[ssot-registry.md]])

`ロール名` 行より:
- SSOT正本: `config/settings.yaml:cli.agents` + `instructions/parts/roles/*`
- ヘルパー: `agent_config.sh:get_agent_role` (部分的)
- Guard状態: Guard16がエージェント名直書きを一部検出。**ロール名全般のGuardは未整備**
- 消費者: 23ファイル (ロール名concept限定計測値)

---

## パターン分類

### カテゴリA: ファイルパス参照 (30件) — 🔴HIGH RISK

**パターン**: `queue/inbox/(shogun|karo|gunshi).yaml` のliteral直書き

**代表例**:
```sh
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"          # cmd_complete_gate.sh:6176
inbox_file="$SCRIPT_DIR/queue/inbox/shogun.yaml"         # gate_shogun_startup.sh:354
GUNSHI_INBOX="$SCRIPT_DIR/queue/inbox/gunshi.yaml"       # inbox_write.sh:1495
```

**該当ファイル**:
cmd_complete_gate.sh, gates/gate_shogun_startup.sh, gates/gate_karo_startup.sh,
gates/gate_gunshi_startup.sh, gates/gate_gunshi_cs_checklist.sh, gates/gate_cmd_state.sh,
gunshi_gate_sync.sh, gunshi_next_action.sh, inbox_write.sh, cmd_delegate.sh,
inbox_watcher.sh, ntfy_cmd.sh

**リスク**: Commanderロール名変更 or 新Commander追加時に全箇所修正が必要

---

### カテゴリB: is_core_agent / role判定 (条件分岐) — 🔴HIGH RISK

**パターン**: role名に基づいた条件分岐

**代表例**:
```sh
# inbox_write.sh:53 — is_core_agent関数
case "$1" in
    shogun|karo|gunshi) return 0 ;;
esac

# hooks/session_end_clear_check.sh:18
if [[ "$agent_id" != "shogun" ]]; then exit 0; fi

# hooks/prompt_state_inject.sh:156
[[ "$agent_id" == "shogun" ]] || return 0

# inbox_write.sh:1262
if [ "$FROM" = "ninja_monitor" ] && [ "$TARGET" != "karo" ] && [ "$TARGET" != "shogun" ]; then
```

**問題**: `is_core_agent()` が inbox_write.sh にのみ存在し、agent_config.sh のSSOTに未統合。
他スクリプトがis_core_agentを使わず直接パターンマッチしている二重実装状態。

---

### カテゴリC: inbox宛先 (6件) — 🟡MEDIUM RISK

**パターン**: `inbox_write.sh karo/shogun/gunshi "..."` の直接呼出し

**代表例**:
```sh
bash scripts/inbox_write.sh karo "..." cmd_new shogun   # cmd_complete_gate.sh
bash scripts/inbox_write.sh shogun "$message" gate_clear cmd_complete_gate  # L255
bash scripts/inbox_write.sh karo "..." task_notify      # gates/gate_cycle_health.sh
```

**該当ファイル**: cmd_complete_gate.sh (4件), gates/gate_cycle_health.sh (1件), deploy_task.sh (1件)

---

### カテゴリD: BULLETIN_NOTIFY (11件) — 🟡MEDIUM RISK

**パターン**: `BULLETIN_NOTIFY=karo,gunshi` の環境変数設定

**代表例**:
```sh
BULLETIN_NOTIFY=karo,gunshi timeout 10 bash "$SCRIPT_DIR/scripts/bulletin_write.sh" ...
BULLETIN_NOTIFY=shogun bash "$SCRIPT_DIR/scripts/bulletin_write.sh" ...
```

**該当ファイル**: cmd_complete_gate.sh (4件), gates/gate_shogun_startup.sh (2件),
ninja_monitor.sh (2件), insight_write.sh (1件), auto_failure_lesson.sh (1件)

**bulletin_write.sh内部**:
```sh
NOTIFY_TARGETS=("shogun" "karo" "gunshi")  # L321 — 3役固定ハードコード
KNOWN_AGENTS_RAW="shogun karo gunshi $(get_ninja_names ...)"  # L33
```

---

### カテゴリE: tmux @agent_id 比較 (24件) — 🟢正当直書き

**パターン**: `if [[ "$agent_id" == "shogun" ]]`

**判定**: tmuxから動的取得した値と比較しているため、SSOTとして問題なし。
ロール名を変更する場合は変更が必要になるが、これはSSOT問題ではなくロール設計変更の問題。

**代表ファイル**: hooks/session_end_clear_check.sh, hooks/prompt_state_inject.sh,
hooks/pre-karo-edit-guard.sh, inbox_watcher.sh

---

### カテゴリF: role専用スクリプト (22ファイル) — 🟢正当直書き

**パターン**: スクリプト自体が特定roleのみに使われる

**スクリプト名にrole名を含む**:
- gates/gate_shogun_startup.sh, gates/gate_karo_startup.sh, gates/gate_gunshi_startup.sh
- gates/gate_shogun_memory.sh, gates/gate_gunshi_cs_checklist.sh, gates/gate_gunshi_report_precheck.sh
- lesson_write_karo.sh, lesson_write_shogun.sh, karo_workaround_log.sh
- gunshi_gate_sync.sh, gunshi_next_action.sh, gunshi_gate_reflux.sh, etc.

**判定**: スクリプト自体がrole専用設計。スクリプト内の自己参照hardcoding は正当。

---

### カテゴリG: ログ出力 (83件) — 🟢正当直書き

**パターン**: `echo "karo inbox: OK"`, `echo "[INFO] shogun..."` 等のメッセージ

**判定**: cosmetic表示のみ。behavior変更なし。変更コスト>便益。

---

## パターン集計

| カテゴリ | 件数 | リスク | SSOT対応 |
|---------|------|--------|---------|
| A: ファイルパス参照 | 30件/12ファイル | 🔴HIGH | ヘルパー化対象 |
| B: role判定条件分岐 | 約20件/15ファイル | 🔴HIGH | ヘルパー移管対象 |
| C: inbox宛先 | 6件/3ファイル | 🟡MEDIUM | 状況依存(下記参照) |
| D: BULLETIN_NOTIFY | 11件/5ファイル | 🟡MEDIUM | 定数化対象 |
| E: tmux比較 | 24件/10ファイル | 🟢低 | 正当直書き |
| F: role専用スクリプト | 22ファイル | 🟢低 | 正当直書き |
| G: ログ出力 | 83件/多数 | 🟢低 | 正当直書き |

---

## SSOT設計方針

### 1. ヘルパー化対象（scripts/lib/agent_config.sh への追加）

#### 1-1: `COMMANDER_ROLES` 定数追加
```bash
# config/settings.yaml 由来ではなく固定定数（Commanderは動的変更なし）
readonly COMMANDER_ROLES_ARRAY=(shogun karo gunshi)
COMMANDER_ROLES="shogun karo gunshi"  # space-separated
```

#### 1-2: `is_commander_role <name>` 関数追加
```bash
is_commander_role() {
    case "$1" in
        shogun|karo|gunshi) return 0 ;;
    esac
    return 1
}
```
**移管元**: inbox_write.sh の `is_core_agent()` を agent_config.sh へ昇格。
inbox_write.sh は `source agent_config.sh && is_commander_role` を呼ぶよう変更。

#### 1-3: `get_commander_inbox_path <role>` 関数追加
```bash
get_commander_inbox_path() {
    local role="$1"
    echo "${_AGENT_CONFIG_SCRIPT_DIR}/queue/inbox/${role}.yaml"
}
```
**移管元**: カテゴリAの30件のliteral直書き

#### 1-4: bulletin_write.sh の `NOTIFY_TARGETS` 定数化
```bash
# bulletin_write.sh L33, L321 を agent_config.sh の定数参照に変更
source agent_config.sh
NOTIFY_TARGETS=("shogun" "karo" "gunshi")  # → COMMANDER_ROLES_ARRAYから生成
```

---

### 2. 正当直書き（変更不要）

以下はSSOT化の対象外：

| パターン | 理由 |
|---------|------|
| `if [[ "$agent_id" == "shogun" ]]` (tmux動的取得後の比較) | 動的値との比較。SSOTとは別問題 |
| role専用スクリプト内の自己参照 | スクリプト設計上必然。変更コスト>便益 |
| ログメッセージ内のrole名 | cosmetic。behavioral影響なし |
| `gate_{role}_startup.sh` 内の自role参照 | ファイル自体がrole専用 |

---

### 3. Guard16パラメータ（Guard拡張対象）

**Guard16現状**: `gate_no_hardcoded_ninja_list.sh` — 3+ninja names on same lineを検出

**拡張候補**:
1. **Commanderロール向け新Guard（Guard16b or Guard18）**:
   - `queue/inbox/(shogun|karo|gunshi).yaml` のliteral直書きを検出
   - `is_core_agent()` の inbox_write.sh 以外での再実装を検出
   - 検出後: `agent_config.sh の is_commander_role() を使え` とガイド

2. **bulletin_write.sh の NOTIFY_TARGETS 固定値化を強制**:
   - `NOTIFY_TARGETS=.*shogun.*karo.*gunshi` の手動記述をBLOCK
   - `${COMMANDER_ROLES_ARRAY[@]}` 展開形式のみ許可

**既存Guard16との整合**:
- Guard16: 3+忍者名の同一行出現を検出
- 新Guard: `queue/inbox/{commander}.yaml` パス literal を検出
- 両者は独立動作可能。pre-write-edit-combined.sh に追加

---

## 実装済み確認 (2026-06-20T16:10 JST)

[[agent_config.sh]] (`scripts/lib/agent_config.sh`) L155-175 に以下が実装済み:

```bash
# L155: get_commander_names() — COMMANDER_ROLES定数相当の関数
get_commander_names() {
    echo "$_AGENT_CONFIG_COMMANDER_NAMES"
}

# L160: is_commander_role() — カテゴリB二重実装解消済み (inbox_write.sh の is_core_agent から委譲)
is_commander_role() {
    local name="$1"
    case " $_AGENT_CONFIG_COMMANDER_NAMES " in
        *" $name "*) return 0 ;;
    esac
    return 1
}

# L168: get_commander_inbox_path() — カテゴリA literal直書きのヘルパー化済み
get_commander_inbox_path() {
    local role="$1"
    if ! is_commander_role "$role"; then return 1; fi
    printf '%s/queue/inbox/%s.yaml\n' "$_AGENT_CONFIG_SCRIPT_DIR" "$role"
}
```

[[inbox_write.sh]] (`scripts/inbox_write.sh`) L51-53 での委譲確認:

```bash
is_core_agent() {
    if type is_commander_role >/dev/null 2>&1; then
        is_commander_role "$1"   # ← agent_config.sh L160 への委譲実装済み
```

`get_commander_inbox_path` は [[inbox_write.sh]] L1500 でも使用確認済み:
```bash
GUNSHI_INBOX="$(get_commander_inbox_path gunshi)"  # L1500
```

**bulletin_write.sh 未解消確認** ([[bulletin_write.sh]] L321):
```bash
NOTIFY_TARGETS=("shogun" "karo" "gunshi")  # ← ★★☆ 依然hardcode残存 (2026-06-20確認)
```

---

## 実装優先順位

| 優先 | 実装内容 | 状態 (2026-06-20確認) |
|------|---------|-----|
| ★★★ | `is_commander_role()` を agent_config.sh に追加 + inbox_write.sh 移管 | ✅ 完了 (L160/L51) |
| ★★☆ | `get_commander_inbox_path()` 追加 + カテゴリA 30件置換 | ✅ 関数完了/全件置換は未確認 |
| ★★☆ | bulletin_write.sh の NOTIFY_TARGETS を COMMANDER_ROLES から生成 | ❌ 未完了 (L321 hardcode残存) |
| ★☆☆ | Guard16b: `queue/inbox/{commander}.yaml` 直書き検出 | ❌ 未実装 |
| ☆☆☆ | カテゴリC(inbox宛先)ヘルパー化 | ❌ 未実装(ROI低) |

---

## 実装手順(次cmd向け)

```
Phase 1: agent_config.sh 拡張
  1. COMMANDER_ROLES定数追加
  2. is_commander_role() 追加 (inbox_write.sh の is_core_agent を移管)
  3. get_commander_inbox_path() 追加

Phase 2: 消費者書き換え (高ROIから)
  1. inbox_write.sh: is_core_agent → is_commander_role
  2. カテゴリA 30件: literal → get_commander_inbox_path() 呼出し
  3. bulletin_write.sh: NOTIFY_TARGETS → COMMANDER_ROLES_ARRAY

Phase 3: Guard追加
  1. gate_no_hardcoded_commander_path.sh 作成
  2. pre-write-edit-combined.sh へ追加登録
```

---

## 因果リンク

- `[[Commanderロール86ファイル最大穴]]` → `[[is_core_agent二重実装]]` → `[[agent_config.sh未統合]]`
- `[[忍者名SSOT確立_Guard16]]` → `[[Commanderロール未保護]]` → `[[本分析]]`
- `[[殿指摘_洗脳早期終了_20260620]]` → `[[SSOT棚卸し]]` → `[[偵察分類SSOT設計]]`
- 実装先: [[agent_config.sh]] L155-175 / [[inbox_write.sh]] L51-56 / [[bulletin_write.sh]] L321(未解消)
- 参照: [[ssot-registry.md]] ロール名行
