#!/usr/bin/env bats
# test_inbox_watcher_karo_nudge.bats — 家老向けcmd_new nudge強化テスト

# awkロジック抽出: inbox_watcher.sh send_nudge関数内のcmd_new検出
run_awk() {
    awk '
        /^- /{block=""; read_state=""}
        /read:[[:space:]]*false/{read_state="unread"}
        /type:.*cmd_new/{if(read_state=="unread"){print 1; exit}}
        END{if(!NR) print 0}
    ' "$1" 2>/dev/null || echo 0
}

run_gate_clear_awk() {
    awk '
        /^- /{read_state=""; type_state=""}
        /read:[[:space:]]*false/{read_state="unread"}
        /type:.*gate_clear/{type_state="gate_clear"}
        read_state=="unread" && type_state=="gate_clear"{print 1; exit}
        END{if(!NR) print 0}
    ' "$1" 2>/dev/null || echo 0
}

@test "T-KN-001: 未読cmd_newを検出する" {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'YAML'
messages:
- content: 'cmd_2231を書いた。配備せよ。'
  from: 'shogun'
  id: 'msg_001'
  read: false
  timestamp: '2026-04-22T15:30:46'
  type: 'cmd_new'
YAML
    result=$(run_awk "$tmp")
    rm -f "$tmp"
    [ "$result" = "1" ]
}

@test "T-KN-002: 既読cmd_newは検出しない" {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'YAML'
messages:
- content: 'cmd_2231を書いた。配備せよ。'
  from: 'shogun'
  id: 'msg_001'
  read: true
  timestamp: '2026-04-22T15:30:46'
  type: 'cmd_new'
YAML
    result=$(run_awk "$tmp")
    rm -f "$tmp"
    [ "$result" != "1" ]
}

@test "T-KN-003: cmd_new以外の未読は検出しない" {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'YAML'
messages:
- content: 'レビュー結果'
  from: 'gunshi'
  id: 'msg_001'
  read: false
  timestamp: '2026-04-22T15:30:46'
  type: 'review_result'
YAML
    result=$(run_awk "$tmp")
    rm -f "$tmp"
    [ "$result" != "1" ]
}

@test "T-KN-004: 複数メッセージで未読cmd_newを検出する" {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'YAML'
messages:
- content: '既読メッセージ'
  from: 'gunshi'
  id: 'msg_001'
  read: true
  timestamp: '2026-04-22T14:00:00'
  type: 'review_result'
- content: 'cmd_2232を書いた。配備せよ。'
  from: 'shogun'
  id: 'msg_002'
  read: false
  timestamp: '2026-04-22T15:30:46'
  type: 'cmd_new'
YAML
    result=$(run_awk "$tmp")
    rm -f "$tmp"
    [ "$result" = "1" ]
}

@test "T-KN-005: 空ファイルでエラーにならない" {
    local tmp
    tmp="$(mktemp)"
    printf 'messages:\n' > "$tmp"
    result=$(run_awk "$tmp")
    rm -f "$tmp"
    [ "$result" != "1" ]
}

@test "T-GS-001: 軍師向け未読gate_clearを検出する" {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'YAML'
messages:
- content: 'cmd_2460 gate_result: CLEAR — /gate-sync スキルでgate結果同期せよ'
  from: 'system'
  id: 'msg_001'
  read: false
  timestamp: '2026-05-02T17:00:00'
  type: 'gate_clear'
YAML
    result=$(run_gate_clear_awk "$tmp")
    rm -f "$tmp"
    [ "$result" = "1" ]
}
