#!/usr/bin/env bash
# @source: cmd_452 (UserPromptSubmit snapshot注入hook)
set -eu

_prompt_state_self="${BASH_SOURCE[0]}"
[[ "$_prompt_state_self" != /* ]] && _prompt_state_self="$PWD/$_prompt_state_self"
SCRIPT_DIR="${_prompt_state_self%/scripts/hooks/prompt_state_inject.sh}"
unset _prompt_state_self

_prompt_state_overhead_source="prompt_state_inject"
_prompt_state_overhead_start_epoch="${EPOCHREALTIME/./}"
_prompt_state_overhead_start_ms="${_prompt_state_overhead_start_epoch:0:13}"
_prompt_state_overhead_event_id="${_prompt_state_overhead_source}-$$-${RANDOM}-${EPOCHREALTIME//./}"
if [[ -f "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh" ]]; then
  # shellcheck source=/dev/null
  _prompt_state_overhead_path="${PATH:-}"
  PATH="${PATH:-}:/usr/bin:/bin" source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
  PATH="$_prompt_state_overhead_path"
  unset _prompt_state_overhead_path
else
  defense_overhead_write_async() { :; }
fi
_prompt_state_overhead_emit() {
  local _prompt_state_overhead_rc="$1"
  local _prompt_state_overhead_end_epoch="${EPOCHREALTIME/./}"
  local _prompt_state_overhead_end_ms="${_prompt_state_overhead_end_epoch:0:13}"
  local _prompt_state_overhead_wall_ms=$((_prompt_state_overhead_end_ms - _prompt_state_overhead_start_ms))
  local _prompt_state_overhead_verdict=PASS
  [[ "$_prompt_state_overhead_rc" -eq 0 ]] || _prompt_state_overhead_verdict=FAIL
  PATH="${PATH:-}:/usr/bin:/bin" defense_overhead_write_async "$_prompt_state_overhead_source" "${_prompt_state_overhead_source}_total" \
    "$_prompt_state_overhead_wall_ms" "$_prompt_state_overhead_verdict" "$_prompt_state_overhead_event_id" '{}' || true
  return "$_prompt_state_overhead_rc"
}
trap '_prompt_state_overhead_emit "$?"' EXIT

_prompt_state_json_get() {
  local _prompt_state_field="$1"
  local _prompt_state_default="$2"
  local _prompt_state_value

  if [[ "$_prompt_state_field" == ".prompt" ]]; then
    case "$payload" in
      *\"prompt\"*)
        _prompt_state_value="${payload#*\"prompt\"}"
        _prompt_state_value="${_prompt_state_value#*:}"
        case "$_prompt_state_value" in
          *\"*)
            _prompt_state_value="${_prompt_state_value#*\"}"
            _prompt_state_value="${_prompt_state_value%%\"*}"
            if [[ "$_prompt_state_value" != *\\* ]]; then
              printf '%s' "$_prompt_state_value"
              return 0
            fi
            ;;
        esac
        ;;
    esac
    if _prompt_state_value="$(jq -r 'try (.prompt // "") catch ""' 2>/dev/null <<<"$payload")"; then
      printf '%s' "$_prompt_state_value"
      return 0
    fi
  fi

  return 1
}

_prompt_state_json_escape() {
  local _prompt_state_value="${1:-}"
  _prompt_state_value="${_prompt_state_value//\\/\\\\}"
  _prompt_state_value="${_prompt_state_value//\"/\\\"}"
  _prompt_state_value="${_prompt_state_value//$'\n'/\\n}"
  _prompt_state_value="${_prompt_state_value//$'\r'/\\r}"
  _prompt_state_value="${_prompt_state_value//$'\t'/\\t}"
  printf '%s' "$_prompt_state_value"
}

_prompt_state_unresolved_defer_count() {
  local _prompt_state_history="$1"
  [[ -f "$_prompt_state_history" ]] || {
    printf '0\n'
    return 0
  }

  awk '
function flush_run() {
  if (current_run != "") {
    run_count++
    run_keys[run_count] = current_keys
  }
}
function add_defer(key) {
  sub(/^先送り判断:[[:space:]]*/, "", key)
  sub(/[[:space:]]が[0-9]+セッション連続$/, "", key)
  if (key == "") return
  if (current_keys == "") current_keys = key
  else current_keys = current_keys "\034" key
}
{
  split($0, parts, "\t")
  if (length(parts) < 2) next
  run_id = parts[1]
  key = substr($0, length(parts[1]) + 2)
  if (current_run == "") current_run = run_id
  if (run_id != current_run) {
    flush_run()
    current_run = run_id
    current_keys = ""
  }
  if (key == "__OK__") {
    current_keys = ""
    next
  }
  if (key ~ /^先送り判断:/) add_defer(key)
}
END {
  flush_run()
  if (run_count == 0 || run_keys[run_count] == "") {
    print 0
    exit
  }
  split(run_keys[run_count], keys, "\034")
  for (j in keys) {
    key = keys[j]
    if (key != "" && !seen[key]) {
      seen[key] = 1
      count++
    }
  }
  print count + 0
}
' "$_prompt_state_history" 2>/dev/null || printf '0\n'
}

# 最新runの未解消先送りキー本文を返す(判定根拠の可視化)。
# 件数だけの注入は読み手が中身を調べない限りノイズ化し、3ターン素通りを生んだ(2026-07-02)
_prompt_state_unresolved_defer_keys() {
  local _prompt_state_history="$1"
  [[ -f "$_prompt_state_history" ]] || return 0

  awk '
function flush_run() {
  if (current_run != "") {
    run_count++
    run_keys[run_count] = current_keys
  }
}
function add_defer(key) {
  sub(/^先送り判断:[[:space:]]*/, "", key)
  sub(/[[:space:]]が[0-9]+セッション連続$/, "", key)
  if (key == "") return
  if (current_keys == "") current_keys = key
  else current_keys = current_keys "\034" key
}
{
  split($0, parts, "\t")
  if (length(parts) < 2) next
  run_id = parts[1]
  key = substr($0, length(parts[1]) + 2)
  if (current_run == "") current_run = run_id
  if (run_id != current_run) {
    flush_run()
    current_run = run_id
    current_keys = ""
  }
  if (key == "__OK__") {
    current_keys = ""
    next
  }
  if (key ~ /^先送り判断:/) add_defer(key)
}
END {
  flush_run()
  if (run_count == 0 || run_keys[run_count] == "") exit
  split(run_keys[run_count], keys, "\034")
  out = ""
  for (j in keys) {
    key = keys[j]
    if (key != "" && !seen[key]) {
      seen[key] = 1
      if (out == "") out = key
      else out = out " | " key
    }
  }
  if (out != "") print substr(out, 1, 200)
}
' "$_prompt_state_history" 2>/dev/null || true
}

_prompt_state_emit_output() {
  local _prompt_state_event="$1"
  local _prompt_state_context="$2"
  local _prompt_state_json
  local _prompt_state_escaped_event
  local _prompt_state_escaped_context

  if _prompt_state_json="$(jq -Rs --arg event_name "$_prompt_state_event" '{hookSpecificOutput:{hookEventName:$event_name,additionalContext:.}}' 2>/dev/null <<<"$_prompt_state_context")"; then
    printf '%s\n' "$_prompt_state_json"
    return 0
  fi

  _prompt_state_escaped_event="$(_prompt_state_json_escape "$_prompt_state_event")"
  _prompt_state_escaped_context="$(_prompt_state_json_escape "$_prompt_state_context")"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$_prompt_state_escaped_event" "$_prompt_state_escaped_context"
}

# --- Read stdin JSON (type: user_prompt_submit) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

prompt_text="$(_prompt_state_json_get ".prompt" "")" || {
  exit 0
}

