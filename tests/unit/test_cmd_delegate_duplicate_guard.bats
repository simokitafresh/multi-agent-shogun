#!/usr/bin/env bats
# test_necessity: cmd_delegate重複ガードの不変量「言及≠委任」を守る。
# cmd_new本文の委任主語(blockの最初のcmd_トークン)のみが委任済み判定の根拠であり、
# 別cmd委任文中の説明的言及では委任済み扱いにならないこと(2026-08-22 cmd_4368 FP根治)。

setup() {
    PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GUARD_WRAPPER="$BATS_TEST_TMPDIR/guard.sh"
    start=$(grep -n "awk -v cmd_id=" "$PROJECT_DIR/scripts/cmd_delegate.sh" | head -1 | cut -d: -f1)
    end=$(awk -v s="$start" "NR>s && /^'/ {print NR; exit}" "$PROJECT_DIR/scripts/cmd_delegate.sh")
    {
        echo '#!/bin/bash'
        echo 'inbox_file="$1"; cmd_id="$2"'
        sed -n "${start},${end}p" "$PROJECT_DIR/scripts/cmd_delegate.sh"
    } > "$GUARD_WRAPPER"
    INBOX="$BATS_TEST_TMPDIR/karo_inbox.yaml"
    cat > "$INBOX" <<'EOF'
messages:
- content: 'cmd_4367(Track A単独)を書いた。配備せよ。Track B(cmd_4368)は後で起票する。'
  from: 'shogun'
  id: 'msg_1'
  type: 'cmd_new'
- content: 'cmd_4300を書いた。配備せよ。'
  from: 'shogun'
  id: 'msg_2'
  type: 'bulletin_notify'
EOF
}

@test "委任主語cmd_4367は委任済みとして検知される" {
    run bash "$GUARD_WRAPPER" "$INBOX" cmd_4367
    [ "$status" -eq 0 ]
}

@test "説明的言及のみのcmd_4368は委任済み扱いされない(FP根治)" {
    run bash "$GUARD_WRAPPER" "$INBOX" cmd_4368
    [ "$status" -ne 0 ]
}

@test "type=cmd_new以外のメッセージ主語cmd_4300は委任済み扱いされない" {
    run bash "$GUARD_WRAPPER" "$INBOX" cmd_4300
    [ "$status" -ne 0 ]
}

@test "どこにも現れないcmd_9999は委任済み扱いされない" {
    run bash "$GUARD_WRAPPER" "$INBOX" cmd_9999
    [ "$status" -ne 0 ]
}
