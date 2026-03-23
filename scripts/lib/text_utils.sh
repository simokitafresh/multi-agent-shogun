#!/usr/bin/env bash
# text_utils.sh - small text helpers shared by shell scripts

print_padded() {
    local text="$1" width="$2"
    local byte_len char_len extra_bytes display_width pad

    byte_len=$(echo -n "$text" | wc -c)
    char_len=${#text}
    extra_bytes=$((byte_len - char_len))
    display_width=$((char_len + extra_bytes / 2))
    pad=$((width - display_width))

    if (( pad < 0 )); then
        pad=0
    fi

    printf "%s%*s" "$text" "$pad" ""
}
