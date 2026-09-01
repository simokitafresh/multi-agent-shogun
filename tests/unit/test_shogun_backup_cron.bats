#!/usr/bin/env bats

# test_necessity: backup cron must carry a deterministic isolated PATH whose
# first entry resolves the gws Node shebang, while preserving exact
# SHOGUN_GWS_BIN selection and shell-safe quoting.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/shogun_backup.py"
    WORK="$BATS_TEST_TMPDIR/work"
    ROOT="$WORK/root"
    GWS_DIR="$WORK/gws dir"
    BIN="$WORK/bin"
    KEY="$WORK/backup.key"
    CRONTAB_CAPTURE="$WORK/crontab"
    export CRONTAB_CAPTURE
    mkdir -p "$ROOT/logs" "$GWS_DIR" "$BIN" "$WORK/dm"
    mkdir -p "$ROOT/scripts"
    cp "$SCRIPT" "$ROOT/scripts/shogun_backup.py"
    printf 'key\n' > "$KEY"

    # The fake gws has the production launcher shape.  The sibling node is
    # enough to prove /usr/bin/env resolves the shebang from the injected PATH.
    printf '#!/usr/bin/env node\n' > "$GWS_DIR/gws"
    printf '#!/bin/sh\nprintf node-resolved\n' > "$GWS_DIR/node"
    chmod +x "$GWS_DIR/gws" "$GWS_DIR/node"

    cat > "$BIN/crontab" <<'EOF'
#!/bin/sh
if [ "$1" = "-l" ]; then
    printf '%s\n' '# existing cron' '# stale # shogun-drive-backup'
    exit 0
fi
if [ "$1" = "-" ]; then
    cat > "$CRONTAB_CAPTURE"
    exit 0
fi
exit 2
EOF
    chmod +x "$BIN/crontab"
}

install_cron() {
    run env PATH="$BIN:/usr/bin:/bin" SHOGUN_GWS_BIN="$1" \
        python3 "$SCRIPT" --install-cron --root "$ROOT" --dm-root "$WORK/dm" \
        --key-file "$KEY" --drive-folder 'folder with spaces'
}

@test "install-cron injects parent-first PATH and quotes a spaced gws path" {
    install_cron "$GWS_DIR/gws"
    [ "$status" -eq 0 ]
    line="$(grep 'shogun-drive-backup$' "$CRONTAB_CAPTURE")"
    [ "$(grep -c 'shogun-drive-backup$' "$CRONTAB_CAPTURE")" -eq 1 ]
    [[ "$line" == *"PATH='$GWS_DIR:/usr/bin:/bin' SHOGUN_GWS_BIN='$GWS_DIR/gws'"* ]]
    [[ "$line" == *"--drive-folder 'folder with spaces'"* ]]
}

@test "generated command succeeds under an empty cron-like environment" {
    install_cron "$GWS_DIR/gws"
    [ "$status" -eq 0 ]
    line="$(grep 'shogun-drive-backup$' "$CRONTAB_CAPTURE")"
    command="${line#0 3 * * * }"
    command="${command% # shogun-drive-backup}"
    command="${command/--backup/--backup --dry-run}"
    run env -i PATH=/usr/bin:/bin bash -c "$command"
    [ "$status" -eq 0 ]
    grep -Fq '"dry_run": true' "$ROOT/logs/shogun_backup.log"

    run /usr/bin/env -i PATH="$GWS_DIR:/usr/bin:/bin" "$GWS_DIR/gws"
    [ "$status" -eq 0 ]
    [ "$output" = "node-resolved" ]
}

@test "empty and relative SHOGUN_GWS_BIN resolve through PATH" {
    cp "$GWS_DIR/gws" "$BIN/gws"
    chmod +x "$BIN/gws"

    install_cron ""
    [ "$status" -eq 0 ]
    line="$(grep 'shogun-drive-backup$' "$CRONTAB_CAPTURE")"
    [[ "$line" == *"PATH=$BIN:/usr/bin:/bin SHOGUN_GWS_BIN=$BIN/gws"* ]]

    install_cron "gws"
    [ "$status" -eq 0 ]
    line="$(grep 'shogun-drive-backup$' "$CRONTAB_CAPTURE")"
    [[ "$line" == *"PATH=$BIN:/usr/bin:/bin SHOGUN_GWS_BIN=$BIN/gws"* ]]
}
