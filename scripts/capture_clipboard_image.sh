#!/bin/bash
# capture_clipboard_image.sh — Prefix+v でWindowsクリップボード画像をPNG保存
# Usage: bash scripts/capture_clipboard_image.sh
#
# WSL2環境でPowerShellを呼び出し、クリップボード上の画像をPNG形式で保存する。
# 保存先: queue/screenshots/shot_YYYYMMDD_HHMMSS.png + latest.png
# 72時間超の古いスクリーンショットを自動削除する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="${SCRIPT_DIR}/queue/screenshots"
RETENTION_HOURS=72

# 保存先ディレクトリ確保
mkdir -p "$SCREENSHOT_DIR"

# ファイル名生成
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="shot_${TIMESTAMP}.png"
FILEPATH="${SCREENSHOT_DIR}/${FILENAME}"
LATEST="${SCREENSHOT_DIR}/latest.png"

# WSL2パスをWindowsパスに変換
WIN_PATH=$(wslpath -w "$FILEPATH")

# PowerShellでクリップボード画像を取得・保存
PS_RESULT=$(powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Drawing
\$img = Get-Clipboard -Format Image
if (\$null -eq \$img) {
    Write-Output 'IMAGE_NULL'
    exit 2
}
\$img.Save('${WIN_PATH}', [System.Drawing.Imaging.ImageFormat]::Png)
\$img.Dispose()
Write-Output 'IMAGE_OK'
exit 0
" 2>&1) || PS_EXIT=$?

PS_EXIT=${PS_EXIT:-0}

# 結果判定
if [ "$PS_EXIT" -ne 0 ] || echo "$PS_RESULT" | grep -q "IMAGE_NULL"; then
    tmux display-message "Screenshot: クリップボードに画像がありません"
    exit 1
fi

# 保存確認
if [ ! -f "$FILEPATH" ]; then
    tmux display-message "Screenshot: 保存失敗 - ファイルが生成されませんでした"
    exit 1
fi

# latest.png を更新
cp "$FILEPATH" "$LATEST"

# 古いスクリーンショットを削除（72時間超）
find "$SCREENSHOT_DIR" -type f \( -name 'shot_*.png' -o -name 'ntfy_*.png' \) -mmin +$((RETENTION_HOURS * 60)) -delete 2>/dev/null || true

# 成功通知
tmux display-message "Screenshot: ${FILEPATH}"
