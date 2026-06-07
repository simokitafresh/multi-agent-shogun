#!/usr/bin/env bash
# text_utils.sh - small text helpers shared by shell scripts

print_padded() {
    local text="$1" width="$2"
    local char_len byte_len display_width pad

    char_len=${#text}

    # Get byte length without subprocess: C locale treats each byte as a character
    local LC_ALL=C
    byte_len=${#text}

    if (( byte_len == char_len )); then
        # ASCII only: display width equals character count
        display_width=$char_len
    else
        display_width=$((char_len + (byte_len - char_len) / 2))
    fi

    pad=$((width - display_width))
    (( pad < 0 )) && pad=0

    printf "%s%*s" "$text" "$pad" ""
}
