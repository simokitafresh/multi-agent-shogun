#!/usr/bin/env bash
# Shared canonical ninja names for WA logging and data-quality gates.

KNOWN_NINJAS=(hayate kagemaru hanzo saizo kotaro tobisaru unknown)
KNOWN_NINJAS_CSV="hayate,kagemaru,hanzo,saizo,kotaro,tobisaru,unknown"
KNOWN_NINJAS_DISPLAY="hayate/kagemaru/hanzo/saizo/kotaro/tobisaru/unknown"

is_known_ninja() {
    local candidate="${1:-}"
    case "$candidate" in
        hayate|kagemaru|hanzo|saizo|kotaro|tobisaru|unknown) return 0 ;;
        *) return 1 ;;
    esac
}

known_ninjas_display() {
    printf '%s\n' "$KNOWN_NINJAS_DISPLAY"
}
