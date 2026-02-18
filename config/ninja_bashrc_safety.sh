#!/usr/bin/env bash
# ══════════════════════════════════════════════════
# ninja_bashrc_safety.sh — 忍者bash環境の安全装置
# 破壊操作(D001/D005/D007/D008)をalias/functionでブロック
# Usage: source config/ninja_bashrc_safety.sh
# ══════════════════════════════════════════════════

# D005: sudo禁止
alias sudo='echo "BLOCKED: sudo is forbidden (D005)" >&2; false'

# D007: mkfs/dd/fdisk禁止
alias mkfs='echo "BLOCKED: mkfs is forbidden (D007)" >&2; false'
alias dd='echo "BLOCKED: dd is forbidden (D007)" >&2; false'
alias fdisk='echo "BLOCKED: fdisk is forbidden (D007)" >&2; false'
