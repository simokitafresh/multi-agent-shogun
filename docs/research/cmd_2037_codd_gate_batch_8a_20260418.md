# cmd_2037 CoDD改善バッチ8-A

## 対象

- `scripts/gates/gate_karo_startup.sh`
- `scripts/gates/gate_gunshi_cs_checklist.sh`
- `scripts/gates/gate_field_get.sh`

## 目的

前回改善後も残っていた startup / validation 系 hot path の subprocess をさらに削り、起動ごとの固定コストを下げる。

## 実装

### `gate_karo_startup.sh`

- `tmux capture-pane | grep -oP | tail` を `awk` 1-pass に置換
- inbox 未読件数を `grep -c` から `awk` に置換
- `pending_decisions.yaml` の total / resolved 件数を `awk` 1-pass で同時集計

### `gate_gunshi_cs_checklist.sh`

- `python3 -c` 2発を単一 `awk` 走査へ統合
- `self_study/consultation` の `cs_checklist` / `causal_chain` 欠落確認と、
  draft review の `APPROVE + FM許容` パターン検出を 1-pass で同時処理
- 後段の `grep|sed|wc` も shell 分岐と `awk` 集計に置換

### `gate_field_get.sh`

- `tasks/hayate.yaml` / `config/settings.yaml` / `config/projects.yaml` の参照を
  `field_get` 複数回から `field_get_multi` に集約
- WARN 判定を `grep` ではなく bash pattern match に変更
- `shogun_to_karo.yaml` の cmd 件数確認を `grep -c` から `awk` に変更

## 計測

実測: `/usr/bin/time -f '%e' bash <script>` を 10 回実行し median 採用。

| スクリプト | Before | After | 差分 |
|------------|--------|-------|------|
| `gate_karo_startup.sh` | 190ms | 140ms | `-26.3%` |
| `gate_gunshi_cs_checklist.sh` | 199ms | 10ms | `-95.0%` |
| `gate_field_get.sh` | 404ms | 40ms | `-90.1%` |

補足:

- `gate_karo_startup.sh` は live 実行で 1 回だけ 1.13s outlier が出たが、median は 140ms で安定。
- `gate_gunshi_cs_checklist.sh` は現行ログに未整備 entry があるため exit code は WARN(1) を返すが、処理時間は大幅に短縮された。

## 検証

- `bash -n scripts/gates/gate_karo_startup.sh`
- `bash -n scripts/gates/gate_gunshi_cs_checklist.sh`
- `bash -n scripts/gates/gate_field_get.sh`
- `bats tests/unit/test_gate_karo_startup.bats`
- `bats tests/unit/test_field_get.bats`
- `bats tests/unit/test_gate_gunshi_cs_checklist.bats`

全て PASS。
