# cmd_323 R2-Task1 (Blind B): sync_pane_vars.sh 仕様調査

**調査者**: hayate (Opus)
**日付**: 2026-02-25
**parent_cmd**: cmd_323
**対象**: scripts/sync_pane_vars.sh + scripts/lib/model_detect.sh + scripts/lib/cli_lookup.sh

---

## §1 全体処理フロー

### 1.1 起動〜初期化

```
sync_pane_vars.sh
│
├─ set -e（エラー即停止）
├─ SCRIPT_DIR 解決（スクリプトの2階層上 = プロジェクトルート）
├─ source cli_lookup.sh  ← SSOT参照ライブラリ読込
│   └─ グローバルキャッシュ3つ初期化（_CLI_LOOKUP_{TYPE,TIER,PROFILE}_CACHE）
├─ source model_detect.sh ← 実モデル検出ライブラリ読込
│   └─ 関数定義のみ（detect_real_model）
└─ AGENT_PANES 連想配列定義（karo=1 ... tobisaru=9）
```

### 1.2 将軍ペイン同期（L38-46）

```
shogun:main ペイン
│
├─ detect_real_model "shogun" "shogun:main"
│   ├─ 成功 → shogun_model = 検出値
│   └─ 失敗 → shogun_model = "Opus"（ハードコードフォールバック）
├─ tmux show-options @model_name → shogun_current
└─ shogun_current ≠ shogun_model → tmux set-option @model_name 更新
```

### 1.3 エージェントペインループ（L48-74）

```
for agent in AGENT_PANES:
│
├─ 1. cli_profile_get(agent, "display_name")
│   └─ settings.yaml → type解決 → cli_profiles.yaml → display_name
│      例: hayate → type未指定 → default "claude" → profiles.claude.display_name = "Opus"
│      例: sasuke → type "codex" → profiles.codex.display_name = "Codex"
│
├─ 2. display_name 空なら cli_type(agent) にフォールバック
│   └─ "claude" / "codex" 等の文字列が返る
│
├─ 3. detect_real_model(agent, target)
│   ├─ 成功 → real_model = 検出値（例: "Opus 4.6"）
│   └─ 失敗 → real_model = ""
│
├─ 4. effective_model = real_model ?: display_name
│   └─ 実モデル値があれば優先、なければ設定値
│
└─ 5. current ≠ effective_model → tmux set-option 更新
    └─ ログに "detected" or "fallback" を表示
```

### 1.4 データフロー概念図

```
                    ┌──────────────┐
                    │ settings.yaml│
                    │ cli.agents.* │
                    └──────┬───────┘
                           │ type解決
                    ┌──────▼───────┐
                    │cli_profiles  │
                    │  .yaml       │
                    └──────┬───────┘
                           │ display_name
                           ▼
              ┌──── Level 3: 設定値 ◄──── フォールバック
              │
              │     ┌────────────────┐
              │     │ capture-pane   │
              │     │ バナー解析     │
              │     └───────┬────────┘
              │             │ 検出成功？
              │     ┌───────▼────────┐
              ├──── │ Level 1: 実検出│ ──YES─→ effective_model
              │     └───────┬────────┘
              │             │ NO
              │     ┌───────▼────────┐
              ├──── │ Level 2: cache │ ──YES─→ effective_model
              │     │ @real_model    │
              │     └───────┬────────┘
              │             │ NO
              └─────────────┼─────────→ effective_model
                            │
                    ┌───────▼────────┐
                    │ tmux set-option│
                    │ @model_name    │
                    └────────────────┘
```

---

## §2 3段フォールバック構造

### Level 1: 実モデル検出（model_detect.sh — capture-paneバナー解析）

| CLI種別 | 検出パターン | 抽出方法 |
|---------|-------------|---------|
| claude | `▝▜█████▛▘  {Opus\|Sonnet\|Haiku} {X.Y} · {Plan}` | grep精密マッチ → sed抽出 |
| codex | `│ model: {model_name} /model to change │` | grep → sed抽出（"loading"除外） |
| copilot/kimi | 未対応 | return 1 |

**検索範囲**: `capture-pane -S -1000`（直近1000行）
**成功時**: tmux @real_model ペイン変数にキャッシュ保存

### Level 2: tmuxキャッシュ（@real_model ペイン変数）

