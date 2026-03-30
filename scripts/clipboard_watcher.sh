#!/bin/bash
# clipboard_watcher.sh — Windowsクリップボードの画像を常時監視・自動保存
# Win+Shift+S でスクショ撮るだけで latest.png に自動保存される。
# 殿が「スクショ見て」と言えば将軍が即座に確認できる。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="${SCRIPT_DIR}/queue/screenshots"
LATEST="${SCREENSHOT_DIR}/latest.png"
POLL_INTERVAL=3
LAST_HASH=""
RETENTION_HOURS=72
TEMP_PATH="${SCREENSHOT_DIR}/.clipboard_temp.png"
WIN_TEMP_PATH=$(wslpath -w "$TEMP_PATH")

mkdir -p "$SCREENSHOT_DIR"

echo "[clipboard_watcher] started (poll=${POLL_INTERVAL}s)"

while true; do
    # PowerShellでクリップボード画像のハッシュ取得+temp保存を一括実行（2回→1回に統合）
    RESULT=$(powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Drawing
\$img = Get-Clipboard -Format Image
if (\$null -eq \$img) {
    Write-Output 'NO_IMAGE'
    exit 0
}
\$ms = New-Object System.IO.MemoryStream
\$img.Save(\$ms, [System.Drawing.Imaging.ImageFormat]::Png)
\$hash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(\$ms.ToArray())
).Replace('-','').Substring(0,16)
\$img.Save('${WIN_TEMP_PATH}', [System.Drawing.Imaging.ImageFormat]::Png)
\$img.Dispose()
\$ms.Dispose()
Write-Output \"HASH:\$hash\"
" 2>/dev/null) || true

    # 画像なし or エラー → スキップ
    if [[ ! "$RESULT" =~ ^HASH: ]]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    CURRENT_HASH="${RESULT#HASH:}"

    # 同じ画像 → スキップ
    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    # 新しい画像を検出 → temp→最終パスに移動
    LAST_HASH="$CURRENT_HASH"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    FILENAME="shot_${TIMESTAMP}.png"
    FILEPATH="${SCREENSHOT_DIR}/${FILENAME}"

    if [ -f "$TEMP_PATH" ]; then
        mv "$TEMP_PATH" "$FILEPATH"
        cp "$FILEPATH" "$LATEST"
        echo "[clipboard_watcher] $(date +%H:%M:%S) saved: ${FILENAME}"

        # 古いスクリーンショットを削除
        find "$SCREENSHOT_DIR" -type f -name 'shot_*.png' ! -name "$FILENAME" -mmin +$((RETENTION_HOURS * 60)) -delete 2>/dev/null || true
    fi

    sleep "$POLL_INTERVAL"
done
