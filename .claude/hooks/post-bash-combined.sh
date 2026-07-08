#!/usr/bin/env bash
# Combined Bash PostToolUse guard: test_result_guard + commit-reminder
# cmd_1661: 2 hooks → 1 script. Eliminates 1 bash startup cost (~60ms).
set -eu

if [ -n "${HOOK_PAYLOAD+x}" ]; then
    payload="$HOOK_PAYLOAD"
else
    payload="$(cat 2>/dev/null || true)"
fi
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Bash"'* ]] && exit 0

mark_post_bash_numeric_gist_flag() {
    [[ "$payload" == *'gh gist edit'* ]] || return 0
    [[ "$payload" =~ [0-9][0-9,]*([.][0-9]+)?[[:space:]]*(件|体|個|名|枚|冊|台|本|通|種|パターン|%|％|円|万円|億|兆|倍|秒|分|時間|日|ヶ月|年) ]] || return 0
    local agent_id state_dir
    agent_id="${TMUX_AGENT_ID:-}"
    if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
        agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    [[ "$agent_id" == "shogun" ]] || return 0
    state_dir="${SHOGUN_STATE_DIR:-/tmp}"
    mkdir -p "$state_dir" 2>/dev/null || true
    : > "$state_dir/shogun_numeric_tool_output_${agent_id}" 2>/dev/null || true
}

mark_post_bash_numeric_gist_flag

mark_post_bash_verification_action_count() {
    local command agent_id state_dir count_file
    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null || true)"
    [[ -n "$command" ]] || return 0
    agent_id="${TMUX_AGENT_ID:-}"
    if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
        agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    [[ "$agent_id" == "shogun" ]] || return 0
    if [[ "$command" =~ (^|[[:space:]/])(memory_db_query|semantic_search)\.sh([[:space:]]|$) ]] \
        || [[ "$command" =~ (^|[[:space:]/])(rg|grep|bats|db-check)([[:space:]]|$) ]] \
        || [[ "$command" =~ tmux[[:space:]].*capture-pane ]]; then
        state_dir="${SHOGUN_STATE_DIR:-/tmp}"
        mkdir -p "$state_dir" 2>/dev/null || true
        count_file="$state_dir/shogun_verification_action_count_${agent_id}"
        printf '1\n' >> "$count_file" 2>/dev/null || true
    fi
}

mark_post_bash_verification_action_count

