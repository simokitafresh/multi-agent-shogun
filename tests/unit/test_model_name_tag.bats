#!/usr/bin/env bats
# test_necessity: settings.yaml model_name is the single source of truth for tmux @model_name;
# respawn choke points must burn it in verbatim (no display-name conversion, no banner parsing),
# and each application must emit exactly one match/mismatch reconciliation log line. (cmd_4160)

setup() {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/lib" "$root/config" "$root/logs" "$root/fakebin"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/cli_lookup.sh" "$root/scripts/lib/"

  cat > "$root/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testagent:
      type: claude
      model_name: sonnet-5-high
    blankagent:
      type: claude
    codexagent:
      type: codex
    badtypeagent:
      type: bogus
YAML

  # fake tmux: only implements set-option / show-options against a flat state file
  state_file="$root/tmux_state.tsv"
  : > "$state_file"
  cat > "$root/fakebin/tmux" <<SH
#!/usr/bin/env bash
state_file="$state_file"
sub="\$1"; shift
target="" varname="" value="" have_value=0
case "\$sub" in
  set-option)
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        -p) shift ;;
        -t) target="\$2"; shift 2 ;;
        *)
          if [ -z "\$varname" ]; then varname="\$1"; shift
          elif [ "\$have_value" -eq 0 ]; then value="\$1"; have_value=1; shift
          else shift
          fi
          ;;
      esac
    done
    printf '%s\t%s\t%s\n' "\$target" "\$varname" "\$value" >> "\$state_file"
    ;;
  show-options)
    while [ "\$#" -gt 0 ]; do
      case "\$1" in
        -p) shift ;;
        -v) shift ;;
        -t) target="\$2"; shift 2 ;;
        *) varname="\$1"; shift ;;
      esac
    done
    awk -F'\t' -v t="\$target" -v v="\$varname" '\$1==t && \$2==v {val=\$3} END {print val}' "\$state_file"
    ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$root/fakebin/tmux"

  export PATH="$root/fakebin:$PATH"
  export CLI_ADAPTER_SETTINGS="$root/config/settings.yaml"
  export MODEL_NAME_TAG_LOG="$root/logs/model_name_tag_verify.log"
  export FAKE_TMUX_STATE="$state_file"
}

@test "settings.yaml model_name is burned into @model_name verbatim, unconverted" {
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; apply_model_name_tag testagent testpane' _ "$root"
  [ "$status" -eq 0 ]
  result=$(awk -F'\t' -v t="testpane" -v v="@model_name" '$1==t && $2==v {val=$3} END {print val}' "$FAKE_TMUX_STATE")
  [ "$result" = "sonnet-5-high" ]
}

@test "reconciliation log records a match line with raw settings value" {
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; apply_model_name_tag testagent testpane' _ "$root"
  [ "$status" -eq 0 ]
  [ -f "$MODEL_NAME_TAG_LOG" ]
  grep -q 'agent=testagent pane=testpane settings_model=sonnet-5-high tmux_model=sonnet-5-high result=match' "$MODEL_NAME_TAG_LOG"
}

@test "missing model_name fails closed without writing tmux or a match log line" {
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; apply_model_name_tag blankagent blankpane' _ "$root"
  [ "$status" -ne 0 ]
  result=$(awk -F'\t' -v t="blankpane" -v v="@model_name" '$1==t && $2==v {val=$3} END {print val}' "$FAKE_TMUX_STATE")
  [ -z "$result" ]
}

@test "apply_model_name_tag does not call display-name conversion or banner-parse functions" {
  repo="$BATS_TEST_DIRNAME/../.."
  run sed -n '/^apply_model_name_tag()/,/^}/p' "$repo/scripts/lib/cli_lookup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cli_model_display"* ]]
  [[ "$output" != *"detect_real_model"* ]]
  [[ "$output" == *"_cli_lookup_settings_get"* ]]
}

@test "all four choke points invoke apply_model_name_tag" {
  repo="$BATS_TEST_DIRNAME/../.."
  run grep -c 'apply_model_name_tag' "$repo/scripts/agent_respawn.sh"
  [ "$status" -eq 0 ]; [ "$output" -ge 1 ]

  run grep -c 'apply_model_name_tag' "$repo/scripts/switch_cli_mode.sh"
  [ "$status" -eq 0 ]; [ "$output" -ge 1 ]

  # ninja_monitor.sh: safe_send_clear(codex/claude) + CLI-DEAD respawn + CODEX-BYPASS respawn = 4 sites
  run grep -c 'apply_model_name_tag' "$repo/scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]; [ "$output" -ge 4 ]
}

