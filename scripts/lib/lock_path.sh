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
    case "$file_path" in
        /mnt/c/*|/mnt/d/*)
            # 純bash DJB2ハッシュ — md5sum subprocessを排除
            # WSL2/NTFS環境でのforkコスト(~10ms)を回避
            local hash=5381 i c
            for (( i=0; i<${#file_path}; i++ )); do
                printf -v c '%d' "'${file_path:$i:1}"
                (( hash = hash * 33 + c ))
            done
            printf '/tmp/shogun_lock_%016x.lock' "$hash"
            ;;
        *)
            printf '%s.lock' "$file_path"
            ;;
    esac
}