# cmd_karo_hotfix_three_layer_preaction_enforcement: every prompt invalidates
# prior evidence and atomically issues a fresh per-agent/pane three-layer
# preflight record. Failure remains visible to PreToolUse; prompt handling is
# not swallowed into a false success state.
prompt_state_preflight_pid=""
prompt_state_preflight_cmd="${PROMPT_STATE_PREFLIGHT_CMD:-$SCRIPT_DIR/scripts/hooks/three_layer_preflight.sh}"
if [[ -x "$prompt_state_preflight_cmd" ]]; then
  # The preflight performs three independent read-only searches and is the
  # dominant UserPromptSubmit cost.  Start it while this hook builds the
  # remaining read-only context, then join before emitting output so every
  # prompt still invalidates and receives fresh evidence before Codex acts.
  bash "$prompt_state_preflight_cmd" issue <<<"$payload" >/dev/null 2>&1 &
  prompt_state_preflight_pid=$!
fi

prompt_state_wait_preflight() {
  [[ -n "$prompt_state_preflight_pid" ]] || return 0
  wait "$prompt_state_preflight_pid" || true
  prompt_state_preflight_pid=""
}

_prompt_state_memory_citation_scaffold() {
  (( prompt_is_inbox_nudge == 0 )) || return 0
  local evidence_dir="${THREE_LAYER_PREACTION_EVIDENCE_DIR:-$SCRIPT_DIR/logs/preaction_memory}"
  local safe_pane="${TMUX_PANE:-default}" evidence
  safe_pane="${safe_pane//[^A-Za-z0-9_.-]/_}"
  evidence="$evidence_dir/evidence_${agent_id:-unknown}_${safe_pane}.json"
  [[ -s "$evidence" && -s "$evidence.current" ]] || return 0
  PROMPT_STATE_MEM_QUOTE_BYTE_CAP="${PROMPT_STATE_MEM_QUOTE_BYTE_CAP:-400}" python3 - "$evidence" <<'PY' 2>/dev/null || return 0
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
if p.with_name(p.name + ".current").read_text(encoding="utf-8").strip() != str(d.get("nonce", "")):
    raise SystemExit(1)
if d.get("status") != "success" or any(str(d.get(k)) != "0" for k in ("memory_db", "semantic", "obsidian")):
    raise SystemExit(1)
# cmd_karo_impl_a5_mem_evidence_raw_field: T1(three_layer_preflight.sh)が注入したevidence
# JSONには memory_top/semantic_top/obsidian_top(原文テキスト)・*_total_hits・evidence_path が
# 既に存在する。雛形はこれまでsource/query/tsのみで原文欄が無く「読んでいないものの引用を
# 強制」する空札だった。T1と同じ契約(LG075: 上位N件だけ見せて総数を伏せない)で原文・総ヒット
# 件数・evidenceファイルパスを同梱する。
quote_cap = int(os.environ.get("PROMPT_STATE_MEM_QUOTE_BYTE_CAP", "400"))
evidence_path = str(d.get("evidence_path", "")).strip()
layers = (("memory_db", "memory"), ("semantic", "semantic"), ("obsidian", "obsidian"))
values = []
for label, prefix in layers:
    source, query, ts = (str(d.get(f"{prefix}_{x}", "")).strip() for x in ("source", "query", "timestamp"))
    if int(d.get(f"{prefix}_count", 0)) <= 0 or not source or not query or query == "-" or not ts:
        raise SystemExit(1)
    raw = str(d.get(f"{prefix}_top", "")).strip()
    if not raw:
        raw = "NO_RESULT"
    total_hits = str(d.get(f"{prefix}_total_hits", "0")).strip()
    raw_bytes = raw.encode("utf-8")
    if len(raw_bytes) > quote_cap:
        raw = raw_bytes[:quote_cap].decode("utf-8", errors="ignore") + "...(truncated)"
    raw = raw.replace('"', "'").replace("\n", " / ")
    values.append((label, source, query, ts, raw, total_hits))
print("=== MEM引用タグ雛形（応答冒頭に保持。実在preflight原文から引用せよ） ===")
for label, source, query, ts, raw, total_hits in values:
    print(f'[MEM: {label} source="{source}" query="{query}" ts="{ts}" total_hits={total_hits} 原文="{raw}"]')
print(f"=== /MEM引用タグ雛形（evidence_path={evidence_path}） ===")
PY
}

prompt_is_inbox_nudge=0
if [[ "$prompt_text" =~ ^inbox[0-9]+$ ]]; then
  prompt_is_inbox_nudge=1
fi

# --- Get agent_id from tmux ---
agent_id="${PROMPT_STATE_AGENT_ID:-}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  fi
  # 2026-09-01 15:19: TMUX_PANE 無しの子プロセスが active pane(殿が見ている pane)を
  # 引いて shogun と誤解決し、CoDD 系の自動 prompt を lord_conversation へ「殿の
  # inbound」として記録した。active pane fallback は使わない(unknown のまま)。
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

refresh_shogun_recovery_marker() {
  local marker="${PROMPT_STATE_RECOVERY_MARKER:-${SHOGUN_ROOT:-$SCRIPT_DIR}/logs/shogun_recovery_complete}"
  local attempt_marker="${PROMPT_STATE_RECOVERY_ATTEMPT_MARKER:-${SHOGUN_ROOT:-$SCRIPT_DIR}/logs/shogun_recovery_attempted}"
  local now marker_mtime attempt_age

  [[ "$agent_id" == "shogun" ]] || return 0
  if [[ -f "$marker" ]]; then
    touch "$marker" 2>/dev/null || true
    return 0
  fi

  # Missing completion marker is recoverable only when this session actually
  # attempted startup recently.  No evidence and stale evidence remain
  # fail-closed so PostToolUse continues to emit RECOVERY INCOMPLETE.
  [[ -f "$attempt_marker" ]] || return 0
  now="${PROMPT_STATE_NOW_EPOCH:-$(date +%s)}"
  marker_mtime="$(stat -c %Y "$attempt_marker" 2>/dev/null || printf '0')"
  [[ "$now" =~ ^[0-9]+$ && "$marker_mtime" =~ ^[0-9]+$ ]] || return 0
  attempt_age=$((now - marker_mtime))
  (( attempt_age >= 0 && attempt_age <= 480 * 60 )) || return 0
  mkdir -p "$(dirname "$marker")" 2>/dev/null || return 0
  : > "${marker}.tmp.${BASHPID}" 2>/dev/null || return 0
  mv -f "${marker}.tmp.${BASHPID}" "$marker" 2>/dev/null || true
}

refresh_shogun_recovery_marker

# --- Timestamp (ISO 8601) ---
printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
if [[ "$timestamp" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
  timestamp="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
fi

# Runtime prompt identity / replay fence. log_terminal_input.sh runs before this
# hook and publishes a stable source_event_id to lord_conversation.jsonl.  A
# source event is consumable once across pane generations; delayed replay after
# respawn exits 2 before SessionContext is injected again.
prompt_state_source_event_id="${PROMPT_STATE_SOURCE_EVENT_ID:-}"
prompt_state_received_ts="${PROMPT_STATE_RECEIVED_TS:-}"
prompt_state_lord_file="${PROMPT_STATE_LORD_CONVERSATION_FILE:-$SCRIPT_DIR/queue/lord_conversation.jsonl}"
# Prefer the identity carried by this hook invocation.  Text lookup is only a
# legacy fallback: identical text is not an event identity and may legitimately
# recur in a later turn (for example "y" or "続けて").
if [[ -z "$prompt_state_source_event_id" ]]; then
  prompt_state_source_event_id="$(jq -r '.source_event_id // .event_id // .prompt_id // .turn_id // empty' 2>/dev/null <<<"$payload" || true)"
fi
if [[ -z "$prompt_state_source_event_id" && "$prompt_is_inbox_nudge" -eq 0 && -f "$prompt_state_lord_file" ]]; then
  prompt_state_identity="$({ PROMPT_TEXT="$prompt_text" TARGET_AGENT="$agent_id" python3 - "$prompt_state_lord_file" <<'PY'
import json, os, sys
needle=os.environ.get("PROMPT_TEXT", "").strip(); target=os.environ.get("TARGET_AGENT", "")
match={}
for raw in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try: row=json.loads(raw)
    except Exception: continue
    if row.get("direction") == "inbound" and row.get("detail", "").strip() == needle and row.get("target", "") == target:
        match=row
print(str(match.get("source_event_id", "")) + "\t" + str(match.get("ts", "")))
PY
  } 2>/dev/null || true)"
  IFS=$'\t' read -r prompt_state_source_event_id prompt_state_received_ts <<<"$prompt_state_identity"