Level 1失敗時に前回の検出結果を参照。バナーがスクロールオフした場合の安全網。

### Level 3: 設定値（cli_lookup.sh → settings.yaml + cli_profiles.yaml）

2段参照チェーン:
```
settings.yaml: cli.agents.{name}.type → (未定義なら cli.default → "claude")
                    ↓
cli_profiles.yaml: profiles.{type}.display_name → (例: "Opus", "Codex")
```

sync_pane_vars.sh L53-57のさらなるフォールバック:
```
display_name = cli_profile_get(agent, "display_name")
if empty → display_name = cli_type(agent)  // "claude" / "codex" 等の文字列
```

### 将軍ペインの特殊フォールバック

sync_pane_vars.sh L40: `|| shogun_model="Opus"`
将軍は settings.yaml の agents に定義されていないため、detect_real_model 失敗時は "Opus" ハードコード。

---

## §3 cli_lookup.sh 内部構造

### 設定パス解決（L20-23）

| 変数 | 解決方法 | 環境変数オーバーライド |
|------|---------|---------------------|
| `_CLI_LOOKUP_SETTINGS` | `CLI_ADAPTER_SETTINGS` → デフォルト `config/settings.yaml` | **可能**（L020教訓反映済み） |
| `_CLI_LOOKUP_PROFILES` | ハードコード `config/cli_profiles.yaml` | **不可** |

### キャッシュ機構（L26-31）

```bash
unset → declare -gA（bash 4.2+グローバル） → declare -A フォールバック
```

3つのキャッシュ: TYPE_CACHE, TIER_CACHE, PROFILE_CACHE（agent:key形式）
re-source時にunsetで初期化。L021教訓（declare -Aスコープ問題）は -gA で解決済み。

### YAMLパース（python3 -c）

各参照でpython3プロセスを起動してyaml.safe_load。yq非依存。
settings.yaml の値形式に2種対応:
- 辞書形式: `hayate: { tier: jonin }` → `agent_cfg.get(field)`
- 文字列形式: `hanzo: codex` → typeフィールドとして直接返却

---

## §4 エッジケース

### EC-1: バナースクロールオフ（影響: 中）

**状況**: CLIが大量出力し、バナー行が直近1000行外にスクロール
**挙動**: capture-pane -S -1000 で検出不可 → Level 2 キャッシュ参照
**リスク**: 一度も検出成功していない場合（初回起動直後に大量出力）→ Level 3 フォールバック
**対応策**: キャッシュ機構が安全網として機能。capture-pane -S - (全履歴)にする案もあるが、パフォーマンス影響あり

### EC-2: ペイン不存在（影響: 低）

**状況**: tmux capture-pane 対象ペインが存在しない
**挙動**: `2>/dev/null` でエラー黙殺 → output="" → 検出失敗 → Level 2/3 フォールバック
**リスク**: 存在しないペインに@model_nameを設定しようとするとset-optionが失敗するが、show-optionsの `|| echo ""` とset-optionのエラーは非致命的（set -eで停止する可能性あり→EC-6参照）

### EC-3: python3不在または yaml モジュール欠如（影響: 高）

**状況**: python3未インストールまたはPyYAML欠如
**挙動**: `2>/dev/null` でエラー黙殺 → 全参照が空文字 → display_name="" → cli_typeもpython3依存で空 → effective_model=""
**リスク**: @model_name が空文字列に設定される。致命的ではないが表示異常
**対応策**: python3+PyYAMLは前提条件として文書化されているが、起動時チェックはない

### EC-4: settings.yaml 未定義エージェント（影響: なし）

**状況**: AGENT_PANESに定義されているがsettings.yamlに未定義のエージェント
**挙動**: `_cli_lookup_settings_get` → `agents.get(agent, {})` = {} → `cli.default` = "claude"
**対応**: 正常動作。設計通りのフォールバック

### EC-5: /model切替後のタイムラグ（影響: 低）

**状況**: エージェントが /model で切替直後、次のsync_pane_vars.sh実行まで古い値
**挙動**: @model_nameは前回実行時の値のまま
**対応**: sync_pane_vars.shが定期実行されていれば次回で反映。呼出間隔に依存

### EC-6: set -e とペイン操作エラーの組合せ（影響: 中）

