# cmd_508 偵察: スクショ貼付け経路調査（WSL2クリップボード→Claude Code）

- date: 2026-03-04 (JST)
- worker: saizo
- scope: 調査のみ（実装変更なし）

## 1) クリップボード画像の取得方法（AC1）

### 1-1. 失敗系（画像なし）
WSL2からPowerShellを呼び出し、テキストをクリップボードへ入れた後に `Get-Clipboard -Format Image` を実行。

```bash
powershell.exe -NoProfile -Command 'Set-Clipboard -Value "cmd_508_text_probe"; try { $img = Get-Clipboard -Format Image -ErrorAction Stop; if ($null -eq $img) { Write-Output "IMAGE_NULL"; exit 2 } else { Write-Output ("IMAGE_OK {0}x{1}" -f $img.Width,$img.Height); exit 0 } } catch { Write-Output ("IMAGE_ERR " + $_.Exception.Message); exit 3 }'
```

実測結果:
- `IMAGE_NULL`
- exit code `2`

結論:
- 非画像クリップボード時は、例外ではなく `null` を返すケースがある。
- `try/catch` だけでは不十分で、`$null` 判定が必須。

### 1-2. 成功系（画像あり）
PowerShellでテスト画像を生成し、Windows Clipboardへセット後、`Get-Clipboard -Format Image` で取得してPNG保存。

実測結果:
- `SAVED C:\tools\multi-agent-shogun\tmp\cmd_508\clipboard_capture.png`
- `DIM 64x32`
- exit code `0`
- `file` 判定: `PNG image data, 64 x 32`

### 1-3. 保存フォーマット（PNG/BMP/JPEG）
同じClipboard画像を3形式で保存し実測。

| format | 保存可否 | file判定 |
|---|---|---|
| PNG | OK | PNG image data |
| BMP | OK | PC bitmap |
| JPEG | OK | JPEG image data |

## 2) トリガー方式比較（AC2）

| 方式 | pros | cons | 実現性 |
|---|---|---|---|
| tmuxキーバインド（例: Prefix+v） | 最速。CLI入力中でも即時発火。運用が一定化しやすい | tmux設定が必要。誤爆時の挙動設計が必要 | 高 |
| bash関数/alias（例: `sshot`） | 実装最小。履歴に残る。デバッグしやすい | コマンド入力が必要で1テンポ遅い | 高 |
| tmux send-keysで将軍ペイン通知 | 保存後に通知を自動化できる | 誤送信・割込みリスク。排他/対象検証が必要 | 中 |
| クリップボード監視（常駐ポーリング） | 自動化度は高い | WSL2 `/mnt/c` で監視負荷と誤検知リスク。常駐管理が重い | 低〜中 |

## 3) Claude Code側の画像読込確認（AC3）

`view_image` 実地確認:

| file | 結果 |
|---|---|
| `tmp/cmd_508/from_clipboard.png` | 読込成功 |
| `tmp/cmd_508/from_clipboard.jpg` | 読込成功 |
| `tmp/cmd_508/from_clipboard.bmp` | 失敗（unsupported image format `image/bmp`） |

サイズ検証（PNG）:
- 1024x1024: 読込成功
- 4096x4096: 読込成功
- 8192x8192: 読込成功

備考:
- 本検証範囲では `PNG/JPEG` が実用、`BMP` は非推奨。

## 4) 保存先とファイル管理

候補比較:
- `queue/screenshots/`: リポジトリ内で追跡しやすい。運用可視性が高い。
- `/tmp`: 一時用途にはよいが、再利用時に消える。

実務推奨:
- 保存先: `queue/screenshots/`
- 命名: `shot_YYYYmmdd_HHMMSS.png`（衝突回避）
- 直近参照用: `latest.png` を毎回更新
- 清掃: `find queue/screenshots -type f -name 'shot_*.png' -mtime +3 -delete`

確認事項:
- `config/settings.yaml` に `screenshot.path` は現時点で未定義。

## 5) 他ツール/公式情報

### Claude Code（公式）
- 画像は「プロンプトへ貼り付け（Cmd/Ctrl+V）」「ドラッグ&ドロップ」で入力可能。
- `claude -p` では `--image <path>` や直接パス指定、base64/data URL指定が可能。

source:
- https://docs.anthropic.com/en/docs/claude-code/common-workflows

### Cursor（公式ドキュメント）
- Keyboard Shortcuts上は `Ctrl+V` の説明が「code or log」で、画像貼付けの明示記載は確認できず。

source:
- https://docs.cursor.com/en/reference/keyboard-shortcuts

### GitHub Copilot in VS Code（公式）
- チャットへの画像追加は「Add Context > Image from Filesystem」と記載（ファイル添付経路）。

source:
- https://docs.github.com/en/copilot/how-tos/use-chat/ask-copilot-questions-in-ide

## 6) 推奨方式（AC4）

推奨1案:
- trigger: tmuxキーバインド（`Prefix + v`）
- save path: `queue/screenshots/shot_YYYYmmdd_HHMMSS.png` + `queue/screenshots/latest.png`
- notify path: tmux `display-message` で保存パス通知（非割込み）。必要時のみ `send-keys` をオプション化。

理由:
- 速度（手操作最小）と安全性（非割込み通知）を両立しやすい。
- `BMP` 非対応を回避し、`PNG` 固定でClaude Code読込成功率が高い。

### 実装時cmd草案

```yaml
id: cmd_508_impl_clipboard_screenshot
purpose: "WSL2+tmux環境で、Prefix+v一発でClipboard画像をPNG保存し、Claude Code入力に使えるパス通知を行う"
acceptance_criteria:
  - "AC1: Prefix+vで queue/screenshots/shot_*.png が生成される"
  - "AC2: latest.png が常に最新画像へ更新される"
  - "AC3: 画像なし時に exit!=0 + 明示メッセージを返す"
  - "AC4: 通知は display-message 既定、send-keys は opt-in"
  - "AC5: 72時間超の古いshot_*.pngを削除できる"
command: |
  1. scripts/capture_clipboard_image.sh を追加
  2. tmux bind-key v run-shell 'bash scripts/capture_clipboard_image.sh'
  3. docs/research に運用手順と失敗時対処を追記
project: infra
priority: high
status: proposed
```
