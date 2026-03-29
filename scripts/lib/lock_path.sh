#!/usr/bin/env bash
# lock_path.sh — Generate /tmp/-based lock file path from any file path
#
# WSL2 /mnt/c (NTFS/DrvFs) 上の flock は不安定なため、
# lock ファイルを /tmp/ (ext4) に配置して排他制御を安定化する。
#
# Usage:
#   source scripts/lib/lock_path.sh
#   lock_file="$(lock_path "/mnt/c/some/file.yaml")"
#   # → /tmp/shogun_lock_<md5hash>.lock

lock_path() {
    local file_path="$1"
    local hash
    hash=$(printf '%s' "$file_path" | md5sum | cut -c1-16)
    printf '/tmp/shogun_lock_%s.lock' "$hash"
}