@test "switch_cli_mode refresh_runtime_model_name no longer calls detect_real_model" {
  repo="$BATS_TEST_DIRNAME/../.."
  run bash -c "sed -n '/refresh_runtime_model_name()/,/^    }/p' '$repo/scripts/switch_cli_mode.sh' | grep -v '^[[:space:]]*#'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"detect_real_model"* ]]
  [[ "$output" == *"apply_model_name_tag"* ]]
}

@test "check_model_names prefers settings.yaml model_name over banner-parsed resolve_model_display" {
  repo="$BATS_TEST_DIRNAME/../.."
  run sed -n '/^check_model_names()/,/^}/p' "$repo/scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'expected=$(_cli_lookup_settings_get "$name" "model_name" "")'* ]]
}

# test_necessity(cmd_karo_hotfix_agent_respawn_cli_sync_202609031435根治): agent_respawn.sh's
# @agent_cli tag must reflect settings.yaml type (SSOT) after a successful respawn, not the
# pre-respawn `cli` variable — which cli_type() can resolve from the live pane's
# pane_current_command (the CLI process about to be replaced) when settings.type has just changed.
# A tag written from the stale variable would leave watchers (health_check.sh, daemon_watchdog.sh,
# inbox_watcher.sh) routing to the wrong CLI after a claude<->codex switch.

@test "agent_respawn @agent_cli sync reads settings.type directly, ignoring a stale pre-respawn cli variable" {
  repo="$BATS_TEST_DIRNAME/../.."
  snippet="$root/agent_cli_sync_snippet.sh"
  sed -n '/^respawn_settings_cli=/,/^# LS078根治/p' "$repo/scripts/agent_respawn.sh" | sed '$d' > "$snippet"
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; agent_name="codexagent"; pane="codexpane"; cli="claude"; source "$2"' _ "$root" "$snippet"
  [ "$status" -eq 0 ]
  result=$(awk -F'\t' -v t="codexpane" -v v="@agent_cli" '$1==t && $2==v {val=$3} END {print val}' "$FAKE_TMUX_STATE")
  [ "$result" = "codex" ]
}

@test "agent_respawn @agent_cli sync writes claude when settings.type is claude" {
  repo="$BATS_TEST_DIRNAME/../.."
  snippet="$root/agent_cli_sync_snippet.sh"
  sed -n '/^respawn_settings_cli=/,/^# LS078根治/p' "$repo/scripts/agent_respawn.sh" | sed '$d' > "$snippet"
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; agent_name="testagent"; pane="testpane2"; cli="codex"; source "$2"' _ "$root" "$snippet"
  [ "$status" -eq 0 ]
  result=$(awk -F'\t' -v t="testpane2" -v v="@agent_cli" '$1==t && $2==v {val=$3} END {print val}' "$FAKE_TMUX_STATE")
  [ "$result" = "claude" ]
}

@test "agent_respawn @agent_cli sync falls back to claude for an unrecognized settings.type value" {
  repo="$BATS_TEST_DIRNAME/../.."
  snippet="$root/agent_cli_sync_snippet.sh"
  sed -n '/^respawn_settings_cli=/,/^# LS078根治/p' "$repo/scripts/agent_respawn.sh" | sed '$d' > "$snippet"
  run bash -c 'source "$1/scripts/lib/cli_lookup.sh"; agent_name="badtypeagent"; pane="badpane"; cli="codex"; source "$2"' _ "$root" "$snippet"
  [ "$status" -eq 0 ]
  result=$(awk -F'\t' -v t="badpane" -v v="@agent_cli" '$1==t && $2==v {val=$3} END {print val}' "$FAKE_TMUX_STATE")
  [ "$result" = "claude" ]
}

@test "agent_respawn.sh derives @agent_cli from settings.type via _cli_lookup_settings_get, not the live-detected cli variable" {
  repo="$BATS_TEST_DIRNAME/../.."
  run sed -n '/^respawn_settings_cli=/,/^# LS078根治/p' "$repo/scripts/agent_respawn.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'_cli_lookup_settings_get "$agent_name" "type"'* ]]
  [[ "$output" != *'@agent_cli "$cli"'* ]]
}
