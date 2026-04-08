# cmd_323 R4-Task3: archive_completed.sh コードレビュー
# blind_id: B (tobisaru / Sonnet 4.6)
# date: 2026-02-25

## 1. 全体構造の把握

### 処理フロー
```
引数パース (keep_results, cmd_id)
  → archive_cmds()     # shogun_to_karo.yaml から完了cmdをアーカイブ
  → archive_dashboard() # dashboard.md の古い戦果をアーカイブ
  → archive.done フラグ出力 (CMD_ID指定時のみ)
```

### 主要関数
| 関数 | 行 | 役割 |
|------|----|------|
| cleanup() | 14 | tmpファイル後始末 (trap EXIT) |
| usage_error() | 26-31 | 引数エラー表示 |
| archive_cmds() | 60-143 | shogun_to_karo.yaml の完了cmdを archive/cmds/ に退避 |
| archive_dashboard() | 148-181 | dashboard.md の古い行を archive/ に退避、直近N件のみ残す |

### データの流れ
- **入力**: `queue/shogun_to_karo.yaml`, `dashboard.md`
- **出力**: `queue/archive/shogun_to_karo_done.yaml`, `queue/archive/cmds/{cmd_id}_{status}_{date}.yaml`, `queue/archive/dashboard_archive.md`
- **tmpファイル**: `/tmp/stk_active_$$.yaml`, `/tmp/stk_done_$$.yaml`, `/tmp/dash_trim_$$.md`

---

## 2. 問題点一覧

### HIGH

#### H1: CMD_IDパストラバーサルリスク (行 48-51, 192-194)
- **severity**: HIGH
- **category**: Security / Path Traversal
- **line**: 48-51, 192-194
- **description**:
  CMD_IDの検証が `[[ "$CMD_ID" != cmd_* ]]` (glob一致) のため、
  `cmd_../../etc/passwd` のような値が検証を通過する。
  Line 192-194 で `mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"` および
  `touch "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"` が実行されると、
  プロジェクトディレクトリ外にファイルが作成される可能性がある。

  例: `CMD_ID=cmd_../../outside` → `queue/gates/cmd_../../outside/archive.done`
  　　→ 実パス: `{PROJECT_DIR}/../outside/archive.done`
- **recommendation**:
  ```bash
  # 変更前
  if [ -n "$CMD_ID" ] && [[ "$CMD_ID" != cmd_* ]]; then

  # 変更後
  if [ -n "$CMD_ID" ] && [[ ! "$CMD_ID" =~ ^cmd_[0-9]+$ ]]; then
  ```

---

### MEDIUM

#### M1: statusフィールド取得の固定インデント依存 (行 99-101) — L034関連
- **severity**: MEDIUM
- **category**: Robustness / YAML Parsing
- **line**: 99-101
- **description**:
  `grep '^  status: '` は先頭2スペースを前提としている。
  YAMLのインデントが変動した場合（実例: shogun_to_karo.yaml で2→0スペース変動あり、L034）、
  statusが取得できず空文字→完了cmdとして扱われず、アーカイブされない。
  L034教訓「固定インデントに依存させるな」が直接該当。
- **recommendation**:
  ```bash
  # 変更後: インデントに依存しないマッチ
  status_val=$(printf '%s\n' "$entry" \
      | grep -E '^\s+status: ' | head -1 \
      | sed 's/^[[:space:]]*status: //' | tr -d '[:space:]')
  ```

#### M2: statusフィールドがネストしたstatusと誤マッチする可能性 (行 99-101) — L010関連
- **severity**: MEDIUM
- **category**: Correctness / YAML Parsing
- **line**: 99-101
- **description**:
  `grep '^  status: '` は2スペースインデントのstatusをマッチする。
  YAMLエントリ内にresult.statusのような2スペースインデントのネストしたstatusが
  存在した場合、誤マッチの可能性がある。L010教訓「statusは先頭マッチすべき」に対して、
  インデント付きのため完全な保護にならない。
  現時点のshogun_to_karo.yamlのスキーマでは発生していないが、潜在的リスク。