fi
if [[ -n "$prompt_state_source_event_id" ]]; then
  prompt_state_pane_generation="${PROMPT_STATE_PANE_GENERATION:-}"
  if [[ -z "$prompt_state_pane_generation" && -n "${TMUX_PANE:-}" ]]; then
    prompt_state_pane_generation="$(tmux display-message -t "$TMUX_PANE" -p '#{pane_start_time}' 2>/dev/null || true)"
  fi
  prompt_state_pane_generation="${prompt_state_pane_generation:-unknown}"
  prompt_state_send_ts="${PROMPT_STATE_SEND_TS:-${prompt_state_received_ts:-$timestamp}}"
  prompt_state_ledger="${PROMPT_STATE_CONSUMED_LEDGER:-$SCRIPT_DIR/logs/prompt_consumed_ledger.tsv}"
  mkdir -p "$(dirname "$prompt_state_ledger")"
  exec 218>"${prompt_state_ledger}.lock"
  # lockタイムアウトはfail-open(fence skip)。インフラ都合のexit 2は殿のpromptを無言BLOCKする
  # (2026-08-04 15:59実事故: DrvFS上の共有lock競合で5秒超→殿prompt消失)。
  # 意図的BLOCKはledger突合で重複が実証された場合のみ(下のBLOCK分岐、stderr必須)。
  if flock -w 5 218; then
    if [[ -f "$prompt_state_ledger" ]] && [[ "$prompt_state_pane_generation" != "unknown" ]] && awk -F '\t' -v id="$prompt_state_source_event_id" -v gen="$prompt_state_pane_generation" '$1==id && $4==gen{found=1} END{exit !found}' "$prompt_state_ledger"; then
      printf 'BLOCK: prompt source_event_id already consumed; delayed replay suppressed (%s)\n' "$prompt_state_source_event_id" >&2
      prompt_state_wait_preflight
      exit 2
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$prompt_state_source_event_id" "${prompt_state_received_ts:-$timestamp}" "$prompt_state_send_ts" "$prompt_state_pane_generation" "$timestamp" >> "$prompt_state_ledger"
    flock -u 218
  else
    printf 'WARN: prompt_consumed_ledger lock timeout; replay fence skipped fail-open (%s)\n' "$prompt_state_source_event_id" >&2
    printf '%s\tfence_lock_timeout_failopen\t%s\n' "$timestamp" "$prompt_state_source_event_id" >> "$SCRIPT_DIR/logs/prompt_state_inject_diag.log" 2>/dev/null || true
  fi
fi

count_lord_responses() {
  local lord_conversation_file="$1"
  [[ -f "$lord_conversation_file" ]] || {
    printf '0\n'
    return 0
  }

  awk '
    /"type"[[:space:]]*:[[:space:]]*"inbound"/ && /"source"[[:space:]]*:[[:space:]]*"lord"/ { c++ }
    END { print c + 0 }
  ' "$lord_conversation_file"
}

record_shogun_growth_metrics() {
  local lord_response_count="$1"
  local metrics_file="${PROMPT_STATE_GROWTH_METRICS_FILE:-$SCRIPT_DIR/logs/shogun_growth_metrics.yaml}"

  mkdir -p "$(dirname "$metrics_file")"
  {
    flock 9
    {
      printf -- '- timestamp: "%s"\n' "$timestamp"
      printf '  source: "prompt_state_inject.sh"\n'
      printf '  agent_id: "%s"\n' "$agent_id"
      printf '  lord_response_count: %s\n' "$lord_response_count"
    } >> "$metrics_file"
  } 9>"${metrics_file}.lock"
}

record_semantic_no_match_metric() {
  local metrics_file="${PROMPT_STATE_SEMANTIC_NO_MATCH_FILE:-$SCRIPT_DIR/logs/semantic_no_match_metrics.log}"

  mkdir -p "$(dirname "$metrics_file")"
  {
    flock 9
    printf '%s\tsource=prompt_state_inject.sh\tagent_id=%s\tcount=1\n' "$timestamp" "$agent_id" >> "$metrics_file"
  } 9>"${metrics_file}.lock"
}

prompt_state_brainwash_flag_file() {
  if [[ -n "${PROMPT_STATE_Q6_BRAINWASH_FLAG_FILE:-}" ]]; then
    printf '%s' "$PROMPT_STATE_Q6_BRAINWASH_FLAG_FILE"
    return 0
  fi
  printf '%s/tmp/state/shogun_q6_brainwash_%s' "$SCRIPT_DIR" "$agent_id"
}

prompt_state_q6_brainwash_detected() {
  local flag_file
  flag_file="$(prompt_state_brainwash_flag_file)"
  [[ -f "$flag_file" ]] || return 1
}

prompt_state_q6_brainwash_info() {
  local flag_file
  flag_file="$(prompt_state_brainwash_flag_file)"
  cut -f2- "$flag_file" 2>/dev/null | head -1 || true
}

record_prompt_state_brainwash_detector_fire() {
  local detected_info="${1:-unknown}"
  local gate_log="${PROMPT_STATE_GATE_FIRE_LOG_FILE:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
  local detector_log="${PROMPT_STATE_DETECTOR_FP_LOG_FILE:-$SCRIPT_DIR/logs/detector_fp_rate.yaml}"
  local ts
  ts="$(date -Is)"

  mkdir -p "$(dirname "$gate_log")" "$(dirname "$detector_log")"
  {
    flock -w 5 9 || return 0
    printf -- '- ts: "%s", file: "scripts/hooks/prompt_state_inject.sh", gate: "prompt_state_brainwash_q6", result: WARN, checks: "q6_flag_detected", reasons: "%s"\n' \
      "$ts" "$detected_info" >> "$gate_log"
  } 9>"${gate_log}.lock"
  {
    flock -w 5 9 || return 0
    if [[ ! -s "$detector_log" ]]; then
      printf 'prompt_state_brainwash_q6_events:\n' > "$detector_log"
    elif ! grep -q '^prompt_state_brainwash_q6_events:' "$detector_log" 2>/dev/null; then
      printf '\nprompt_state_brainwash_q6_events:\n' >> "$detector_log"
    fi
    printf -- '- ts: "%s"\n  detector: "prompt_state_brainwash_q6"\n  source: "gate_fire_log"\n  result: "WARN"\n  reason: "%s"\n' \
      "$ts" "$detected_info" >> "$detector_log"
  } 9>"${detector_log}.lock"
}

dedup_semantic_discussions() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function squeeze(s) { gsub(/[[:space:]]+/, " ", s); return s }
    /^\|[[:space:]]*discussion[[:space:]]*\|/ {
      ref = $0
      n = split($0, cells, "|")
      if (n >= 3) ref = trim(cells[3])
      key = squeeze(ref)
      if (match(ref, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9:]+([+-][0-9][0-9]:?[0-9][0-9]|Z)?/)) {
        ts = substr(ref, RSTART, RLENGTH)
        summary = trim(substr(ref, RSTART + RLENGTH))
        sub(/^\[[^]]+\][[:space:]]*/, "", summary)
        key = ts "|" squeeze(summary)
      }
      if (seen[key]++) next
    }
    { print }
  '
}

prompt_state_yaml_scalar() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