**状況**: ペイン不存在時に `tmux set-option -p -t` が失敗
**挙動**: set -eにより即座にスクリプト停止 → 以降のエージェントが未処理
**現状**: show-optionsは `|| echo ""` でガード済みだが、L68-69の比較→set-optionパスで set-option自体には `2>/dev/null` なし。ただしペインが存在しなければcapture-paneの段階で空→current=""→effective_model=display_nameとなり、set-optionに到達する可能性はある
**リスク**: ペイン消失のタイミング次第で中断。ただし実運用上はtmuxペインが消失する状況は限定的

---

## §5 改善提案

### 提案1: python3一括パースによる起動高速化（優先度: 中）

**現状**: 9エージェント × 最大2回(type + profile) = 最大18回のpython3プロセス起動。キャッシュは同一プロセス内のみ有効（sync_pane_vars.shは1回実行で終了）。

**提案**: 全エージェントのtype + display_nameを1回のpython3呼び出しで一括取得し、シェル変数にexportする。

```bash
# 案: 1回のpython3で全エージェント情報を取得
eval "$(python3 -c "
import yaml
with open('config/settings.yaml') as f: s = yaml.safe_load(f)
with open('config/cli_profiles.yaml') as f: p = yaml.safe_load(f)
agents = s.get('cli',{}).get('agents',{})
default_type = s.get('cli',{}).get('default','claude')
for name in ['karo','sasuke','kirimaru','hayate','kagemaru','hanzo','saizo','kotaro','tobisaru']:
    a = agents.get(name, {})
    t = a if isinstance(a,str) else a.get('type', default_type)
    dn = p.get('profiles',{}).get(t,{}).get('display_name','')
    print(f'_BULK_TYPE_{name}={t}')
    print(f'_BULK_DN_{name}={dn}')
")"
```

**効果**: python3起動回数 18→1。WSL2環境ではプロセス起動オーバーヘッドが顕著なため効果大。
**注意**: cli_lookup.shの公開APIは既存の他スクリプトからも使われるため、一括パースはsync_pane_vars.sh専用の最適化として追加し、cli_lookup.shのAPIは変更しない。

### 提案2: _CLI_LOOKUP_PROFILESの環境変数オーバーライド対応（優先度: 低）

**現状**: `_CLI_LOOKUP_SETTINGS` はCLI_ADAPTER_SETTINGS環境変数でオーバーライド可能（L020教訓反映済み）だが、`_CLI_LOOKUP_PROFILES` はハードコード。

**提案**:
```bash
_CLI_LOOKUP_PROFILES="${CLI_PROFILES_PATH:-${_CLI_LOOKUP_DIR}/config/cli_profiles.yaml}"
```

**効果**: テスト時にモック用cli_profiles.yamlを差し込み可能に。

### 提案3: set -e安全性の強化（優先度: 低）

**現状**: tmux set-option（L43, L69）にエラーガードなし。ペインが実行中に消失した場合、set -eで後続エージェントが未処理。

**提案**: set-optionに `2>/dev/null || true` を追加、またはスクリプト冒頭のset -eを除去してexit codeをハンドリング。

```bash
tmux set-option -p -t "$target" @model_name "$effective_model" 2>/dev/null || true
```

---

## §6 教訓との照合

| 教訓 | 本調査での確認結果 |
|------|------------------|
| L034 (awk/sed固定インデント) | model_detect.shのsedパターンは `.*▝▜█████▛▘` で柔軟マッチ。固定インデント依存なし。問題なし |
| L020 (設定パス環境変数共有) | cli_lookup.sh L22で `CLI_ADAPTER_SETTINGS` オーバーライド対応済み。ただし `_CLI_LOOKUP_PROFILES` は未対応（提案2で指摘） |
| L010 (status行先頭マッチ) | 本調査対象スクリプトにYAMLのstatus行パースなし。該当なし |
| L009 (whitelist .gitignore) | 本調査はコード変更なし。該当なし |
| L030 (current_project死コード) | sync_pane_vars.shはcurrent_projectを参照しない。PJ非依存の基盤スクリプト。該当なし |
| L046 (capture-pane false positive) | model_detect.sh L42で精密パターン `(Opus|Sonnet|Haiku)[[:space:]]+[0-9]+\.[0-9]+` + `tail -1` で対策済み |