- **recommendation**:
  statusがトップレベルフィールドであることを構造的に保証するか、
  YAMLパーサ(python3 -c + yaml.safe_load)での解析に変更する。

#### M3: statusの正規表現が末尾アンカーなし (行 109)
- **severity**: MEDIUM
- **category**: Correctness
- **line**: 109
- **description**:
  `[[ "$status_val" =~ ^(completed|cancelled|absorbed|halted|superseded|done) ]]`
  は末尾 `$` がないため、"completed_extra" のような予期しない値にも
  "completed" としてマッチし `BASH_REMATCH[1]="completed"` となる。
  ただし現状のYAMLスキーマでは発生しないため低リスクだが潜在的バグ。
- **recommendation**:
  ```bash
  if [[ "$status_val" =~ ^(completed|cancelled|absorbed|halted|superseded|done)$ ]]; then
  ```

#### M4: flockの subshell 内で `return 1` を使用 (行 133, 175)
- **severity**: MEDIUM
- **category**: Code Quality / Readability
- **line**: 133, 175
- **description**:
  `( ... return 1 ... )` のように `( )` サブシェル内で `return 1` を使用している。
  bashでは関数外の `return` はサブシェルを終了させる（`exit 1` と等価）が、
  非慣用的で読みにくい。意図が不明確。
- **recommendation**:
  ```bash
  flock -w 10 200 || { echo "[archive] WARN: flock timeout on QUEUE_FILE"; exit 1; }
  ```

#### M5: KEEP_RESULTS=0 が検証を通過する (行 42-46)
- **severity**: MEDIUM
- **category**: Input Validation
- **line**: 42-46
- **description**:
  `^[0-9]+$` は "0" を有効として通過させる。コメントには「正の整数」とあるが、
  `bash archive_completed.sh 0` を実行するとダッシュボードの全行がアーカイブされる
  （ゼロ件を残す）。意図しない全削除が発生する可能性がある。
- **recommendation**:
  ```bash
  if [[ ! "$KEEP_RESULTS" =~ ^[1-9][0-9]*$ ]]; then
  ```

#### M6: DASH_ARCHIVE書き込みがflockの外 (行 167-171 vs 173-178)
- **severity**: MEDIUM
- **category**: Correctness / Race Condition
- **line**: 167-171 (outside flock), 173-178 (inside flock)
- **description**:
  DASH_ARCHIVEへの追記（行167-171）はflockの外で実行される。
  その後のflock取得（行175）が失敗した場合、
  DASH_ARCHIVEには行が追加されたがDASHBOARDは削除されていない状態になる。
  次回実行時に同じ行が再度アーカイブされ、重複エントリが発生する。
- **recommendation**:
  DASH_ARCHIVEへの書き込みをflockブロック内に移動する。
  ```bash
  (
      flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; exit 1; }
      # アーカイブ書き込みをflock内に移動
      {
          echo ""
          echo "# Archived $(date '+%Y-%m-%d %H:%M')"
          sed -n "${archive_first_line},${last_data_line}p" "$DASHBOARD"
      } >> "$DASH_ARCHIVE"
      sed "${archive_first_line},${last_data_line}d" "$DASHBOARD" > "/tmp/dash_trim_$$.md"
      mv "/tmp/dash_trim_$$.md" "$DASHBOARD"
  ) 200>"$DASHBOARD.lock"
  ```

---

### LOW

#### Lo1: cmd_idパース失敗時のWARNメッセージに詳細不足 (行 120)
- **severity**: LOW
- **category**: Observability
- **line**: 120
- **description**:
  `echo "[archive] WARN: failed to parse cmd_id at lines ${s}-${e}" >&2`
  はエントリの内容を含まないため、デバッグ時に原因特定が難しい。