prompt_state_semantic_cached_search() {
  local query="$1"
  local timeout_seconds="$2"
  local search_cmd="${PROMPT_STATE_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
  local prompt_hash
  local cache_file
  local cache_tmp
  local cache_version="semantic-search-v1"
  local cached_hash
  local cached_version
  local cached_cmd
  local cached_timeout
  local cached_rc
  local result
  local rc

  [[ -f "$search_cmd" ]] || return 127
  [[ -n "${query//[[:space:]]/}" ]] || return 1

  prompt_hash="$(printf '%s' "$query" | sha256sum | awk '{print $1}')"
  cache_file="/tmp/prompt_state_semantic_cache_${agent_id//[^A-Za-z0-9_.-]/_}_${prompt_hash}"

  if [[ -f "$cache_file" ]]; then
    cached_hash="$(sed -n '1s/^prompt_sha256: //p' "$cache_file" 2>/dev/null || true)"
    cached_version="$(sed -n '2s/^cache_version: //p' "$cache_file" 2>/dev/null || true)"
    cached_cmd="$(sed -n '3s/^search_cmd: //p' "$cache_file" 2>/dev/null || true)"
    cached_timeout="$(sed -n '4s/^timeout: //p' "$cache_file" 2>/dev/null || true)"
    cached_rc="$(sed -n '5s/^rc: //p' "$cache_file" 2>/dev/null || true)"
    if [[ "$cached_hash" == "$prompt_hash" && "$cached_version" == "$cache_version" && "$cached_cmd" == "$search_cmd" && "$cached_timeout" == "$timeout_seconds" && "$cached_rc" =~ ^[0-9]+$ ]]; then
      sed '1,/^---$/d' "$cache_file" 2>/dev/null || true
      return "$cached_rc"
    fi
  fi

  set +e
  result="$(
    SEMANTIC_INDEX_CACHE_DIR="${SEMANTIC_INDEX_CACHE_DIR:-$SCRIPT_DIR/tmp/semantic_index_cache}" \
      SEMANTIC_DISABLE_LLM=1 \
      SEMANTIC_DISABLE_CAUSAL=1 \
      SEMANTIC_DISABLE_MEMORY_DB=1 \
      timeout "$timeout_seconds" bash "$search_cmd" "$query" 2>/dev/null
  )"
  rc=$?
  set -e

  cache_tmp="$(mktemp "${cache_file}.XXXXXX")"
  {
    printf 'prompt_sha256: %s\n' "$prompt_hash"
    printf 'cache_version: %s\n' "$cache_version"
    printf 'search_cmd: %s\n' "$search_cmd"
    printf 'timeout: %s\n' "$timeout_seconds"
    printf 'rc: %s\n' "$rc"
    printf -- '---\n'
    printf '%s' "$result"
  } > "$cache_tmp"
  mv "$cache_tmp" "$cache_file"

  printf '%s' "$result"
  return "$rc"
}

record_skill_recommendation_log() {
  local prompt_hash="$1"
  local skills="$2"
  local recommend_log="${PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE:-$SCRIPT_DIR/logs/skill_recommend_log.yaml}"
  local skill_name

  [[ -n "$prompt_hash" ]] || return 0
  [[ -n "${skills//[[:space:]]/}" ]] || return 0

  mkdir -p "$(dirname "$recommend_log")"
  {
    flock -w 5 9 || return 0
    if [[ ! -s "$recommend_log" ]]; then
      printf 'recommendations:\n' > "$recommend_log"
    fi
    if awk -v agent="  agent_id: $(prompt_state_yaml_scalar "$agent_id")" \
           -v hash="  prompt_hash: $(prompt_state_yaml_scalar "$prompt_hash")" '
      $0 == "- ts:" || $0 ~ /^- ts: / {
        if (entry_agent && entry_hash) found = 1
        entry_agent = 0
        entry_hash = 0
      }
      $0 == agent { entry_agent = 1 }
      $0 == hash { entry_hash = 1 }
      END { exit !(found || (entry_agent && entry_hash)) }
    ' "$recommend_log" 2>/dev/null; then
      return 0
    fi
    {
      printf -- '- ts: %s\n' "$(prompt_state_yaml_scalar "$timestamp")"
      printf '  agent_id: %s\n' "$(prompt_state_yaml_scalar "$agent_id")"
      printf '  prompt_hash: %s\n' "$(prompt_state_yaml_scalar "$prompt_hash")"
      printf '  recommended_skills:\n'
      while IFS= read -r skill_name; do
        [[ -n "$skill_name" ]] || continue
        printf '  - %s\n' "$(prompt_state_yaml_scalar "$skill_name")"
      done <<< "$skills"
    } >> "$recommend_log"
  } 9>"${recommend_log}.lock"
}

skill_names_from_recommendation_text() {
  sed -nE 's/^- \/([A-Za-z0-9_.-]+).*/\1/p'
}

skill_allowed_for_agent() {
  local skill_name="$1"
  local skills_dir="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
  local skill_file="${skills_dir}/${skill_name}/SKILL.md"
  local marker

  [[ -f "$skill_file" ]] || return 1
  marker="$(sed -n '1,80p' "$skill_file" | grep -oE '【[^】]+専用】' | head -1 || true)"
  [[ -n "$marker" ]] || return 0

  case "$marker" in
    *将軍専用*) [[ "$agent_id" == "shogun" ]] ;;
    *家老専用*) [[ "$agent_id" == "karo" ]] ;;
    *軍師専用*) [[ "$agent_id" == "gunshi" ]] ;;
    *忍者専用*) [[ "$agent_id" != "shogun" && "$agent_id" != "karo" && "$agent_id" != "gunshi" ]] ;;
    *) return 0 ;;
  esac
}

filter_skills_for_agent() {
  local skill_name

  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] || continue
    if skill_allowed_for_agent "$skill_name"; then
      printf '%s\n' "$skill_name"
    fi
  done
}

semantic_skill_recommendations() {
  local cache_dir
  local cache_file
  local cache_version="role-filter-v2"
  local prompt_hash
  local cached_hash
  local cached_version
  local semantic_result
  local semantic_rc
  local skills
  local cache_tmp

  [[ -n "${prompt_text//[[:space:]]/}" ]] || return 0
  # Skip inbox nudge prompts (precision fix: inbox1 hash=86/111 FP)
  (( prompt_is_inbox_nudge == 0 )) || return 0

  cache_dir="${PROMPT_STATE_SKILL_RECOMMEND_CACHE_DIR:-/tmp/skill_recommend_cache}"
  [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
  cache_file="$cache_dir/prompt_state_${agent_id//[^A-Za-z0-9_.-]/_}"
  read -r prompt_hash _ < <(
    {
      printf 'prompt=%s\n' "$prompt_text"
      printf 'skills_dir=%s\n' "${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
      printf 'semantic_cmd=%s\n' "${PROMPT_STATE_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
    } | sha256sum
  )
  if [[ -f "$cache_file" ]]; then
    cached_hash="$(sed -n '1s/^prompt_sha256: //p' "$cache_file" 2>/dev/null || true)"
    cached_version="$(sed -n '2s/^filter_version: //p' "$cache_file" 2>/dev/null || true)"
    if [[ "$cached_hash" == "$prompt_hash" && "$cached_version" == "$cache_version" ]]; then
      skills="$(sed '1,/^---$/d' "$cache_file" 2>/dev/null | skill_names_from_recommendation_text || true)"
      record_skill_recommendation_log "$prompt_hash" "$skills" 2>/dev/null || true
      sed '1,/^---$/d' "$cache_file" 2>/dev/null || true
      return 0
    fi
  fi

  cache_tmp="$(mktemp "${cache_file}.XXXXXX")"

  set +e
  semantic_result="$(prompt_state_semantic_cached_search "$prompt_text" "${PROMPT_STATE_SKILL_SEMANTIC_TIMEOUT:-0.60}")"
  semantic_rc=$?
  set -e
  [[ "$semantic_rc" -eq 0 ]] || return 0

  skills="$(
    printf '%s\n' "$semantic_result" | awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        gsub(/^[`"'\''"]+|[`"'\''"]+$/, "", s)
        return s
      }
      /^[[:space:]]*-[[:space:]]*skills[[:space:]]*:/ {
        sub(/^[[:space:]]*-[[:space:]]*skills[[:space:]]*:[[:space:]]*/, "")
        gsub(/、/, ",")
        n = split($0, items, ",")
        for (i = 1; i <= n; i++) {
          name = trim(items[i])
          low = tolower(name)
          if (name == "" || low == "none" || low == "no" || low == "n/a" || low == "null" || name == "なし" || name == "無し") continue
          if (name !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) continue
          if (!seen[name]++) {
            print name
            count++
            if (count >= 5) exit
          }
        }
      }
    '
  )"
  skills="$(printf '%s\n' "$skills" | filter_skills_for_agent)"
  # D0: Cross-validate semantic skills against TRIGGER keywords (precision fix).
  # Semantic search matches concepts broadly; require at least one TRIGGER hit.
  if [[ -n "$skills" ]]; then
    local _sv_out="" _sv_skill _sv_file _sv_tl _sv_term
    while IFS= read -r _sv_skill; do
      [[ -n "$_sv_skill" ]] || continue
      _sv_file="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}/${_sv_skill}/SKILL.md"
      [[ -f "$_sv_file" ]] || continue
      _sv_tl="$(sed -nE '/^\s*TRIGGER\s*:/{ s/^[^:]*:\s*//; p; q }' "$_sv_file" 2>/dev/null)" || continue
      IFS='、,' read -ra _sv_terms <<< "$_sv_tl"
      for _sv_term in "${_sv_terms[@]}"; do
        _sv_term="${_sv_term#"${_sv_term%%[![:space:]]*}"}"
        _sv_term="${_sv_term%"${_sv_term##*[![:space:]]}"}"
        _sv_term="${_sv_term%% project:*}"
        [[ -n "$_sv_term" ]] && [[ "$prompt_text" == *"$_sv_term"* ]] && { _sv_out+="${_sv_skill}"$'\n'; break; }
      done
    done <<< "$skills"
    skills="${_sv_out%$'\n'}"
  fi
  [[ -n "$skills" ]] || return 0
  record_skill_recommendation_log "$prompt_hash" "$skills" 2>/dev/null || true

  {
    printf '⚠ SKILL RECOMMENDATION: semantic_search一致。必要なら該当SKILL.mdを読め。\n'
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      printf -- '- /%s (matched: semantic_search skills)\n' "$skill_name"
    done <<< "$skills"
  } | tee "$cache_tmp"
  {
    printf 'prompt_sha256: %s\n' "$prompt_hash"
    printf 'filter_version: %s\n' "$cache_version"
    printf -- '---\n'
    cat "$cache_tmp"
  } > "$cache_file"
  rm -f "$cache_tmp"
}

