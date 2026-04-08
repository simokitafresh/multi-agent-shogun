#!/usr/bin/env bash
# layout_string.sh — 動的LAYOUT_STRING生成（3列 2-3-3配置）
# Usage: source scripts/lib/layout_string.sh
#        generate_layout_string [window] [pane_base]
#
# shutsujin_departure.sh と reset_layout.sh の両方で使用。
# ウィンドウサイズから tmux select-layout 用の文字列を動的生成する。
# agent_config.sh が source 済みであること。

generate_layout_string() {
    local window="${1:-shogun:agents}"
    local pb="${2:-1}"

    local win_w win_h
    win_w=$(tmux display-message -t "$window" -p '#{window_width}')
    win_h=$(tmux display-message -t "$window" -p '#{window_height}')

    # 列幅
    local col1_pct
    col1_pct=$(get_layout_col1_width_pct)
    local c1_w=$(( win_w * col1_pct / 100 ))
    local c23_remain=$(( win_w - c1_w - 2 ))   # -2: 列境界線2本
    local c2_w=$(( c23_remain / 2 ))
    local c3_w=$(( c23_remain - c2_w - 1 ))     # -1: 境界線1本

    # col1 行高さ（karo + gunshi）
    local karo_h
    karo_h=$(get_layout_karo_height)
    # ガード: karo_hがウィンドウ高さを圧迫する場合は自動調整（最低でもgunshiに3行確保）
    local karo_max=$(( win_h - 4 ))
    if (( karo_h > karo_max )); then
        karo_h=$karo_max
    fi
    local c1_r2_h=$(( win_h - karo_h - 1 ))

    # col2,3 行高さ（3等分、最低1行保証）
    local r1_h=$(( win_h / 3 ))
    local r2_h=$(( win_h / 3 ))
    local r3_h=$(( win_h - r1_h - r2_h - 2 ))
    if (( r3_h < 1 )); then r3_h=1; fi

    # x座標
    local c2_x=$(( c1_w + 1 ))
    local c3_x=$(( c1_w + c2_w + 2 ))

    # y座標
    local c1_y2=$(( karo_h + 1 ))
    local cy2=$(( r1_h + 1 ))
    local cy3=$(( r1_h + r2_h + 2 ))

    # レイアウト文字列本体
    local body="${win_w}x${win_h},0,0"
    body+="{${c1_w}x${win_h},0,0"
    body+="[${c1_w}x${karo_h},0,0,${pb}"
    body+=",${c1_w}x${c1_r2_h},0,${c1_y2},$((pb+1))]"
    body+=",${c2_w}x${win_h},${c2_x},0"
    body+="[${c2_w}x${r1_h},${c2_x},0,$((pb+2))"
    body+=",${c2_w}x${r2_h},${c2_x},${cy2},$((pb+3))"
    body+=",${c2_w}x${r3_h},${c2_x},${cy3},$((pb+4))]"
    body+=",${c3_w}x${win_h},${c3_x},0"
    body+="[${c3_w}x${r1_h},${c3_x},0,$((pb+5))"
    body+=",${c3_w}x${r2_h},${c3_x},${cy2},$((pb+6))"
    body+=",${c3_w}x${r3_h},${c3_x},${cy3},$((pb+7))]}"

    # tmux checksum計算
    local csum
    csum=$(python3 -c "
body = '${body}'
csum = 0
for c in body:
    csum = (csum >> 1) + ((csum & 1) << 15)
    csum = (csum + ord(c)) & 0xFFFF
print(format(csum, '04x'))
")

    echo "${csum},${body}"
}
