#!/usr/bin/env bash
# note_figure_render.sh — HTML断片(artifactの節など)をnote記事用PNGへ描画する
# Usage: bash scripts/note_figure_render.sh <in.html> <out.png> [width_px=600] [max_height_px=1800]
#  - Windows Chrome headless(隔離profile必須: D009) / device-scale 2 / 下余白を自動トリム
#  - in.html は自己完結(外部CSS/フォント/画像なし)。ライト固定で書く(dark media queryは無視される)
set -euo pipefail
IN="$1"; OUT="$2"; W="${3:-600}"; H="${4:-1800}"
CHROME="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
[ -x "$CHROME" ] || { echo "FAIL: chrome not found: $CHROME" >&2; exit 1; }
STAGE=/mnt/c/tmp/note_figure_render; mkdir -p "$STAGE/profile"
cp "$IN" "$STAGE/in.html"
timeout 90 "$CHROME" --headless=new --user-data-dir="C:\\tmp\\note_figure_render\\profile" --no-first-run --hide-scrollbars \
  --force-device-scale-factor=2 --window-size="${W},${H}" --screenshot="C:\\tmp\\note_figure_render\\out.png" \
  "file:///C:/tmp/note_figure_render/in.html" >/dev/null 2>&1 || true
[ -s "$STAGE/out.png" ] || { echo "FAIL: screenshot not produced" >&2; exit 1; }
python3 "$(dirname "$0")/lib/png_trim_bottom.py" "$STAGE/out.png" "$OUT" 40
echo "RENDERED $OUT"