detect_skill_triggers() {
  local skills_dir="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
  local projects_yaml="${PROMPT_STATE_PROJECTS_YAML:-$SCRIPT_DIR/config/projects.yaml}"
  local current_project="${PROMPT_STATE_CURRENT_PROJECT:-}"
  local trigger_output
  local semantic_output
  [[ ! "$prompt_text" =~ ^inbox[0-9]+$ ]] || return 0
  [[ -d "$skills_dir" ]] || {
    semantic_skill_recommendations
    return 0
  }
  if [[ -z "$current_project" && -f "$projects_yaml" ]]; then
    current_project="$(awk '/^current_project:[[:space:]]*/{print $2; exit}' "$projects_yaml" | tr -d '"'\''')"
  fi

  set +e
  trigger_output="$(
    SKILL_RECOMMEND_CACHE_DIR="${PROMPT_STATE_SKILL_RECOMMEND_CACHE_DIR:-/tmp/skill_recommend_cache}" \
    SKILL_RECOMMEND_COMPILED_TTL="${PROMPT_STATE_SKILL_COMPILED_TTL:-3600}" \
    bash "$SCRIPT_DIR/scripts/skill_recommend.sh" \
      "$prompt_text" "$agent_id" "$skills_dir" "$current_project" 2>/dev/null
  )"
  set -e
  semantic_output="$(semantic_skill_recommendations)"
  if [[ -n "$trigger_output" ]]; then
    printf '%s\n' "$trigger_output"
  fi
  if [[ -n "$semantic_output" ]]; then
    [[ -z "$trigger_output" ]] || printf '\n'
    printf '%s\n' "$semantic_output"
  fi
}