- **recommendation**:
  ```bash
  echo "[archive] WARN: failed to parse cmd_id at lines ${s}-${e}: $(printf '%s\n' "$entry" | head -3)" >&2
  ```

#### Lo2: `cut -d: -f1` がパスにコロンを含む場合に脆弱 (行 153)
- **severity**: LOW
- **category**: Robustness
- **line**: 153
- **description**:
  `grep -n '...' "$DASHBOARD" | cut -d: -f1` はgrepの `-n` 出力の行番号抽出に使用しているが、
  DAASHBOARDパスにコロンが含まれると正しく行番号が取れない。
  現在のDAASHBOARD="$PROJECT_DIR/dashboard.md"にコロンはないが、潜在的脆弱性。
- **recommendation**:
  ```bash
  mapfile -t result_lines < <(grep -n '^| [0-9]' "$DASHBOARD" | grep -oP '^\d+')
  ```
  またはgrep出力を `awk -F: '{print $1}'` で処理。

#### Lo3: archive_cmds が何も完了cmdがない場合のログが不完全 (行 76-80)
- **severity**: LOW
- **category**: Observability
- **line**: 76-80
- **description**:
  `starts[@]` が空の場合 "no entries found" を出力して終了するが、
  kept/archivedの合計が分からない。一貫性のあるログ形式にする方が追跡しやすい。
- **recommendation**:
  メッセージを `"[archive] cmds: archived=0 kept=0 (no entries found)"` に統一。

---

## 3. セキュリティ観点レビュー

| 観点 | 評価 | 詳細 |
|------|------|------|
| コマンドインジェクション | OK | 外部入力はすべてクォートされている。python3 -c等の動的コード実行なし。 |
| パストラバーサル | **要対応** | CMD_ID検証が不十分 (H1参照) |
| tmpファイル競合 | OK | `$$` PID付き一時ファイル名。cleanup trapで確実に削除。 |
| flock排他制御 | OK (一部) | QUEUE_FILE/DASHBOARD更新はflock保護。DASH_ARCHIVE書き込みが漏れ (M6) |
| シェル変数展開 | OK | 変数はすべてダブルクォート囲み。`set -u` で未定義変数をエラー扱い。 |
| L047/L043 (python注入) | N/A | 本スクリプトにpython3 -c使用なし |

---

## 4. 良い点

1. **完璧なcleanupトラップ (行14)**: `trap cleanup EXIT` により、スクリプトが正常終了・エラー終了・シグナル受信いずれの場合も全tmpファイルが確実に削除される。`set -euo pipefail` と組み合わせることで、中断時のゴミファイル残留リスクがほぼゼロ。

2. **アトミックなファイル更新 (行135, 177)**: tmpファイルへの書き込み → `mv` による置換パターンにより、QUEUE_FILEとDASHBOARDの更新が原子的に行われる。部分書き込みによるファイル破損がない。

3. **flockによる並行アクセス保護 (行132-136, 174-178)**: 複数プロセスが同時実行した場合でも、重要ファイルの更新がflock(タイムアウト10秒付き)で保護されている。

4. **PID付き一時ファイル (行14)**: `$$` によるプロセス固有の一時ファイル名でtmpファイル衝突を防止。

5. **柔軟な引数パース (行33-40)**: `$1` が `cmd_*` で始まる場合にCMD_IDとして解釈するロジックにより、引数順序の柔軟性がある。ユーザビリティが高い。

---

## 5. 総評

全体的にシェルスクリプトのベストプラクティス（set -euo pipefail、trap、flock、atomic mv）が適切に使用された高品質なスクリプト。
主な改善点はCMD_IDのパストラバーサル対策（HIGH）と、DASH_ARCHIVEのflock外書き込み（MEDIUM）の2点。
残りのMEDIUM/LOW指摘は現状のユースケース（karo単独実行）では実害は少ないが、堅牢性向上のために対応が望ましい。

---
*生成: tobisaru (Sonnet 4.6) / cmd_323 R4-Task3*
