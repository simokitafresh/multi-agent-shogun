# CLI/Model 2層SSOT設計 — デフォルト編成と動的編成の分離
<!-- generated: 2026-06-21T15:27:00+09:00 by gunshi idle analysis -->

## 背景

殿指示(2026-06-21): CLI種別(Claude/Codex)とモデル(Opus/Sonnet/GPT-5.5)の切替を実践検証し、知見を環境に埋め込んだ。その過程で設計課題が浮上:

- **現状**: settings.yamlが「デフォルト編成」と「現在の動的編成」の両方を兼ねている
- **問題**: 動的変更(shogun-cli-switch)でsettings.yamlを変更→tmux再起動(shutsujin)後も動的変更が残る
- **殿の指摘**: 「デフォルト＝tmux自体の再起動と、起動後に動的なcli変更への追随は異なる」

## 設計: 2層SSOT (案C — 殿承認2026-06-21)

### 原則

| 層 | 正本 | 責務 | 変更契機 |
|---|------|------|---------|
| **デフォルト層** | `config/cli_profiles.yaml` の `defaults:` セクション | tmux再起動時の初期編成定義 | 殿が恒久的に編成を変えたい時のみ |
| **動的層** | `config/settings.yaml` の各agent type/model_name | 起動後の現在編成。ninja_monitor/build_cli_commandが参照 | shogun-cli-switchで随時変更(オントロジー駆動) |

### 流れ

```
tmux再起動(shutsujin)
  → shutsujin_departure.sh がデフォルト層(cli_profiles.yaml defaults)を読む
  → settings.yamlの各agent type/model_nameをデフォルト値で上書き
  → 全pane起動(build_cli_commandがsettings.yamlを参照)
  → 全員がデフォルト編成で起動

起動後
  → 殿「hanzoをGPT5.5 low fastonに」
  → shogun-cli-switch実行
  → settings.yaml type/model_name変更 + respawn(オントロジー駆動: 概念Aの変更が全連鎖を自動更新)
  → ninja_monitorはsettings.yamlを読む → 動的変更に自動追随

次回tmux再起動
  → デフォルト層に復帰。動的変更はリセット
```

### メリット・デメリット比較(殿と議論済み)

| 案 | メリット | デメリット |
|----|---------|-----------|
| A: settings.yaml永続化 | SSOT単一。ninja_monitor整合 | 一時変更が永続化。デフォルトとの区別不能 |
| B: tmux変数のみ | 再起動でデフォルト復帰 | ninja_monitorがsettings.yaml不整合で壊れる |
| **C: 2層SSOT(採用)** | 再起動でデフォルト復帰 + ninja_monitor整合 + 動的変更自由 | cli_profiles.yamlにdefaults追加の実装が必要 |

## 実装計画

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `config/cli_profiles.yaml` | `defaults:` セクション追加(各agentのデフォルトtype/model_name) |
| `scripts/shutsujin_departure.sh` | 起動時にdefaultsからsettings.yaml type/model_nameを上書きするロジック追加 |
| `skills/shogun-cli-switch/SKILL.md` | 2層SSOT設計の説明追記 |
| `context/infrastructure.md` | 2層SSOT設計の索引追記 |

### cli_profiles.yaml defaults セクション例

```yaml
defaults:
  # tmux再起動時に settings.yaml を初期化する値
  # 殿が恒久的に編成を変えたい場合のみ変更
  shogun: {type: claude, model_name: claude-opus-4-6}
  karo: {type: claude, model_name: claude-opus-4-6}
  gunshi: {type: claude, model_name: claude-opus-4-6}
  hayate: {type: claude, model_name: gpt-5.5-low}
  kagemaru: {type: claude, model_name: gpt-5.5-low}
  hanzo: {type: claude, model_name: gpt-5.5-low}
  saizo: {type: claude, model_name: claude-sonnet-4-6}
  kotaro: {type: claude, model_name: claude-sonnet-4-6}
  tobisaru: {type: claude, model_name: claude-sonnet-4-6}
```

### shutsujin_departure.sh 追加ロジック