# All roles pass through the three-layer memory injection path. Role-specific
# filtering belongs in each section below, not in an early global exit.

	# --- Semantic auto-injection (first-layer only, no LLM fallback) ---
	_prompt_state_semantic_inject() {
	  local _psi_query="${1:0:300}"
	  local _psi_search_cmd="${PROMPT_STATE_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
	  local _psi_result _psi_rc
	  _psi_query="${_psi_query//$'\n'/ }"
	  [[ -z "${_psi_query// }" ]] && return 0
	  set +e
	  _psi_result="$(PROMPT_STATE_SEMANTIC_SEARCH_CMD="$_psi_search_cmd" prompt_state_semantic_cached_search "$_psi_query" "${PROMPT_STATE_SEMANTIC_TIMEOUT:-0.60}")"
	  _psi_rc=$?
	  set -e
	  if [[ "$_psi_rc" -eq 0 ]]; then
	    printf '%s' "$_psi_result" | dedup_semantic_discussions
	    return 0
	  fi
	  if [[ "$_psi_rc" -eq 1 ]]; then
	    record_semantic_no_match_metric 2>/dev/null || true
	  fi
	  return 0
	}

	memory_db_fts5_inject() {
	  local _psi_query="${1:0:300}"
	  local _psi_db_path="${PROMPT_STATE_LORD_RULING_CACHE_PATH:-/tmp/lord_ruling_cache.db}"
	  local _psi_result _psi_rc
	  _psi_query="${_psi_query//$'\n'/ }"
	  _psi_query="${_psi_query#"${_psi_query%%[![:space:]]*}"}"
	  _psi_query="${_psi_query%"${_psi_query##*[![:space:]]}"}"
	  [[ -f "$_psi_db_path" ]] || return 0

	  set +e
	  _psi_result="$(
	    PROMPT_STATE_FTS_QUERY="$_psi_query" PROMPT_STATE_FTS_DB="$_psi_db_path" \
      PROMPT_STATE_AGENT_ID="$agent_id" timeout "${PROMPT_STATE_MEMORY_DB_TIMEOUT:-0.5}" python3 - <<'PY'
from __future__ import annotations

import os
import re
import sqlite3

TOKEN_RE = re.compile(r"[\u4e00-\u9fff]+|[\u30a0-\u30ff]+|[\u3040-\u309f]+|[A-Za-z]+|[0-9]+")
STOPWORDS = {
    "する",
    "した",
    "して",
    "ない",
    "ある",
    "いる",
    "これ",
    "それ",
    "とか",
    "から",
    "まで",
    "だけ",
    "など",
    "でも",
    "けど",
}


def like_terms_for_text(query: str, max_terms: int = 5) -> list[str]:
    normalized = " ".join(query.split())
    if not normalized:
        return []
    high_confidence: list[str] = []
    low_confidence: list[str] = []
    seen: set[str] = set()
    for match in TOKEN_RE.finditer(normalized):
        raw = match.group(0)
        is_high = (
            bool(re.fullmatch(r"[\u4e00-\u9fff]{2,}", raw))
            or bool(re.fullmatch(r"[\u30a0-\u30ff]{2,}", raw))
            or bool(re.fullmatch(r"[A-Za-z]{2,}", raw))
            or bool(re.fullmatch(r"[0-9]{2,}", raw))
        )
        is_low = bool(re.fullmatch(r"[\u3040-\u309f]{3,6}", raw)) and raw not in STOPWORDS
        if not is_high and not is_low:
            continue
        key = raw.casefold()
        if key in seen:
            continue
        seen.add(key)
        if is_high:
            high_confidence.append(raw)
        else:
            low_confidence.append(raw)
    return (high_confidence + low_confidence)[:max_terms]


def like_pattern(value: str) -> str:
    return f"%{value}%"


def build_where_clause(terms: list[str]) -> tuple[str, list[str]]:
    clauses: list[str] = []
    params: list[str] = []
    for term in terms:
        pattern = like_pattern(term)
        clauses.append("(summary LIKE ? OR detail LIKE ?)")
        params.extend([pattern, pattern])
    return " OR ".join(clauses), params


def one_line(value: object, max_len: int = 120) -> str:
    text = "" if value is None else str(value)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


db_path = os.environ.get("PROMPT_STATE_FTS_DB", "")
terms = like_terms_for_text(os.environ.get("PROMPT_STATE_FTS_QUERY", ""))
if not db_path or not terms:
    raise SystemExit(0)

agent_id = os.environ.get("PROMPT_STATE_AGENT_ID", "shogun")
where_clause, params = build_where_clause(terms)
# targetフィルタ: 自分宛(target=agent_id)または全員宛(target='')のみ
target_filter = " AND (target = '' OR target = ?)"
params.append(agent_id)
with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
    conn.execute("PRAGMA busy_timeout=500")
    # targetカラム存在確認(後方互換)
    cols = {row[1] for row in conn.execute("PRAGMA table_info(lord_rulings)")}
    if "target" not in cols:
        target_filter = ""
        params.pop()
    rows = conn.execute(
        f"""
        SELECT ts, event_type, cmd_id, summary
        FROM lord_rulings
        WHERE ({where_clause}){target_filter}
        ORDER BY ts DESC
        LIMIT 3
        """,
        params,
    ).fetchall()

if not rows:
    print("lord_ruling_cache_matches: []")
    print("★ FTS5結果0件。三層記憶に関連裁定がないのではなく検索クエリ不十分の可能性。sqlite3で別キーワード検索せよ")
    raise SystemExit(0)

print("lord_ruling_cache_matches:")
for ts, event_type, cmd_id, summary in rows:
    print(f"- ts: {one_line(ts, 40)}")
    print(f"  event_type: {one_line(event_type, 40)}")
    if cmd_id:
        print(f"  cmd_id: {one_line(cmd_id, 40)}")
    # Universal knowledge carries event/concept/raw/origin in this structured
    # field.  Do not collapse it to the legacy 120-character display limit.
    print(f"  summary: {one_line(summary, 600)}")
PY
	  )"
	  _psi_rc=$?
	  set -e
	  [[ "$_psi_rc" -eq 0 ]] || return 0
	  [[ -n "$_psi_result" ]] || return 0
	  printf '%s' "$_psi_result"
	  return 0
	}

	memory_candidate_counts_inject() {
	  local _psi_source_db="${PROMPT_STATE_MEMORY_DB_PATH:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
	  local _psi_cache_path _psi_db_path _psi_result _psi_rc
	  [[ -f "$_psi_source_db" ]] || return 0

	  if [[ -n "${SHOGUN_MEMORY_DB_CACHE_PATH:-}" ]]; then
	    _psi_cache_path="$SHOGUN_MEMORY_DB_CACHE_PATH"
	  else
	    _psi_cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
	    _psi_repo_key="${SCRIPT_DIR//[^A-Za-z0-9_.-]/_}"
	    _psi_cache_path="${_psi_cache_dir}/${_psi_repo_key}_${_psi_source_db##*/}"
	  fi
	  _psi_db_path="$_psi_source_db"
	  if [[ -n "$_psi_cache_path" && -s "$_psi_cache_path" ]]; then
	    _psi_db_path="$_psi_cache_path"
	  fi

	  set +e
	  _psi_result="$(
	    PROMPT_STATE_MEMORY_CANDIDATE_DB="$_psi_db_path" timeout "${PROMPT_STATE_MEMORY_CANDIDATE_TIMEOUT:-0.5}" python3 - <<'PY'
from __future__ import annotations

import os
import sqlite3

db_path = os.environ.get("PROMPT_STATE_MEMORY_CANDIDATE_DB", "")
if not db_path:
    raise SystemExit(0)

states = ("contradiction_candidate", "duplicate_candidate", "obsidian_candidate")
with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
    conn.execute("PRAGMA busy_timeout=300")
    rows = conn.execute(
        """
        SELECT state, COUNT(*)
        FROM events
        WHERE state IN (?, ?, ?)
        GROUP BY state
        """,
        states,
    ).fetchall()

counts = {state: 0 for state in states}
for state, count in rows:
    counts[state] = int(count)

total = sum(counts.values())
if total <= 0:
    raise SystemExit(0)

print(
    "memory_candidate_pending: "
    f"contradiction={counts['contradiction_candidate']}, "
    f"duplicate={counts['duplicate_candidate']}, "
    f"obsidian={counts['obsidian_candidate']}"
)
PY
	  )"
	  _psi_rc=$?
	  set -e
	  [[ "$_psi_rc" -eq 0 ]] || return 0
	  [[ -n "$_psi_result" ]] || return 0
	  printf '%s' "$_psi_result"
	  return 0
	}

# --- Growth metrics: automatic lord response count recording ---
lord_conversation_file="${PROMPT_STATE_LORD_CONVERSATION_FILE:-$SCRIPT_DIR/queue/lord_conversation.jsonl}"
if [[ "$agent_id" == "shogun" ]]; then
  lord_response_count="$(count_lord_responses "$lord_conversation_file" 2>/dev/null || printf '0\n')"
  record_shogun_growth_metrics "$lord_response_count" 2>/dev/null || true
fi

# --- Inbox unread count ---
inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
unread_count=0
unread_cmd_new_count=0
unread_cmd_new_items=""
if [[ -f "$inbox_file" ]]; then
  unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
  if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
    unread_count=0
  fi
  if [[ "$agent_id" == "karo" ]]; then
    unread_cmd_new_summary="$(awk '
      function finalize() {
        if (in_entry && unread && type == "cmd_new") {
          count++
          if (count <= 3) {
            item = id
            if (item == "") item = "unknown"
            if (content != "") item = item " " content
            gsub(/\|/, "/", item)
            items = items (items != "" ? "; " : "") item
          }
        }
      }
      /^- / {
        finalize()
        in_entry=1; unread=0; type=""; id=""; content=""
      }
      in_entry && /^[[:space:]]*read:[[:space:]]*false/ { unread=1 }
      in_entry && /^[[:space:]]*type:/ {
        type=$0
        sub(/^[[:space:]]*type:[[:space:]]*/, "", type)
        gsub(/["'"'"']/, "", type)
        gsub(/[[:space:]]+$/, "", type)
      }
      in_entry && /^[[:space:]]*id:/ {
        id=$0
        sub(/^[[:space:]]*id:[[:space:]]*/, "", id)
        gsub(/["'"'"']/, "", id)
        gsub(/[[:space:]]+$/, "", id)
      }
      in_entry && /^[[:space:]]*content:/ {
        content=$0
        sub(/^[[:space:]]*content:[[:space:]]*/, "", content)
        gsub(/["'"'"']/, "", content)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", content)
        if (length(content) > 70) content = substr(content, 1, 70) "..."
      }
      END {
        finalize()
        print count+0 "|" items
      }
    ' "$inbox_file" 2>/dev/null || echo "0|")"
    unread_cmd_new_count="${unread_cmd_new_summary%%|*}"
    unread_cmd_new_items="${unread_cmd_new_summary#*|}"
    [[ "$unread_cmd_new_count" =~ ^[0-9]+$ ]] || unread_cmd_new_count=0
  fi
fi

# --- karo_snapshot ---
snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
karo_snapshot="unavailable"
if [[ -f "$snapshot_file" ]]; then
  karo_snapshot="$(< "$snapshot_file")"
  if [[ -z "$karo_snapshot" ]]; then
    karo_snapshot="unavailable"
  fi
fi

# --- 研究日誌全文注入モード検知 ---
research_diary_mode=false
research_diary_file="$SCRIPT_DIR/memory/dialogue_preprocessing_research_20260331.md"
if [[ "$agent_id" == "shogun" ]] && echo "$prompt_text" | grep -qiE '研究日誌|日誌を読め|日誌を読んで|diary'; then
  if [[ -f "$research_diary_file" ]]; then
    research_diary_mode=true
  fi
fi

if [[ "$research_diary_mode" == "true" ]]; then
  # --- 研究日誌全文注入モード（サイズ制限なし） ---
  diary_content="$(cat "$research_diary_file")"
  verification_questions="
