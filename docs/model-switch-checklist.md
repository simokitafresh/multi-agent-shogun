# モデル切替チェックリスト

cmd_142合議の教訓を仕組み化した切替手順。
Stage 1-3（SSOT基盤・スクリプト置換・ルール文書）が完了していることが前提。

## Phase 1: 切替前（Pre-Switch）

### 自動チェック

- [ ] `bash scripts/model_switch_preflight.sh [target_agent]` を実行
- [ ] 結果が **PASS** であることを確認（FAILなら切替禁止）
- [ ] WARN項目を確認し、タスク実行中の忍者がいれば完了を待つ

### 手動確認

- [ ] `config/settings.yaml` の現在の設定をバックアップ
  ```bash
  cp config/settings.yaml config/settings.yaml.bak
  ```
- [ ] 切替対象の忍者を決定（カナリア1名 → 段階展開）
- [ ] `cli_profiles.yaml` に切替先CLIのプロファイルが定義済みか確認
- [ ] 切替先CLIがインストール済みか確認（`which <cli_command>`）

## Phase 2: 切替中（During Switch）

### Step 1: カナリア展開（1名のみ）

- [ ] `config/settings.yaml` でカナリア忍者の `type` を変更
  ```yaml
  agents:
    <ninja_name>:
      type: <new_cli_type>
      tier: <tier>
  ```
- [ ] カナリア忍者の inbox_watcher を再起動
  ```bash
  # 該当ペインで Ctrl-C → watcher再起動
  tmux send-keys -t shogun:2.<pane> C-c
  # shutsujin_departure.sh が再起動を処理
  ```
- [ ] カナリア忍者に `/clear` を送信（新設定を反映）
- [ ] 一巡確認:
  - [ ] タスクを1つ割り当てて正常に処理されるか
  - [ ] inbox_watcher が nudge を正常に配信するか
  - [ ] ninja_monitor が idle/busy を正しく検知するか
  - [ ] CTXパースが正しく動作するか（ログ確認）

### Step 2: 段階展開（問題なければ）

- [ ] 残りの対象忍者の `type` を順次変更
- [ ] 各忍者の watcher 再起動 + `/clear`
- [ ] 各忍者にテストタスクを割り当てて動作確認

## Phase 3: 切替後（Post-Switch）

### 30分監視

- [ ] `ninja_monitor.sh` のログを監視
  ```bash
  tail -f logs/ninja_monitor.log
  ```
- [ ] 全忍者が正常にタスクを処理していることを確認
- [ ] inbox 覗き（他人のinboxを読む等の異常行動）がないか確認
- [ ] CTX消費が異常に速くないか確認

### 安定確認

- [ ] 3タスク以上の正常完了を確認
- [ ] preflight を再実行して PASS を確認
  ```bash
  bash scripts/model_switch_preflight.sh
  ```
- [ ] バックアップファイルを削除
  ```bash
  rm config/settings.yaml.bak
  ```

## ロールバック手順

切替後に問題が発生した場合の即応手順。

### 即時ロールバック（30分以内）

1. バックアップから復元
   ```bash
   cp config/settings.yaml.bak config/settings.yaml
   ```
2. 対象忍者の watcher を再起動（Ctrl-C → 自動再起動）
3. 対象忍者に `/clear` を送信
4. `bash scripts/model_switch_preflight.sh` で元の状態を確認

### 段階ロールバック（部分的に問題がある場合）

1. 問題のある忍者のみ `settings.yaml` の `type` を元に戻す
2. 該当忍者の watcher 再起動 + `/clear`
3. 正常に動作する忍者はそのまま継続

## 教訓（cmd_142より）

1. **インフラにモデル名ハードコードがあると CLI 切替だけでは追従しない** → Stage 1-3 で解消済み
2. **モデルによって「性格」が異なる** → カナリア展開で事前検証必須
3. **ルール文書にモデル名を入れるな** → ロールで分けよ（上忍/下忍）
4. **骨格=モデル非依存、味付け=モデル特性チューニング** → cli_profiles.yaml で分離済み
5. **切替前に全grep + 段階展開 + ロールバック準備必須** → 本チェックリスト + preflight script
