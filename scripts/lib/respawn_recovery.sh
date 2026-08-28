#!/usr/bin/env bash
# Persist exactly one recovery nudge for an active task after verified respawn.
respawn_recovery_launch_command() {
    local root="$1" launch="$2" executable args candidate resolved node_path
    local resolved_dir=""
    local variable_name variable_default variable_value
    [ -n "$launch" ] || {
        printf '%s\n' 'respawn_recovery_launch_command: empty launch command' >&2
        return 1
    }
    [[ "$launch" != *$'\n'* && "$launch" != *$'\r'* ]] || {
        printf '%s\n' 'respawn_recovery_launch_command: newline in launch command' >&2
        return 1
    }

    # Only the first whitespace-delimited word is resolved.  Do not eval the
    # command: the SSOT uses ${NAME:-default}, while launch arguments must be
    # inert data because the result is later passed to tmux as a shell string.
    read -r executable args <<< "$launch"
    [ -n "$executable" ] || {
        printf '%s\n' 'respawn_recovery_launch_command: executable is missing' >&2
        return 1
    }

    if [[ "$executable" == '${'*':-'*'}' ]]; then
        local variable_expression
        variable_expression="${executable#'${'}"
        variable_expression="${variable_expression%'}'}"
        variable_name="${variable_expression%%:-*}"
        variable_default="${variable_expression#*:-}"
        # Validate the captured name before indirect expansion. The caller
        # controls launch text, and an invalid name must become a resolver
        # failure rather than a shell "invalid variable name" diagnostic.
        [[ "$variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
            printf 'respawn_recovery_launch_command: invalid variable name: %s\n' "$variable_name" >&2
            return 1
        }
        if [[ -v "$variable_name" ]]; then
            variable_value="${!variable_name}"
        else
            variable_value=""
        fi
        candidate="${variable_value:-$variable_default}"
    else
        candidate="$executable"
    fi

    # Tilde expansion is explicit (rather than eval) so the existing Claude
    # ~/bin/claude contract remains valid.
    local tilde_char home_prefix
    printf -v tilde_char '\176'
    home_prefix="${tilde_char}/"
    if [ "$candidate" = "~" ]; then
        candidate="$HOME"
    elif [[ "$candidate" == "$home_prefix"* ]]; then
        candidate="$HOME/${candidate#"$home_prefix"}"
    fi

    # Validate before lookup so shell metacharacters cannot reach command -v
    # or the nvm glob below.  The launch command is later embedded in tmux.
    [[ "$candidate" =~ ^[[:alnum:]_./:=+@%~+-]+$ ]] || {
        printf 'respawn_recovery_launch_command: unsafe executable: %s\n' "$candidate" >&2
        return 1
    }

    local explicit_override=0
    [ -n "${variable_value:-}" ] && explicit_override=1
    # Callers outside cli_lookup may pass the profile's bare default (`codex`)
    # instead of its ${SHOGUN_CODEX_BIN:-codex} form. Keep the same SSOT
    # override priority in that path as well.
    if [ "$candidate" = "codex" ] && [ -z "${variable_value:-}" ] &&
        [ -n "${SHOGUN_CODEX_BIN:-}" ]; then
        candidate="$SHOGUN_CODEX_BIN"
        explicit_override=1
        [[ "$candidate" =~ ^[[:alnum:]_./:=+@%~+-]+$ ]] || {
            printf 'respawn_recovery_launch_command: unsafe executable: %s\n' "$candidate" >&2
            return 1
        }
    fi
    if [[ "$candidate" = /* ]]; then
        resolved="$candidate"
        resolved_dir="${candidate%/*}"
    else
        # command -v is deliberately used for PATH/relative lookup.  A shell
        # builtin/function or unresolved name is rejected unless it yields a
        # real absolute executable path.
        resolved=$(command -v "$candidate" 2>/dev/null || true)
        if [[ "$resolved" != /* ]]; then
            if [[ -n "$resolved" && -f "$resolved" && -x "$resolved" ]]; then
                resolved_dir="${resolved%/*}"
                resolved_dir=$(realpath -m -- "$resolved_dir" 2>/dev/null || true)
                resolved=$(realpath -e -- "$resolved" 2>/dev/null || true)
            else
                resolved=""
            fi
        elif [[ ! -f "$resolved" || ! -x "$resolved" ]]; then
            resolved=""
        else
            resolved_dir="${resolved%/*}"
            resolved=$(realpath -e -- "$resolved" 2>/dev/null || true)
        fi
    fi

    # The explicit override is authoritative. Falling through to another
    # executable when it is set would make a typo silently select a different
    # CLI. With the profile default (codex), resolve exactly one executable
    # from nvm when monitor's PATH does not include nvm.
    if [[ -z "$resolved" && "$explicit_override" -eq 0 && "$candidate" != */* ]]; then
        local nvm_root nvm_path
        local -a nvm_candidates=()
        nvm_root="$HOME/.nvm/versions/node"
        if [ -d "$nvm_root" ]; then
            shopt -s nullglob
            nvm_candidates=("$nvm_root"/*/bin/"$candidate")
            shopt -u nullglob
        fi
        if [ "${#nvm_candidates[@]}" -gt 1 ]; then
            printf 'respawn_recovery_launch_command: multiple nvm executables for %s: %s\n' \
                "$candidate" "${nvm_candidates[*]}" >&2
            return 1
        fi
        if [ "${#nvm_candidates[@]}" -eq 1 ]; then
            nvm_path="${nvm_candidates[0]}"
            [ -f "$nvm_path" ] || {
                printf 'respawn_recovery_launch_command: nvm executable is not a file: %s\n' "$nvm_path" >&2
                return 1
            }
            [ -x "$nvm_path" ] || {
                printf 'respawn_recovery_launch_command: nvm executable is not executable: %s\n' "$nvm_path" >&2
                return 1
            }
            resolved_dir="${nvm_path%/*}"
            resolved=$(realpath -e -- "$nvm_path" 2>/dev/null || true)
        else
            printf 'respawn_recovery_launch_command: nvm executable not found: %s\n' "$candidate" >&2
            return 1
        fi
    fi

    [[ "$resolved" = /* && -f "$resolved" && -x "$resolved" ]] || {
        printf 'respawn_recovery_launch_command: unresolved executable: %s\n' "$candidate" >&2
        return 1
    }

    # Reject shell syntax in arguments and in variable-derived executables.
    # Normal CLI flags/path characters remain supported; quotes, expansions,
    # redirects, separators and globbing cannot reach tmux.
    [[ ! "$args" =~ [^[:alnum:]_./:=+@%~[:space:]-] ]] || {
        printf 'respawn_recovery_launch_command: unsafe launch arguments: %s\n' "$args" >&2
        return 1
    }

    # realpath resolves the nvm `codex` shim to package/bin/codex.js. Keep the
    # directory from which the executable was selected so its sibling `node`
    # remains available to the /usr/bin/env node shebang.
    node_path="${RESPAWN_RECOVERY_NODE_PATH:-$resolved_dir}"
    [ -n "$node_path" ] || node_path="${resolved%/*}"
    [ -d "$node_path" ] || {
        printf 'respawn_recovery_launch_command: node path is not a directory: %s\n' "$node_path" >&2
        return 1
    }

    local quoted_node quoted_root quoted_executable
    printf -v quoted_node '%q' "$node_path"
    printf -v quoted_root '%q' "$root"
    printf -v quoted_executable '%q' "$resolved"
    # shellcheck disable=SC2016
    # $PATH must remain literal in the generated command.
    printf 'export PATH="%s:$PATH"; cd %s && exec %s' "$quoted_node" "$quoted_root" "$quoted_executable"
    [ -z "$args" ] || printf ' %s' "$args"
    printf '\n'
}

respawn_recovery_ready() {
    local pane="$1" capture ctx tmux_bin="${RESPAWN_RECOVERY_TMUX_BIN:-tmux}"
    [ "$($tmux_bin display-message -t "$pane" -p '#{pane_dead}' 2>/dev/null || echo 1)" = 0 ] || return 1
    capture=$($tmux_bin capture-pane -t "$pane" -p -J -S -100 2>/dev/null || true)
    printf '%s\n' "$capture" | grep -qE 'Claude Code|OpenAI Codex|Codex CLI|❯|›' || return 1
    respawn_recovery_generation "$pane" >/dev/null || return 1
    ctx=$(printf '%s\n' "$capture" | grep -oE '(CTX:[[:space:]]*|Context[[:space:]]+)[0-9]+%( used)?' | tail -1 | grep -oE '[0-9]+' || true)
    [ "$ctx" = 0 ] || return 1
}

# respawn-paneの成功直後はCLIバナー/CTX表示がまだ描画されていないことがある。
# 単発判定でその正常な起動窓をrespawn失敗へ誤変換せず、期限内だけ再確認する。
respawn_recovery_wait_ready() {
    local pane="$1"
    local attempts="${RESPAWN_RECOVERY_READY_ATTEMPTS:-10}"
    local delay="${RESPAWN_RECOVERY_READY_DELAY_SECONDS:-1}"
    local attempt

    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || attempts=10
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        respawn_recovery_ready "$pane" && return 0
        [ "$attempt" -lt "$attempts" ] && sleep "$delay"
    done
    return 1
}

respawn_recovery_generation() {
    local pane="$1" pid stat starttime
    local tmux_bin="${RESPAWN_RECOVERY_TMUX_BIN:-tmux}" proc_root="${RESPAWN_RECOVERY_PROC_ROOT:-/proc}"
    pid=$($tmux_bin display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null || true)
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ -r "$proc_root/$pid/stat" ] || return 1
    stat=$(<"$proc_root/$pid/stat")
    # comm (field 2) may contain spaces and parentheses; strip through its final ') '.
    stat=${stat##*) }
    starttime=$(printf '%s\n' "$stat" | awk '{print $20}')
    [[ "$starttime" =~ ^[0-9]+$ ]] || return 1
    printf '%s:%s\n' "$pid" "$starttime"
}

respawn_recovery_notify() {
    local root="$1" agent="$2" generation="$3" source="${4:-respawn}" content="${5:-}"
    local task_file="$root/queue/tasks/${agent}.yaml"
    local state_dir="${RESPAWN_RECOVERY_STATE_DIR:-$root/.cache/respawn-recovery}"
    local values status parent task_id marker
    [ -n "$generation" ] && [ "$generation" != "unknown" ] || return 1
    if [ -n "$content" ] && [[ "$content" =~ [\`\$\|\;\&\<\>] ]]; then content=""; fi
    if [ -f "$task_file" ]; then
      values=$(python3 - "$task_file" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
t = d.get("task", d) if isinstance(d, dict) else {}
print(t.get("status") or "")
print(t.get("parent_cmd") or "")
print(t.get("task_id") or "")
PY
      ) || return 1
    else
      values=$'\n\n'
    fi
    status=$(printf '%s\n' "$values" | sed -n '1p')
    parent=$(printf '%s\n' "$values" | sed -n '2p')
    task_id=$(printf '%s\n' "$values" | sed -n '3p')
    case "$status" in
      assigned|acknowledged|in_progress) [ -n "$parent" ] && [ -n "$task_id" ] || return 1 ;;
      *) [ -n "$content" ] || return 0; parent=""; task_id="" ;;
    esac
    mkdir -p "$state_dir"
    marker="$state_dir/${agent}.$(printf '%s' "$generation" | sha256sum | cut -d' ' -f1).sent"
    exec 219>"${marker}.lock"
    flock -w 5 219 || return 1
    [ ! -e "$marker" ] || return 0
    if [ -n "$parent" ]; then
      message="respawn復帰。既存taskを継続せよ。parent_cmd=${parent} task_id=${task_id} source=${source}"
      [ -z "$content" ] || message="${message} 補足: ${content}"
      sender=karo
    else
      message="$content"
      sender=ninja_monitor
    fi
    bash "$root/scripts/inbox_write.sh" "$agent" "$message" \
        recovery "$sender" continue_same_task || return 1
    : > "$marker"
}