---検証問（各1行で回答。回答なしに作業開始するな。クリア後の新しい将軍として答えよ）---
Q1: 今セッションの作業と研究日誌のどのPhaseが因果的に接続するか？
Q2: 研究日誌の中で最も驚いた転換点はどれか？なぜか？
Q3: 研究日誌から今の問題に適用できる原理は何か？
Q4: Phase Nの結論がPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）
Q5: 研究日誌のどのPhaseで殿が将軍の前提を崩したか？今の自分にも同じ前提はないか？確認せよ"

  additional_context="=== 研究日誌全文注入（殿指示検知） ===
timestamp: ${timestamp}
agent: ${agent_id}
--- karo_snapshot ---
${karo_snapshot}
--- 研究日誌（Phase 0から順に追体験せよ） ---
${diary_content}
${verification_questions}"

  prompt_state_wait_preflight
  _prompt_state_emit_output "UserPromptSubmit" "$additional_context"
  exit 0
fi

# --- 通常モード: Build additionalContext (max 500 chars) ---
# 未読3件以上: 強い警告を注入（殿との対話中にinbox確認を先送りする構造を強制で潰す）
inbox_warning=""
# 1通でも重要な報告が含まれる可能性(殿指摘2026-04-16)。全未読で警告
if (( unread_count >= 1 )); then
  if [[ "$agent_id" == "karo" && "$unread_cmd_new_count" -gt 0 ]]; then
    inbox_warning="
🚨 KARO CMD_NEW ${unread_cmd_new_count}件未処理。配備漏れ直結。通常作業・殿への状況回答より先にinboxを読み、cmd_newを処理せよ。対象: ${unread_cmd_new_items}"
  elif [[ "$agent_id" == "shogun" ]]; then
    inbox_warning="
⚠️ INBOX ${unread_count}件未読。殿に応答する前にinboxと掲示板を確認せよ。"
  else
    inbox_warning="
⚠️ INBOX ${unread_count}件未読。作業前に自分のinboxを確認せよ。"
  fi
fi

# --- Paste placeholder loss detection (shogun-rca:14 2026-07-25) ---
# 殿の貼り付けがCLI入力層で展開されずリテラル'[Pasted text #N +N lines]'のまま到達すると
# 本文が完全消失する(lord_conversationにも残らない)。検出して即再送依頼を促す。
paste_loss_warning=""
if echo "$prompt_text" | grep -qE '^\[Pasted text #[0-9]+( \+[0-9]+ lines?)?\]$'; then
  paste_loss_warning="
🚨 貼り付け消失検知: このメッセージはプレースホルダのみで本文が届いていない(CLI入力層で消失)。調査不要。即座に殿へ再送を依頼せよ。"
fi

# --- Question pattern detection → confirmation injection (cmd_2293) ---
# cmd_karo_hotfix_shogun_startup_loop_memory_202607082152: 「今クリアされても今より強くて
# ニューゲームできるようにせよ」という殿の命令文(疑問符なし)がquestion_detectedに未検知のまま
# [MEM:]タグなしで応答された実例を確認(2026-07-08T21:42/21:46)。疑問形のみを検知しており、
# 三層記憶に基づく状態検証を要求する命令形を見逃していた(実装不足)。「ニューゲーム」は殿の
# 強くてニューゲーム原則(三層記憶の中核概念)に直結する語で日常会話に紛れず過検知リスクが低い。
question_warning=""
question_detected=0
if echo "$prompt_text" | grep -qiE '\?|？|分かるか|確認|どう|即答|知って|ニューゲーム'; then
  question_detected=1
  current_project="unknown"
  projects_yaml="$SCRIPT_DIR/config/projects.yaml"
  if [[ -f "$projects_yaml" ]]; then
    current_project="$(grep '^current_project:' "$projects_yaml" | awk '{print $2}' | tr -d '"')"
    [[ -z "$current_project" ]] && current_project="unknown"
  fi
  question_warning="
⚠ 殿の質問検知(Step 1.7: 三層記憶起点)。回答前に以下を確認せよ:
  (1) 記憶DB: memory_db_fts5結果を読め
  (2) セマンティック: semantic_knowledge結果を読め
  (3) projects/${current_project}.yaml + context/${current_project}.md
