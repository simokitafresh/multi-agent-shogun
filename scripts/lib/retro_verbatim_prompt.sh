#!/usr/bin/env bash
# Compatibility shim. Retro delivery is owned by the pane transport adapter.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retro_pane_prompt.sh"

retro_verbatim_prompt_key() { retro_pane_prompt_key "$1" "$2"; }
retro_verbatim_prompt_deliver() { retro_pane_prompt_deliver "$@"; }
retro_verbatim_prompt_enqueue() { retro_pane_prompt_enqueue "$@"; }
retro_verbatim_prompt_async() { retro_pane_prompt_async "$@"; }