# === Guard 0: cmd_save.sh BLOCK reminder ===
if [[ "$payload" == *'cmd_save.sh'* || "$payload" == *'cmd_publish.sh'* ]]; then
    cmd_save_meta="$(PAYLOAD="$payload" jq -r '
        def walk_objects:
            .. | objects;
        def text_values:
            [
                .tool_result?,
                .toolUseResult?,
                .tool_response?,
                .toolResponse?,
                .result?,
                .output?,
                .stdout?,
                .stderr?
            ]
            | map(select(. != null))
            | [ .[] | .. | strings ]
            | join("\n");
        [
            (.tool_input.command // .toolInput.command // ""),
            ([
                walk_objects
                | (.exit_code? // .exitCode?)
                | select(type == "number" or type == "string")
                | tostring
            ] | first // ""),
            text_values
        ] | @tsv
    ' 2>/dev/null <<< "$payload" || true)"
    cmd_save_command="${cmd_save_meta%%$'\t'*}"
    cmd_save_rest=""
    if [[ "$cmd_save_meta" == *$'\t'* ]]; then
        cmd_save_rest="${cmd_save_meta#*$'\t'}"
    fi
    cmd_save_exit="${cmd_save_rest%%$'\t'*}"
    cmd_save_output=""
    if [[ "$cmd_save_rest" == *$'\t'* ]]; then
        cmd_save_output="${cmd_save_rest#*$'\t'}"
    fi

    cmd_save_block_detected=0
    if [[ "$cmd_save_exit" == "1" ]]; then
        cmd_save_block_detected=1
    elif [[ "$cmd_save_output" == *'BLOCK:'* && ( "$cmd_save_output" == *'cmd_save.sh'* || "$cmd_save_command" == *'cmd_publish.sh'* || "$cmd_save_command" == *'cmd_save.sh'* ) ]]; then
        cmd_save_block_detected=1
    fi

    if [[ ( "$cmd_save_command" == *'cmd_save.sh'* || "$cmd_save_command" == *'cmd_publish.sh'* ) && "$cmd_save_block_detected" == "1" ]]; then
        # BLOCK理由をpayloadから抽出(stderr/content内の"BLOCK:"行)
        block_lines="$(jq -r '
            [.. | strings] | join("\n")
        ' 2>/dev/null <<< "$payload" | grep -E '^BLOCK:|^  [0-9]+\.' | head -10 || true)"
        msg=$'★★★ cmd_save.sh BLOCK — 止まるな、全件修正して再実行せよ ★★★\n'
        if [[ -n "$block_lines" ]]; then
            msg+=$'\n'"$block_lines"$'\n'
        fi
        msg+=$'\n即修正→ bash scripts/cmd_save.sh <cmd_id> 再実行。PASSまで回せ。止まるな。'
        printf '%s' "$msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
        exit 0
    fi
fi

# === Guard 1: test_result_guard ===
if [[ "$payload" == *'pytest'* || "$payload" == *'bats'* || "$payload" == *'jest'* || \
      "$payload" == *'npm test'* || "$payload" == *'pnpm test'* || "$payload" == *'yarn test'* || \
      "$payload" == *'bun test'* || "$payload" == *'py.test'* ]]; then
    # cmd_2075: fail/skip事前チェック — fail/skip文字列なし → python3不要 (35ms → ~5ms)
    # 前回revertとの差: サブシェル維持 / python3到達頻度を削減
    if [[ "$payload" != *' failed'* && "$payload" != *'FAILED'* && \
          "$payload" != *'failures'* && "$payload" != *' skipped'* && \
          "$payload" != *'SKIP'* && "$payload" != *'not ok'* && \
          "$payload" != *'ERROR'* && "$payload" != *'# skip'* ]]; then
        : # テスト全PASS確認済み。python3不要
    else
    # Delegate to existing python3 logic for complex test output parsing
    HOOK_PAYLOAD="$payload" python3 - <<'PYTEST'
import json
import os
import re
import shlex
import sys


def load_payload(raw: str):
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def split_segments(command: str):
    return [segment.strip() for segment in re.split(r"(?:&&|\|\||;|\|)", command) if segment.strip()]


def is_test_command(command: str) -> bool:
    if not isinstance(command, str) or not command.strip():
        return False
    for segment in split_segments(command):
        try:
            tokens = shlex.split(segment, posix=True)
        except ValueError:
            continue
        if not tokens:
            continue
        cmd0 = os.path.basename(tokens[0])
        if cmd0 in {"pytest", "py.test", "bats", "jest"}:
            return True
        if cmd0 in {"python", "python3"} and len(tokens) >= 3 and tokens[1] == "-m" and tokens[2] == "pytest":
            return True
        if cmd0 == "npx" and len(tokens) >= 2 and tokens[1] == "jest":
            return True
        if cmd0 in {"npm", "pnpm", "yarn", "bun"} and len(tokens) >= 2 and tokens[1] == "test":
            return True
    return False


def collect_text(value):
    parts = []
    def walk(node):
        if isinstance(node, str):
            if node.strip(): parts.append(node)
            return
        if isinstance(node, list):
            for item in node: walk(item)
            return
        if isinstance(node, dict):
            for item in node.values(): walk(item)
    walk(value)
    return "\n".join(parts)


def extract_output_text(data: dict) -> str:
    candidates = []
    for key in ("tool_result", "toolUseResult", "tool_output", "toolOutput",
                "tool_response", "result", "output", "stdout", "stderr"):
        if key in data:
            candidates.append(collect_text(data.get(key)))
    text = "\n".join(part for part in candidates if part.strip())
    if text.strip():
        return text
    transcript_path = data.get("transcript_path") or data.get("transcriptPath") or ""
    if not isinstance(transcript_path, str) or not transcript_path:
        return ""
    try:
        with open(transcript_path, "r", encoding="utf-8") as fh:
            tail = fh.readlines()[-200:]
    except Exception:
        return ""
    return "".join(tail)


def _filter_tap_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not re.match(r"\s*(?:ok|not ok)\b", line)
        and not re.match(r"\s*[✓✗]", line)
    )


def parse_skip_count(text: str) -> int:
    non_tap_text = _filter_tap_lines(text)
    matches = []
    for pat in (r"(\d+)\s+(?:tests?\s+)?skipped\b", r"(\d+)\s+(?:tests?\s+)?skips?\b",
                r"skipped:\s*(\d+)\b", r"skips?:\s*(\d+)\b"):
        for m in re.finditer(pat, non_tap_text, flags=re.IGNORECASE | re.MULTILINE):
            try: matches.append(int(m.group(1)))
            except Exception: pass
    bats_skips = len(re.findall(r"(?im)^\s*(?:ok|not ok)\s+\d+\b.*#\s*skip\b", text))
    if bats_skips: matches.append(bats_skips)
    if matches: return max(matches)
    if re.search(r"(?m)(?:^\s*SKIP(?:PED)?\b|\bSKIP(?:PED)?\s*$)", non_tap_text): return 1
    return 0


def parse_fail_count(text: str) -> int:
    # cmd_3271: parse_skip_countと同様にTAP行(ok/not ok)を除外してからregex検索。
    # 除外しないと「ok 265 failed AC count command...」等のテスト名が誤マッチする。
    non_tap_text = _filter_tap_lines(text)
    matches = []
    for pat in (r"(\d+)\s+(?:tests?\s+)?failed\b", r"(\d+)\s+(?:test suites?\s+)?failed\b",
                r"(\d+)\s+failures?\b", r"failed:\s*(\d+)\b", r"failures?:\s*(\d+)\b"):
        for m in re.finditer(pat, non_tap_text, flags=re.IGNORECASE | re.MULTILINE):
            try: matches.append(int(m.group(1)))
            except Exception: pass
    bats_fails = len(re.findall(r"(?im)^\s*not ok\b(?!.*#\s*skip\b)", text))
    if bats_fails: matches.append(bats_fails)
    if matches: return max(matches)
    if re.search(r"(?im)^\s*FAIL(?:ED)?\b", non_tap_text) or re.search(r"\bFAILED\b", non_tap_text): return 1
    return 0


data = load_payload(os.environ.get("HOOK_PAYLOAD", ""))
tool_name = data.get("tool_name") or data.get("toolName") or ""
if tool_name != "Bash": raise SystemExit(0)
tool_input = data.get("tool_input") or data.get("toolInput") or {}
command = ""
if isinstance(tool_input, dict):
    raw_command = tool_input.get("command") or tool_input.get("cmd") or ""
    if isinstance(raw_command, str): command = raw_command
if not is_test_command(command): raise SystemExit(0)
output_text = extract_output_text(data)
if not output_text.strip(): raise SystemExit(0)
skip_count = parse_skip_count(output_text)
fail_count = parse_fail_count(output_text)
messages = []
if skip_count > 0:
    messages.append(f"ERROR: {skip_count} test(s) SKIPPED.\nWHY: SKIP=FAIL rule (CLAUDE.md). Skipped tests are treated as failures.\nFIX: 1) Check why tests are skipped. 2) Fix the skip condition or the test. 3) Re-run to confirm 0 skips.")
if fail_count > 0:
    messages.append(f"ERROR: {fail_count} test(s) FAILED.\nWHY: All tests must pass before proceeding.\nFIX: 1) Read the failure output above. 2) Fix the failing code or test. 3) Re-run to confirm all pass.")
if messages:
    payload_out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n".join(messages)}}
    print(json.dumps(payload_out, ensure_ascii=False, separators=(",", ":")))
PYTEST
    fi  # close inner fail/skip check
fi  # close Guard 1

# === Guard 2: commit-reminder ===
if [[ "$payload" == *'inbox_write'* && "$payload" == *'report_received'* ]]; then
    _post_bash_self="${BASH_SOURCE[0]}"
    [[ "$_post_bash_self" != /* ]] && _post_bash_self="$PWD/$_post_bash_self"
    SCRIPT_DIR="${_post_bash_self%/.claude/hooks/post-bash-combined.sh}"
    unset _post_bash_self

    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    if [[ -n "$command" && "$command" == *'inbox_write'* && "$command" == *'report_received'* ]]; then
        ninja_name=""
        if [[ "$command" =~ report_received[[:space:]]+([a-z_]+) ]]; then
            ninja_name="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$ninja_name" ]]; then
            task_path="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
            if [[ -f "$task_path" ]]; then
                project="$(awk '
                    /^task:[[:space:]]*$/ { in_task=1; next }
                    in_task && /^[^[:space:]]/ { exit }
                    in_task && /^[[:space:]]+project:[[:space:]]*/ {
                        sub(/^[[:space:]]+project:[[:space:]]*/, "")
                        gsub(/^["'\''"]|["'\''"]$/, "")
                        print
                        exit
                    }
                ' "$task_path" 2>/dev/null || true)"

                if [[ -n "$project" ]]; then
                    projects_path="$SCRIPT_DIR/config/projects.yaml"
                    project_path="$(awk -v target="$project" '
                        /^projects:[[:space:]]*$/ { in_projects=1; next }
                        in_projects && /^[^[:space:]]/ { exit }
                        in_projects && /^[[:space:]]+-[[:space:]]id:[[:space:]]*/ {
                            current=$0
                            sub(/^[[:space:]]+-[[:space:]]id:[[:space:]]*/, "", current)
                            gsub(/^["'\''"]|["'\''"]$/, "", current)
                            next
                        }
                        in_projects && current == target && /^[[:space:]]+path:[[:space:]]*/ {
                            sub(/^[[:space:]]+path:[[:space:]]*/, "")
                            gsub(/^["'\''"]|["'\''"]$/, "")
                            print
                            exit
                        }
                    ' "$projects_path" 2>/dev/null || true)"

                    if [[ -n "$project_path" && -d "$project_path" ]]; then
                        status_output="$(git -C "$project_path" status --porcelain --untracked-files=no 2>/dev/null || true)"
                        filtered_files="$(printf '%s\n' "$status_output" | awk '
                            length($0) >= 4 {
                                path=substr($0,4)
                                if (path ~ /^logs\// || path ~ /^queue\// || path ~ /^node_modules\// || path ~ /^\.next\// || path ~ /^__pycache__\//) next
                                if (path ~ /\.(log|pyc)$/) next
                                print path
                            }
                        ' | sort -u)"

                        if [[ -n "$filtered_files" ]]; then
                            msg=$'\n'"⚠ COMMIT MISSING 警告 ⚠"$'\n'"プロジェクト ${project} (${project_path}) にuncommitted変更あり:"$'\n'
                            count=0
                            while IFS= read -r f; do
                                [[ -n "$f" ]] || continue
                                count=$((count + 1))
                                if (( count <= 10 )); then
                                    msg+="  - ${f}"$'\n'
                                fi
                            done <<< "$filtered_files"
                            if (( count > 10 )); then
                                msg+="  ... +$((count - 10)) files"$'\n'
                            fi
                            msg+=$'\n'"報告を提出する前に、自分の任務scope内ファイルだけをcommitせよ:"$'\n'"  cd ${project_path} && git add <scope内file...> && git commit -m 'feat: <cmd_id> <summary>'"$'\n'$'\n'"scope外/他忍者担当の変更はstageせず、家老へ報告せよ。commit漏れはcmd_complete_gateでBLOCKされ家老の手動対応(WA)が発生する。"
                            printf '%s' "$msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
                        fi
                    fi
                fi
            fi
        fi
    fi
fi

# === Guard 3: halt/clear送信後の停止検証(BLOCK) + inbox_write後確認強制 ===
# 送信は確認ではない。結果を確認せよ(LK013: 2026-05-20全失敗の根因)
# Phase 1: halt/clear送信検出→CTX記録。Phase 2: 次のBash実行時にCTX低下を検証→未低下ならBLOCK
_HALT_PENDING_DIR="/tmp/shogun_halt_pending"

# Phase 2: 前回のhalt/clear送信の停止確認(次のBashアクション時に発火)
_halt_pending_files=()
if [[ -d "$_HALT_PENDING_DIR" ]]; then
    shopt -s nullglob
    _halt_pending_files=("$_HALT_PENDING_DIR"/*.pending)
    shopt -u nullglob
fi
for _hf in "${_halt_pending_files[@]}"; do
    [[ -f "$_hf" ]] || continue
    _halt_ninja="$(basename "$_hf" .pending)"
    _old_ctx="$(cat "$_hf" 2>/dev/null || echo "")"
    # 対象忍者のpaneを取得してCTX確認
    _halt_pane="$(tmux list-panes -t shogun:agents -F 'shogun:agents.#{pane_index}' -f "#{==:#{@agent_id},$_halt_ninja}" 2>/dev/null | head -1 || true)"
    _new_ctx=""
    if [[ -n "$_halt_pane" ]]; then
        _new_ctx="$(tmux capture-pane -t "$_halt_pane" -p -S -30 2>/dev/null | grep -oP 'CTX:\d+%' | tail -1 || true)"
    fi
    if [[ -n "$_old_ctx" && -n "$_new_ctx" && "$_old_ctx" == "$_new_ctx" && "$_new_ctx" != "CTX:0%" ]]; then
        # CTX変化なし+0%でない → 停止未確認 → BLOCK
        printf '%s' "BLOCK: ${_halt_ninja}にhalt/clearを送信したがCTX未変化(${_old_ctx}→${_new_ctx})。停止していない。capture-pane -S -30で全体を確認し、停止を実証してからpendingファイルを削除せよ: rm ${_hf}" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
        exit 2
    fi
    # CTX低下 or 0% → 停止確認OK → pendingクリア
    rm -f "$_hf" 2>/dev/null
done

# Phase 1: halt/clear送信検出→CTX記録
if [[ "$payload" == *'inbox_write'* ]]; then
    _iw_cmd="$(jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null <<< "$payload" || true)"
    # Fix(2026-05-21): heredoc/文字列内のinbox_writeにマッチ防止。bash第1引数チェック
    _iw_verb="${_iw_cmd%%[[:space:]]*}"
    _iw_arg1_raw="${_iw_cmd#*[[:space:]]}"
    _iw_arg1="${_iw_arg1_raw%%[[:space:]]*}"
    _iw_arg1="${_iw_arg1//\"/}"
    if [[ "$_iw_verb" == "bash" && "$_iw_arg1" == *'inbox_write.sh'* ]]; then
        _iw_target="$(echo "$_iw_cmd" | grep -oP 'inbox_write\.sh\s+\K\S+' || true)"
        _iw_type="$(echo "$_iw_cmd" | grep -oP '(task_halt|clear_command)' || true)"
        if [[ -n "$_iw_target" && -n "$_iw_type" ]]; then
            mkdir -p "$_HALT_PENDING_DIR" 2>/dev/null || true
            # halt/clear送信先のCTXを記録
            _target_pane="$(tmux list-panes -t shogun:agents -F 'shogun:agents.#{pane_index}' -f "#{==:#{@agent_id},$_iw_target}" 2>/dev/null | head -1 || true)"
            _target_ctx=""
            if [[ -n "$_target_pane" ]]; then
                _target_ctx="$(tmux capture-pane -t "$_target_pane" -p -S -30 2>/dev/null | grep -oP 'CTX:\d+%' | tail -1 || true)"
            fi
            echo "$_target_ctx" > "$_HALT_PENDING_DIR/${_iw_target}.pending" 2>/dev/null || true
            printf '%s' "★halt/clear送信: ${_iw_target}(${_target_ctx})。次のBash実行時にCTX低下を自動検証する。停止未確認ならBLOCK。" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
            exit 0
        fi
        # 通常のinbox_write(halt/clear以外)
        if [[ -n "$_iw_target" && "$_iw_target" != "karo" && "$_iw_target" != "shogun" && "$_iw_target" != "gunshi" ]]; then
            printf '%s' "★確認必須: ${_iw_target}のpaneをcapture-pane -S -30で確認し、nudgeが到達したか・作業を開始したかを目視確認せよ。送信≠確認。" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
            exit 0
        fi
    fi
fi

# === Guard 4: deploy_task.sh completion verification ===
# deploy_task.sh実行後に「deployment complete」が出力に含まれるか検証
# 含まれなければnudge未送信→配備不完全の警告(LK-A02 v7: 2026-05-17事故)
# Fix(なぜなぜ7回 2026-05-21): payload substring matchだとgrep/diff/gitでも発火(偽陽性)
# 根因1: `sh`がパス内マッチ。根因2: verb=bash+引数内文字列マッチ(inbox_write msg内のdeploy_task.sh)
# → bashの第1引数(スクリプトパス)がdeploy_task.shを含むかで判定
if [[ "$payload" == *'deploy_task.sh'* ]]; then
    _g4_cmd="$(jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null <<< "$payload" || true)"
    _g4_verb="${_g4_cmd%%[[:space:]]*}"
    _g4_rest="${_g4_cmd#*[[:space:]]}"
    _g4_arg1="${_g4_rest%%[[:space:]]*}"
    _g4_arg1="${_g4_arg1//\"/}"
fi
if [[ "${_g4_verb:-}" == "bash" && "${_g4_arg1:-}" == *deploy_task.sh* ]]; then
    _deploy_output="$(PAYLOAD="$payload" jq -r '
        (.tool_result.stdout // .toolResult.stdout // .content // "") | tostring
    ' 2>/dev/null <<< "$payload" || true)"
    if [[ -n "$_deploy_output" ]] && [[ "$_deploy_output" != *"deployment complete"* ]]; then
        _warn_msg="⚠ deploy_task.sh出力に'deployment complete'が見つからない。nudge未送信の可能性。出力全文を確認し、必要なら手動nudge(inbox_write.sh)を送信せよ"
        printf '%s' "$_warn_msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
    else
        # deployment complete でもnudge到達は別問題。pane確認を強制
        _deploy_target="$(jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null <<< "$payload" | grep -oP 'deploy_task\.sh\s+\K\S+' || true)"
        if [[ -n "$_deploy_target" ]]; then
            printf '%s' "★確認必須: ${_deploy_target}のpaneをcapture-pane -S -30で確認し、nudgeが到達し作業を開始したか目視確認せよ。deploy完了≠nudge到達。" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
        fi
    fi
fi

# === Guard 5: LS-A16 fullrecalculate後parity確認リマインド (本番パリティ必須) ===
# admin/recalculate-sync実行を検知したら即parity確認を促す。事後BLOCKでなく事前検出層
# (post-bash-commit-reminder.shと同じ「事前WARN、事後BLOCKはcmd_complete_gate側」の二段構え)。
# cmd_1770三重事故(DB登録→パリティ未確認→コード未デプロイ+偽signal)の再発防止。
if [[ "$payload" == *'recalculate-sync'* ]]; then
    _g5_cmd="$(jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null <<< "$payload" || true)"
    _g5_verb="${_g5_cmd%%[[:space:]]*}"
    _g5_verb="${_g5_verb//\"/}"
    if [[ "$_g5_verb" == "curl" && "$_g5_cmd" == *'recalculate-sync'* ]]; then
        _g5_msg=$'\n⚠ 本番パリティ必須: fullrecalculate実行を検知した。\n即座にparity_check.sh（またはgate_recalculate_completeness.sh）でholding_signal+monthly_returnの完全一致を確認せよ。「あとでまとめて確認」は禁止。\n3レイヤー貫通(DB+API+FE)も忘れるな → skills/pf-registration/SKILL.md Phase 3 Step 6'
        printf '%s' "$_g5_msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
    fi
fi

exit 0