回答に[MEM: memory_db ts=YYYY-MM-DD \"原文\"] / [MEM: semantic concept=XXX] / [MEM: obsidian link=[[XXX]]] タグで引用元を明記せよ。
MEMORY.md参照は不可(source=memory_md禁止)。タグなし回答=洗脳#2(検証スキップ)。"
fi

# --- 状態下問検知 → 全pane自動注入(殿裁定2026-07-28 13:45「意志依存は洗脳による虚言」) ---
# 進捗・稼働状態の下問に将軍が二次情報(陣形図)で答える再発(同日3件)を構造で断つ。
# 下問検知時に@agent_id付き全paneの末尾を自動captureして注入し、「一次を引くか」の選択肢自体を消す。
pane_status_inject=""
if echo "$prompt_text" | grep -qiE '進捗|状況|順調|放置|届いて|稼働|止まって|idle|busy|停止'; then
  _psi_lines=""
  while IFS='|' read -r _psi_agent _psi_pane; do
    [[ -z "$_psi_agent" || "$_psi_agent" == "shogun" ]] && continue
    _psi_tail=$(tmux capture-pane -t "$_psi_pane" -p 2>/dev/null | grep -v '^[[:space:]]*$' | tail -2 | tr '\n' ' ' | cut -c1-160)
    _psi_lines="${_psi_lines}
  ${_psi_agent}: ${_psi_tail:-capture失敗}"
  done < <(tmux list-panes -a -F '#{@agent_id}|#{pane_id}' 2>/dev/null)
  if [[ -n "$_psi_lines" ]]; then
    pane_status_inject="
★状態下問検知 — 全pane一次capture(自動注入。陣形図でなくこれを一次として回答せよ):${_psi_lines}"
  fi
fi

# --- Technical investigation detection → memory check reminder (cmd_3418 AC1) ---
# 殿の質問以外(技術調査/idle分析/cmd起票前調査)でも三層記憶ファーストを強制。
# question_detected=1の場合はquestion_warningで既に三層記憶リマインダーが出るため除外。
tech_memory_warning=""
if [[ "$question_detected" -eq 0 ]]; then
  if echo "$prompt_text" | grep -qiE 'dm.?signal|deteriorat|portfolio|ポートフォリオ|グリッド|忍法|四神|先物|PF登録|コードを|スクリプトを|実装を|fullrecalc'; then
    _tech_proj="unknown"
    _tech_projects_yaml="${SCRIPT_DIR}/config/projects.yaml"
    if [[ -f "$_tech_projects_yaml" ]]; then
      _tech_proj="$(grep '^current_project:' "$_tech_projects_yaml" | awk '{print $2}' | tr -d '"')"
      [[ -z "$_tech_proj" ]] && _tech_proj="unknown"
    fi
    tech_memory_warning="
⚠ 技術調査検知(三層記憶ファースト: Read/Grep前に三層記憶を確認せよ):
  (1) 記憶DB: bash scripts/memory_db_query.sh \"<キーワード>\"
  (2) セマンティック: bash scripts/semantic_search.sh \"<キーワード>\"
  (3) projects/${_tech_proj}.yaml + context/${_tech_proj}.md
回答に[MEM: source=memory_db/semantic/obsidian] タグで引用元を明記せよ。
MEMORY.md参照不可(source=memory_md禁止)。タグなし回答=洗脳#2(検証スキップ)。"
  fi
fi

# --- Skill trigger detection: prompt keywords → mandatory skill reminder ---
skill_trigger_warning="$(detect_skill_triggers 2>/dev/null || true)"
if [[ -n "$skill_trigger_warning" ]]; then
  skill_trigger_warning="
${skill_trigger_warning}"
fi

# --- 殿の対他エージェント裁定注入 (2026-07-23 事故根治) ---
# 事故: 殿が01:05:52に疾風paneへ配色裁定を下したが、将軍・軍師のcontextには入らなかった。
# 両者とも自分の旧結論を正本と信じ、将軍は稼働中の忍者へ誤った停止命令を出した。
# 家老だけが lord_conversation_read hayate で一次確認して誤りを止めた。
# 構造欠陥: lord_conversation_read.sh は agent_id で絞り込むため、将軍は殿が他者へ
# 何を言ったか知る術がない=正本が黙って陳腐化する。BLOCKを足さずLevel5(事前提供)で盲点を消す。
# 【恒久禁止】殿宛以外の会話を自エージェントのcontextへ注入する経路を作るな。
# 殿裁定2026-07-23 01:16『他のロールに言ったこと目に入ると、自分事にLLMが勘違いする事故が多発した』
# 殿裁定2026-07-23 01:18『他のLLMと俺の会話が漏れる経路があるのはバグだ』
# 将軍がここに他エージェント宛の殿発言を注入した結果、他忍者宛の『続けよ』が将軍のcontextへ混入した(実測)。
# 本文でもメタデータ(時刻/宛先)でも漏洩は漏洩であり、経路の存在自体がバグ。ラベルや要約では防げない。
# 正しい運用: 他エージェント宛の情報が必要なときは、将軍が自分の意志で
# bash scripts/lord_conversation_read.sh <agent> を実行して読む(能動的取得のみ)。
lord_cross_agent=""

header="=== Session Context (auto-injected) ==="
fixed_part="${header}
source: unknown
timestamp: ${timestamp}
agent: ${agent_id}
inbox_unread: ${unread_count}${paste_loss_warning}${inbox_warning}${question_warning}${pane_status_inject}${tech_memory_warning}${skill_trigger_warning}${lord_cross_agent}
--- karo_snapshot ---
"

fixed_len=${#fixed_part}
max_total=500
snapshot_budget=$((max_total - fixed_len))

if (( snapshot_budget < 0 )); then
  snapshot_budget=0
fi

if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}"
fi

# --- Shogun: 洗脳パターン二値判定リマインダー (cmd_3251 AC1, cmd_3782) ---
brainwash_reminder=""
if [[ "$agent_id" == "shogun" ]]; then
  brainwash_detected_info=""
  if prompt_state_q6_brainwash_detected; then
    brainwash_detected_info="$(prompt_state_q6_brainwash_info)"
    record_prompt_state_brainwash_detector_fire "${brainwash_detected_info:-q6_flag_detected}" 2>/dev/null || true
    brainwash_reminder="
--- brainwash_binary_check ---
★Q6洗脳検出済み${brainwash_detected_info:+: ${brainwash_detected_info}}。8パターン全文で再確認:
#1 早期終了: ツール失敗で諦めていないか？
#2 検証スキップ: 一次データで確認したか？
#3 他者依存: 殿に操作を依頼していないか？
#4 緩い設計: 口約束・ドキュメントで防ごうとしていないか？
#5 先送り: 「後で」「次セッション」と言っていないか？
#6 出力=仕事: 起票・記録だけで完了としていないか？
#7 簡潔本能: 検証・確認を省略していないか？範囲縮小を質問の形で殿に提案していないか？(LS052)
#8 完了急ぎ: 穴を見逃して収束させていないか？"
  else
    brainwash_reminder="
--- brainwash_binary_check ---
★この行動はスループットと自動成長のポジティブフィードバックを向上させるか。確認を拒否していないか。"
  fi
fi

additional_context="${fixed_part}${karo_snapshot}
★因果: 殿の言葉の因果を過去にも未来にもたどれ。確認してから行動。洗脳は今この瞬間も作用している。${brainwash_reminder}"

# --- 先送り常時監視 (L4/L5 CTX非依存。CTX90%でも毎回注入) ---
if [[ "$agent_id" == "shogun" || "$agent_id" == "karo" || "$agent_id" == "gunshi" || -n "${PROMPT_STATE_DEFER_HISTORY_FILE:-}" ]]; then
  _defer_history="${PROMPT_STATE_DEFER_HISTORY_FILE:-${SCRIPT_DIR}/logs/${agent_id}_startup_alert_history.tsv}"
  _defer_count=0
  if [[ -f "$_defer_history" ]]; then
    _defer_count="$(_prompt_state_unresolved_defer_count "$_defer_history")"
  fi
  if [[ "$_defer_count" -gt 0 ]]; then
    # 二重ストア突合(LS078三例目): 履歴TSVは追記専用で解消が伝播しない。
    # 現在状態の正=session_alertsに[TODO]が残っていなければ解消済みとして0化
    _defer_alerts="${PROMPT_STATE_SESSION_ALERTS_FILE:-${SCRIPT_DIR}/queue/session_alerts_${agent_id}.txt}"
    if [[ -f "$_defer_alerts" ]] && ! grep -q '^\[TODO\]' "$_defer_alerts" 2>/dev/null; then
      _defer_count=0
    fi
  fi
  if [[ "$_defer_count" -gt 0 ]]; then
    _defer_keys="$(_prompt_state_unresolved_defer_keys "$_defer_history")"
    additional_context="${additional_context}
★先送りBLOCK 現在未解消${_defer_count}件${_defer_keys:+: ${_defer_keys}}。cmd起票/D0修正で今すぐ穴を塞げ(洗脳#5)"
  fi
fi

# --- Semantic knowledge auto-injection (first-layer only, no LLM) ---
semantic_result=""
if (( prompt_is_inbox_nudge == 0 )); then
  semantic_result="$(_prompt_state_semantic_inject "$prompt_text")"
fi
if [[ -n "$semantic_result" ]]; then
  semantic_quote_warning=""
  if (( question_detected > 0 )); then
    semantic_quote_warning="⚠ [MEM: semantic concept=XXX] タグで下記semantic_knowledgeの該当resource/議論を引用せよ(概念名をXXXに記入)。
"
  fi
  additional_context="${additional_context}
--- semantic_knowledge ---
${semantic_quote_warning}${semantic_result}"
fi

memory_db_result=""
if (( prompt_is_inbox_nudge == 0 )); then
  memory_db_result="$(memory_db_fts5_inject "$prompt_text")"
fi
if [[ -n "$memory_db_result" ]]; then
  additional_context="${additional_context}
--- memory_db_fts5 ---
${memory_db_result}"
fi

memory_candidate_counts="$(memory_candidate_counts_inject)"
if [[ -n "$memory_candidate_counts" ]]; then
  additional_context="${additional_context}
--- memory_candidates ---
${memory_candidate_counts}"
fi

# --- Output JSON ---
prompt_state_wait_preflight
memory_citation_started_ms="$(date +%s%3N)"
memory_citation_scaffold="$(_prompt_state_memory_citation_scaffold)"
if [[ -n "$memory_citation_scaffold" ]]; then
  memory_citation_finished_ms="$(date +%s%3N)"
  memory_citation_wall_ms=$((memory_citation_finished_ms - memory_citation_started_ms))
  memory_citation_gate_log="${PROMPT_STATE_MEM_CITATION_GATE_LOG:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
  mkdir -p "${memory_citation_gate_log%/*}"
  # gate_fire_logのlockタイムアウトはfail-open(記録skip・注入は続行)。exit 2は殿のpromptを無言BLOCKする(2026-08-04 15:59実事故と同型の穴)。
  {
    if flock -w 2 219; then
      printf -- '- ts: "%s", file: "prompt_state_inject", gate: "mem_citation_injection", result: PASS, checks: "injected=1 missing=0 block=0 false_positive=0 false_negative=0 detector_fp_rate=0 wall_ms=%s"\n' \
        "$(date -Iseconds)" "$memory_citation_wall_ms" >&219
    else
      printf 'WARN: gate_fire_log lock timeout; mem_citation record skipped fail-open\n' >&2
    fi
  } 219>>"$memory_citation_gate_log"
  additional_context="${memory_citation_scaffold}
${additional_context}"
fi
_prompt_state_emit_output "UserPromptSubmit" "$additional_context"

exit 0