```bash
# デフォルト編成をsettings.yamlに復元
restore_default_formation() {
    local defaults_yaml="config/cli_profiles.yaml"
    local settings_yaml="config/settings.yaml"

    # defaults:セクションから各agentのtype/model_nameを読み取り
    # yaml_field_set.shでsettings.yamlを上書き
    python3 -c "
import yaml
with open('$defaults_yaml') as f:
    d = yaml.safe_load(f)
defaults = d.get('defaults', {})
for agent, cfg in defaults.items():
    for key in ('type', 'model_name'):
        if key in cfg:
            print(f'{agent} {key} {cfg[key]}')
" | while read agent key value; do
        bash scripts/lib/yaml_field_set.sh "$settings_yaml" "$agent" "$key" "$value"
    done
}
```

## オントロジーとの関係

- **概念A = CLI種別(type)**: shogun-cli-switchで変更→settings.yaml + tmux変数 + respawnが連鎖更新
- **概念B = モデル(model_name)**: CLI種別に依存。Claude CLIならClaude系、Codex CLIならGPT系
- **リセットトリガー = shutsujin**: デフォルト層→settings.yaml初期化→全pane再起動
- **Guard 9b**: respawn-pane通過(正規操作)。model_switchのみBLOCK

## 検証済み知見(本設計の前提)

| 知見 | 検証方法 | 結果 |
|------|---------|------|
| Claude CLIのターミナル設定残留→Codex exit 2 | 双方向6連続テスト | reset追加で100%解消 |
| CLI種別変更時のrespawnスキップ | 3人同時切替テスト | CLI type change検出で強制respawn |
| model_nameファミリー不整合 | settings.yaml type/model不整合検出 | 自動リセットで解消 |
| CLI switch後の自動recovery | CTX確認 | cli_switch_pending→CTX:0%待機 |
| config.toml全Codex共有 | effort変更テスト | respawn忍者のみ反映 |

## 追加課題: 2層SSOT未適用の設定 (#3-#5)

殿指摘(2026-06-21): 全件対処。優先順位で先送りするな。

### #3: launch_cmd (version pin/unpin)

| 項目 | 内容 |
|------|------|
| 現状 | pin-2.1.87/unpin-latestでsettings.yamlの個別launch_cmdを変更 |
| 問題 | tmux再起動後もunpin状態が残る。デフォルト(pinned 2.1.87)に戻るべき |
| 対策 | cli_profiles.yaml defaultsにlaunch_cmd追加。shutsujinで復元 |
| 変更対象 | cli_profiles.yaml defaults + shutsujin_departure.sh |

### #4: config.toml model_reasoning_effort

| 項目 | 内容 |
|------|------|
| 現状 | ~/.codex/config.toml に全Codex共有の1値。per-agent設定なし |
| 問題 | hayateだけlowにしたくてもsaizo/kagemaruもlowになる |
| 対策案A | Codex CLI起動引数で上書き可能か調査（--reasoning-effort等） |
| 対策案B | per-agent config.toml生成(~/.codex/config_hayate.toml)+起動時XDG_CONFIG_HOME差替え |
| 対策案C | respawn時に一時的にconfig.toml書換え→起動→元に戻す(race条件注意) |
| 変更対象 | switch_cli_mode.sh or build_cli_command + config.toml管理 |

### #5: config.toml service_tier (fast)

| 項目 | 内容 |
|------|------|
| 現状 | config.tomlに全Codex共有の1値 |
| 問題 | #4と同根。per-agentでfast on/off不可 |
| 対策 | #4と同一アプローチで解決 |

### 実装cmd一覧(全件)

| cmd | 内容 | 対象ファイル |
|-----|------|------------|
| cmd_A | cli_profiles.yaml defaults追加 + shutsujin default復元 | cli_profiles.yaml, shutsujin_departure.sh |
| cmd_B | launch_cmd 2層SSOT化 | cli_profiles.yaml defaults, shutsujin_departure.sh |
| cmd_C | Codex per-agent effort/fast設定の調査+実装 | config.toml管理, build_cli_command, switch_cli_mode.sh |

## 因果リンク

- → [[殿指摘_CLI_model_20260621]] CLI種別とモデルの関係
- → [[operational_ontology]] 概念Aの変更が全連鎖を自動更新
- → [[agent_formation_management]] 編成管理SSOT
- → [[Codex_exit_2_root_cause]] ターミナル設定残留問題
