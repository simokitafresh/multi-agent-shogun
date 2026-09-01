#!/usr/bin/env bash
# Combined Bash PreToolUse guard: block_destructive + no-verify + report-deny + yaml-dump
# cmd_1661: 4 hooks → 1 script. Eliminates 3 bash startup costs (~60ms each).
set -euo pipefail

if [ -n "${HOOK_PAYLOAD+x}" ]; then
    payload="$HOOK_PAYLOAD"
else
    payload="$(cat)"
fi
if [[ -n "${BATS_TEST_FILENAME:-}" && -n "${GUARD14_BATS_COMMAND+x}" ]]; then
    command="$GUARD14_BATS_COMMAND"
    payload='{"tool_name":"Bash","tool_input":{"command":"guard14-bats-command"}}'
fi
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
shell_tool="$(awk 'match($0, /"(tool_name|toolName)"[[:space:]]*:[[:space:]]*"([^"]+)"/) { value=substr($0,RSTART,RLENGTH); sub(/^.*:[[:space:]]*"/,"",value); sub(/"$/,"",value); print value; exit }' <<< "$payload" 2>/dev/null || true)"
case "$shell_tool" in
    Bash|exec_command|unified_exec) ;;
    *) exit 0 ;;
esac
command="${command:-}"
# cmd_2075: jq → awk置換 (jq≈4ms → awk≈2ms, 前回revertとの差: サブシェル維持/ツール軽量化)
# awk char-by-char でJSON stringを復元する。ここで一度だけdecodeし、
# 全Guardへ実際のshell command（改行・quoteを含む）を渡す。
if [[ -z "$command" && ( "$payload" == *'"tool_input"'* || "$payload" == *'"toolInput"'* ) \
    && ( "$payload" == *'"command"'* || "$payload" == *'"cmd"'* ) ]]; then
    command="$(awk '
        match($0, /"(command|cmd)"[[:space:]]*:[[:space:]]*"/) {
            s = substr($0, RSTART + RLENGTH)
            n = length(s); result = ""
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (c == "\\" && i < n) {
                    e = substr(s, i + 1, 1)
                    if (e == "n") result = result "\n"
                    else if (e == "r") result = result "\r"
                    else if (e == "t") result = result "\t"
                    else if (e == "b") result = result sprintf("%c", 8)
                    else if (e == "f") result = result sprintf("%c", 12)
                    else if (e == "\"" || e == "\\" || e == "/") result = result e
                    else if (e == "u" && i + 5 <= n) {
                        # Unicode escapes are not shell structure. Preserve
                        # them losslessly; command boundaries are ASCII.
                        result = result substr(s, i, 6)
                        i += 5
                        continue
                    } else result = result "\\" e
                    i++
                    continue
                }
                if (c == "\"") break
                result = result c
            }
            print result; exit
        }
    ' <<< "$payload" 2>/dev/null || true)"
fi

emit_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
    printf '%s\n' "$1" >&2
    exit 2  # exit 2 = intentional block (Codex CLI continues). exit 1 = hook error (Codex CLI crashes)
}

_pre_bash_self="${BASH_SOURCE[0]}"
[[ "$_pre_bash_self" != /* ]] && _pre_bash_self="$PWD/$_pre_bash_self"
SCRIPT_DIR="${_pre_bash_self%/.claude/hooks/pre-bash-combined.sh}"
if [[ -n "${BATS_TEST_FILENAME:-}" && -n "${GUARD14_BATS_PROJECT_ROOT:-}" ]]; then
    SCRIPT_DIR="$GUARD14_BATS_PROJECT_ROOT"
fi
unset _pre_bash_self

# Guard14's boundary suite exercises this combined-hook entry point dozens of
# times.  Let that suite skip unrelated guards while still using the exact
# production Guard14 implementation below.  BATS_TEST_FILENAME makes the
# override unavailable in agent sessions even if the environment leaks.
run_guard14() {
    if [[ ! -f "$SCRIPT_DIR/scripts/lib/guard14_db_trust_classify.sh" ]]; then
        echo "BLOCK [Guard14]: DB接続分類器(scripts/lib/guard14_db_trust_classify.sh)が見つからない。fail-closedのため全DB関連コマンドをBLOCKする。" >&2
        return 2
    fi
    # shellcheck source=scripts/lib/guard14_db_trust_classify.sh
    source "$SCRIPT_DIR/scripts/lib/guard14_db_trust_classify.sh"
    local classification
    if ! classification="$(guard14_classify "$payload" "$command")"; then
        echo "BLOCK [Guard14]: DB接続分類器(guard14_classify)の実行に失敗した。fail-closedのためBLOCKする。" >&2
        return 2
    fi
    if [[ "$classification" != "not_connection" && "$classification" != "connection:local_ephemeral" ]]; then
        echo "BLOCK [Guard14]: DB直接接続禁止(判定=${classification:-classification_error})。/db-checkスキルを使え(skills/db-check/SKILL.md)。2ステップ: (1)python3 scripts/db_capability_launcher.py --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --prepare-only --credential-source-file backend/.env --credential-file /tmp/dm-signal-db-chk.env (2)printf 'SELECT ...' | python3 scripts/db_capability_launcher.py --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce \$(date +%s)-readonly --credential-file /tmp/dm-signal-db-chk.env。localhost/127.0.0.1/::1/Unix socket/:memory:、または設定済みproject配下の実在SQLiteへ literal file URI + mode=ro + uri=True で接続する場合は自動許可対象。" >&2
        return 2
    fi
}

if [[ "${GUARD14_BATS_ONLY:-0}" == "1" && -n "${BATS_TEST_FILENAME:-}" ]]; then
    run_guard14
    exit 0
fi

# All state-changing Bash commands in this repository consume the same
# per-prompt three-layer evidence as Write/Edit. The verifier has a narrow
# read-only allowlist so the preflight search itself cannot deadlock.
if [[ ! -x "$SCRIPT_DIR/scripts/hooks/three_layer_preflight.sh" ]]; then
    emit_deny "BLOCK: 三層preflight scriptが欠落。状態変更Bashをfail-closedで停止"
fi
# bats-core exports BATS_TEST_FILENAME into every test process; a real agent
# session never has it set. Test payloads are synthetic and no
# UserPromptSubmit ever issues evidence for them, so enforcing this check
# here would fail every hook-dispatch test instead of exercising the guard
# actually under test. three_layer_preflight.sh's own tests call verify()
# directly (bypassing this dispatcher) with crafted evidence, so they are
# unaffected by this bypass; the fail-closed check above still runs.
# 復旧コマンド(証跡発行 three_layer_preflight.sh issue)自体は fail-closed 下でも常に通す。
# これを弾くと証跡を再発行できずBashが完全ロックアウトするデッドロックになる
# (2026-07-21 verify fail-closed復元 bcfe6c1f8 で顕在化。fail-open時は verify が常に0で隠れていた。
#  hookメッセージが約束する『issueはallowlist済み』の実体化)。
if [[ "$command" != *three_layer_preflight.sh*issue* ]] \
   && [[ -z "${BATS_TEST_FILENAME:-}" ]] \
   && ! bash "$SCRIPT_DIR/scripts/hooks/three_layer_preflight.sh" verify "Bash" "" "$command" >/dev/null 2>&1; then
    emit_deny "BLOCK: 三層preflight証跡なし/無効。UserPromptSubmitごとに記憶DB・semantic・Obsidian検索を完了せよ。復旧: bash scripts/hooks/three_layer_preflight.sh issue \"<今の作業内容1行>\" を実行せよ(証跡発行コマンド自体はallowlist済みでBLOCK中も実行可能)"
fi

mark_memory_or_gist_numeric_flags() {
    local agent_id state_dir
    agent_id="${TMUX_AGENT_ID:-}"
    if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
        agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    [[ "$agent_id" == "shogun" ]] || return 0
    state_dir="${SHOGUN_STATE_DIR:-/tmp}"
    mkdir -p "$state_dir" 2>/dev/null || true

    if [[ "$command" =~ (^|[[:space:]/])(memory_db_query|semantic_search)\.sh([[:space:]]|$) ]]; then
        : > "$state_dir/shogun_memory_search_seen_${agent_id}" 2>/dev/null || true
    fi

    [[ "$command" == *"gh gist edit"* ]] || return 0
    if [[ "$command" =~ [0-9][0-9,]*([.][0-9]+)?[[:space:]]*(件|体|個|名|枚|冊|台|本|通|種|パターン|%|％|円|万円|億|兆|倍|秒|分|時間|日|ヶ月|年) ]]; then
        : > "$state_dir/shogun_numeric_tool_output_${agent_id}" 2>/dev/null || true
        return 0
    fi
    COMMAND_FOR_GIST_NUMERIC="$command" python3 - "$state_dir/shogun_numeric_tool_output_${agent_id}" <<'PY' 2>/dev/null || true
import os
import re
import shlex
import sys
from pathlib import Path

command = os.environ.get("COMMAND_FOR_GIST_NUMERIC", "")
flag = Path(sys.argv[1])
number_unit_re = re.compile(r"(?:\d[\d,]*(?:\.\d+)?|\d+(?:\.\d+)?)\s*(?:件|体|個|名|枚|冊|台|本|通|種|パターン|%|％|円|万円|億|兆|倍|秒|分|時間|日|ヶ月|年)")
try:
    tokens = shlex.split(command)
except ValueError:
    tokens = []
for token in tokens:
    path = Path(token)
    if not path.is_file() or path.stat().st_size > 262144:
        continue
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        continue
    if number_unit_re.search(text):
        flag.write_text("", encoding="utf-8")
        break
PY
}

mark_memory_or_gist_numeric_flags

mark_shogun_verification_action_count() {
    local agent_id state_dir count_file
    agent_id="${TMUX_AGENT_ID:-}"
    if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
        agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    [[ "$agent_id" == "shogun" ]] || return 0
    [[ -n "${command:-}" ]] || return 0
    if [[ "$command" =~ (^|[[:space:]/])(memory_db_query|semantic_search)\.sh([[:space:]]|$) ]] \
        || [[ "$command" =~ (^|[[:space:]/])(rg|grep|bats|db-check)([[:space:]]|$) ]] \
        || [[ "$command" =~ tmux[[:space:]].*capture-pane ]]; then
        state_dir="${SHOGUN_STATE_DIR:-/tmp}"
        mkdir -p "$state_dir" 2>/dev/null || true
        count_file="$state_dir/shogun_verification_action_count_${agent_id}"
        printf '1\n' >> "$count_file" 2>/dev/null || true
    fi
}

mark_shogun_verification_action_count

knowledge_grep_query() {
    local cache_dir cache_key cache_file now last ttl query

    ttl="${PRE_BASH_KNOWLEDGE_QUERY_CACHE_SEC:-300}"
    if [[ "$ttl" =~ ^[0-9]+$ && "$ttl" -gt 0 ]]; then
        cache_dir="${PRE_BASH_KNOWLEDGE_QUERY_CACHE_DIR:-/tmp/pre_bash_knowledge_query_cache}"
        cache_key="$(printf '%s' "$command" | cksum | awk '{print $1}')"
        cache_file="$cache_dir/${cache_key}.query"
        now="$(date +%s)"
        last="$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
        if [ $((now - last)) -lt "$ttl" ]; then
            cat "$cache_file" 2>/dev/null || true
            return 0
        fi
    fi

    query="$(COMMAND="$command" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import os
import sys

command = os.environ.get("COMMAND", "")
sys.path.insert(0, os.path.join(os.environ["PROJECT_ROOT"], "scripts", "lib"))
try:
    from shell_command_segments import segment_tokens
except ModuleNotFoundError:
    # Isolated hook copies may intentionally omit optional knowledge-query
    # helpers.  Leave the query empty so command-specific fail-closed guards
    # (notably GA-231's agent_config check) can still run and emit exit 2.
    print("")
    raise SystemExit(0)
knowledge_roots = ("context", "docs", "projects", "memory")
infra_roots = ("scripts/gates/", "scripts/hooks/", ".claude/hooks/")


def normalize_tokens(tokens: list[str]):
    while tokens and "=" in tokens[0] and not tokens[0].startswith("-") and tokens[0].split("=", 1)[0].isidentifier():
        tokens = tokens[1:]
    if tokens and tokens[0] == "timeout":
        tokens = tokens[2:] if len(tokens) > 2 and tokens[1].replace(".", "", 1).isdigit() else tokens[1:]
    if tokens and tokens[0] == "command":
        tokens = tokens[1:]
    return tokens


def is_knowledge_path(token: str) -> bool:
    clean = token.strip("'\"")
    clean = clean[2:] if clean.startswith("./") else clean
    root = clean.split("/", 1)[0]
    return root in knowledge_roots


def is_infra_path(token: str) -> bool:
    clean = token.strip("'\"")
    clean = clean[2:] if clean.startswith("./") else clean
    return any(clean.startswith(root) for root in infra_roots)


def extract_query(tokens: list[str], tool_index: int) -> str:
    tool = os.path.basename(tokens[tool_index])
    query = ""
    i = tool_index + 1
    while i < len(tokens):
        tok = tokens[i]
        if tok in ("-e", "--regexp", "--pattern") and i + 1 < len(tokens):
            return tokens[i + 1]
        if tok in ("-f", "--file", "-m", "--max-count", "-A", "-B", "-C", "--context") and i + 1 < len(tokens):
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        if not is_knowledge_path(tok):
            query = tok
        break
    return query


for segment in segment_tokens(command) or []:
    tokens = normalize_tokens(segment)
    for idx, token in enumerate(tokens):
        if os.path.basename(token) not in {"grep", "rg"}:
            continue
        if any(is_infra_path(tok) for tok in tokens[idx + 1:]):
            continue
        if not any(is_knowledge_path(tok) for tok in tokens[idx + 1:]):
            continue
        query = extract_query(tokens, idx)
        if query:
            print(query)
            raise SystemExit(0)
raise SystemExit(0)
PY
)"
    if [[ -n "${query:-}" && "$ttl" =~ ^[0-9]+$ && "$ttl" -gt 0 ]]; then
        mkdir -p "$cache_dir" 2>/dev/null || true
        printf '%s\n' "$query" > "$cache_file" 2>/dev/null || true
    fi
    printf '%s\n' "$query"
}

emit_three_layer_digest_once() {
    # 三層preflightは「証跡の存在」を強制するが「読むこと」を強制しない形骸化バグ
    # (2026-08-01殿指摘: 作業前三層確認の実効が消えている)。既存の証跡ストアを
    # 唯一の正本として、同一promptにつき一度だけ検索結果要点をツール実行画面へ
    # 再注入し、読まずに作業が進まない構造にする。printしたら0、対象外なら1を返す。
    local agent pane safe_key ev_file marker prompt_hash
    agent="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    agent="${agent:-unknown}"
    pane="${TMUX_PANE:-default}"
    safe_key="${agent}_${pane}"
    safe_key="${safe_key//[^A-Za-z0-9_.-]/_}"
    ev_file="$SCRIPT_DIR/logs/preaction_memory/evidence_${safe_key}.json"
    [[ -r "$ev_file" ]] || return 1
    prompt_hash="$(EV_FILE="$ev_file" python3 -c 'import json,os;print(json.load(open(os.environ["EV_FILE"])).get("prompt_hash","")[:16])' 2>/dev/null || true)"
    [[ -z "$prompt_hash" ]] && return 1
    marker="/tmp/three_layer_digest_${safe_key}_${prompt_hash}"
    [[ -e "$marker" ]] && return 1
    : > "$marker" 2>/dev/null || true
    EV_FILE="$ev_file" python3 - <<'PY'
import json
import os

try:
    ev = json.load(open(os.environ["EV_FILE"]))
except Exception:
    raise SystemExit(0)
def clip(key, n=300):
    return (ev.get(key) or "").replace("\n", " ")[:n]
message = (
    "★三層記憶ダイジェスト(preflight証跡より・本prompt初回のみ): 作業前に読め。[MEM:]引用にはこの実結果を使え。\n"
    f"query={ev.get('memory_query','')!r} status={ev.get('status','')}\n"
    f"- memory_db({ev.get('memory_timestamp','')}): {clip('memory_top')}\n"
    f"- semantic({ev.get('semantic_timestamp','')}): {clip('semantic_top', 200)}\n"
    f"- obsidian({ev.get('obsidian_timestamp','')}): {clip('obsidian_top', 200)}"
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": message}}, ensure_ascii=False))
PY
    return 0
}

emit_memory_db_for_knowledge_grep() {
    local query agent_id hash_file now last rows sql query_sql agent_sql like_sql
    local rows_cache_dir rows_cache_file db_file db_fingerprint cached_fingerprint tmp_cache

    if emit_three_layer_digest_once; then
        return 0
    fi

    case "$command" in
        *grep*|*rg*) ;;
        *) return 0 ;;
    esac
    case "$command" in
        *context/*|*docs/*|*projects/*|*memory/*) ;;
        *) return 0 ;;
    esac

    query="$(knowledge_grep_query || true)"
    [[ -z "$query" ]] && return 0

    agent_id="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    [[ -z "$agent_id" ]] && agent_id="unknown"

    hash_file="/tmp/pre_bash_memory_inject_$(printf '%s' "${agent_id}|${query}" | cksum | awk '{print $1}')"
    now="$(date +%s)"
    last="$(stat -c %Y "$hash_file" 2>/dev/null || echo 0)"
    if [ $((now - last)) -lt "${PRE_BASH_MEMORY_INJECT_DEBOUNCE_SEC:-30}" ]; then
        return 0
    fi
    : > "$hash_file" 2>/dev/null || true

    query_sql="${query//\'/\'\'}"
    agent_sql="${agent_id//\'/\'\'}"
    like_sql="%${query_sql}%"
    sql="SELECT ts || ' | ' || substr(summary,1,180) FROM events WHERE agent='lord' AND target='${agent_sql}' AND (summary LIKE '${like_sql}' OR detail LIKE '${like_sql}') ORDER BY ts DESC LIMIT 5;"
    # The same warm grep is common within one prompt. Cache only while the
    # SQLite DB/WAL fingerprint is unchanged, so repeated hook invocations do
    # not repay WSL process+SQLite startup without hiding newly written rows.
    rows_cache_dir="${PRE_BASH_MEMORY_ROWS_CACHE_DIR:-/tmp/pre_bash_memory_rows_cache}"
    rows_cache_file="$rows_cache_dir/$(printf '%s' "${agent_id}|${query}" | cksum | awk '{print $1}').rows"
    db_file="${MEMORY_DB_QUERY_DB:-${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}}"
    db_fingerprint="$(stat -c '%Y:%s' "$db_file" 2>/dev/null || true)|$(stat -c '%Y:%s' "${db_file}-wal" 2>/dev/null || true)"
    cached_fingerprint="$(sed -n '1p' "$rows_cache_file" 2>/dev/null || true)"
    if [[ -n "$db_fingerprint" && "$cached_fingerprint" == "$db_fingerprint" ]]; then
        rows="$(sed '1d' "$rows_cache_file" 2>/dev/null || true)"
    else
        local _db_rc=0
        rows="$(timeout "${PRE_BASH_MEMORY_DB_TIMEOUT_SEC:-5}" bash "$SCRIPT_DIR/scripts/memory_db_query.sh" "$sql" 2>/dev/null)" || _db_rc=$?
        # Only publish cache on success (rc=0). Timeout (rc=124) or error
        # leaves last-known-good cache intact to avoid cache poisoning.
        if [[ $_db_rc -eq 0 ]]; then
            mkdir -p "$rows_cache_dir" 2>/dev/null || true
            tmp_cache="$(mktemp "$rows_cache_dir/.rows.XXXXXX" 2>/dev/null || true)"
            if [[ -n "$tmp_cache" ]]; then
                { printf '%s\n' "$db_fingerprint"; printf '%s\n' "$rows"; } > "$tmp_cache"
                mv "$tmp_cache" "$rows_cache_file" 2>/dev/null || true
            fi
        elif [[ -r "$rows_cache_file" ]]; then
            # Fall back to last-known-good cache on timeout/error
            rows="$(sed '1d' "$rows_cache_file" 2>/dev/null || true)"
        fi
    fi
    [[ -z "$rows" ]] && rows="該当なし (agent=lord target=${agent_id})"
    INJECT_QUERY="$query" INJECT_AGENT="$agent_id" INJECT_ROWS="$rows" python3 - <<'PY'
import json
import os

query = os.environ.get("INJECT_QUERY", "")
agent = os.environ.get("INJECT_AGENT", "")
rows = os.environ.get("INJECT_ROWS", "")
message = (
    "★memory-db自動注入: knowledge grep/rg検知。"
    f" query={query!r} target={agent!r} agent='lord'のみ\n"
    f"{rows}"
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": message}}, ensure_ascii=False))
PY
}

destructive_approval_reason() {
    local conversation_file="${PRE_BASH_LORD_CONVERSATION_FILE:-$SCRIPT_DIR/queue/lord_conversation.jsonl}"
    COMMAND="$command" LORD_CONVERSATION_FILE="$conversation_file" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import json
import os
import re
import sys

command = os.environ.get("COMMAND", "")
conversation_file = os.environ.get("LORD_CONVERSATION_FILE", "")
project_root = os.path.realpath(os.environ.get("PROJECT_ROOT", "."))
sys.path.insert(0, os.path.join(project_root, "scripts", "lib"))
from shell_command_segments import segment_tokens


def destructive_families(cmd: str) -> list[str]:
    families: list[str] = []
    for tokens in segment_tokens(cmd) or []:
        if len(tokens) < 2 or os.path.basename(tokens[0]) != "git":
            continue
        sub = tokens[1]
        args = tokens[2:]
        if sub == "push" and "--force-with-lease" in args:
            families.append("force-with-lease")
        if sub == "reset" and "--hard" in args:
            families.append("reset-hard")
        if sub == "clean":
            for tok in args:
                if tok == "--force" or (tok.startswith("-") and "f" in tok[1:] and tok != "-n"):
                    families.append("git-clean-force")
                    break
    return families


families = destructive_families(command)
if not families:
    raise SystemExit(0)

approval_keywords = (
    "承認", "許可", "実行してよい", "実行して良い", "やってよい", "やって良い",
    "してよい", "して良い", "OK", "ok", "approved", "approve", "allowed",
)
family_keywords = {
    "force-with-lease": ("force-with-lease", "force with lease", "force push", "強制push", "強制プッシュ", "push", "プッシュ"),
    "reset-hard": ("reset --hard", "reset hard", "reset", "リセット"),
    "git-clean-force": ("git clean", "clean -f", "clean --force", "clean", "クリーン"),
}


def entry_text(entry: dict) -> str:
    return " ".join(
        str(entry.get(key, ""))
        for key in ("detail", "summary", "content", "message", "text")
    )


approved = False
if conversation_file and os.path.exists(conversation_file):
    try:
        with open(conversation_file, encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    entry = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if entry.get("direction") != "inbound":
                    continue
                entry_target = str(entry.get("target", "")).strip()
                if entry_target and entry_target != os.environ.get("PROMPT_STATE_AGENT_ID", "shogun"):
                    continue
                text = entry_text(entry)
                if not any(keyword in text for keyword in approval_keywords):
                    continue
                for family in families:
                    if any(keyword in text for keyword in family_keywords[family]) or "破壊的" in text or "destructive" in text.lower():
                        approved = True
                        break
                if approved:
                    break
    except OSError:
        approved = False

if not approved:
    print(
        "D010: destructive git operation requires explicit inbound Lord approval "
        "in queue/lord_conversation.jsonl"
    )
PY
}

# === Guard 0: filter-repo working tree destruction prevention (cmd_1881 incident) ===
# コマンド呼出し位置(行頭 or ;|&&||| の後)のみマッチ。引数内の文字列は無視。
# 旧: payload全文+command全文マッチ→report_field_set.sh引数で誤発火(cmd_2397事故)
if [[ -n "$command" && "$command" =~ (^|[\;\&\|])[[:space:]]*(git[[:space:]]+filter-repo|git-filter-repo) ]]; then
    emit_deny "WARNING: git-filter-repo deletes files from WORKING TREE too, not just git history. Back up large files BEFORE running."
fi

# === Guard 0.5: intentional symlink replacement warning ===
# queue/inbox is intentionally a symlink for CLI memory/inbox integration.
# Replacing it with a real directory silently breaks notification delivery.
# Provenance: cmd_3453, 2026-06-20 inbox symlink replacement regression.
if [[ -n "${command:-}" && "$command" == *'queue/inbox'* ]]; then
    if [[ "$command" =~ (^|[\;\&\|])[[:space:]]*(rm|unlink|mv|mkdir|cp)[[:space:]] ]]; then
        echo "WARN: queue/inbox is an intentional symlink for CLI memory/inbox integration. Do not replace it with a real directory; verify with 'ls -ld queue/inbox' before changing." >&2
    fi
fi

# === Guard 1: no-verify + hook bypass detection (G3: extended beyond commit-only) ===
# GA-220: DM-Signal docs/research commitは、staged blob fingerprintと本陣context reflux証跡が
# 一致しなければ直接git commit経路でも公開前にBLOCKする。read-only commandには非発火。
# cmd_karo_hotfix_guard1_git_commit_tokenizer_202607121350: 旧実装は"$command"全文への
# *git*/*commit*部分文字列andだった。report_field_set.shのlesson_candidate/result本文に
# "git"と"committed"という単語がプレーンテキストで含まれるだけの無関係commandでも発火し、
# BLOCKする事故が実測で発生した(3/3再現)。根因の一端はGuard14と同根: ファイル冒頭のawk抽出は
# JSON \"エスケープの早期break回避はするが実際のunescapeはしないため、$commandにはbash quote
# -splicing(例: 'foo'"'"'s')のバックスラッシュが混入し、shlex token化がquote境界を誤認識する。
# Guard14と同じ方針で、判定本体は生payload($payload)をjson.loadsしてtool_input.commandを
# 正規復元してから使う(classifier側でregexパッチしない)。
# Guard0(行頭/区切り文字直後の実行位置のみマッチ。引数内の文字列は無視)と同じ設計原則を踏襲し、
# Guard14と同じ shlex.shlex(posix=True, punctuation_chars=";&|") でquote-awareにtoken化した上で
# 演算子token(&&/||/;/|/単独&)でsegmentへ分割し、各segmentの先頭が実行位置の"git"(+ 任意の
# -C <path>)+ "commit" subcommandであるかのみを見る。全体解析が失敗した場合のみ、Guard0と同じ
# 行頭/区切り文字直後の"git"出現有無でfail-closed可否を判定する(個別message allowlist禁止)。
if [[ -n "${command:-}" && "$command" == *git* && "$command" == *commit* ]]; then
    # A standalone hook copy may omit both shared parsing and role ontology.
    # Do not crash in the parser import before GA-231 can express its intended
    # fail-closed contract with Codex-safe exit 2.
    if [[ ! -r "$SCRIPT_DIR/scripts/lib/shell_command_segments.py" && ! -r "$SCRIPT_DIR/scripts/lib/agent_config.sh" ]]; then
        emit_deny "BLOCK(GA-231): agent role config(scripts/lib/agent_config.sh)が欠落。direct git commitをfail-closedで停止"
    fi
    _guard1_is_git_commit="$(HOOK_PAYLOAD_JSON="$payload" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.environ["PROJECT_ROOT"], "scripts", "lib"))
from shell_command_segments import segment_tokens


def is_git_commit(cmd):
    segments = segment_tokens(cmd)
    if segments is None:
        # 構造判定: 行頭 or 区切り文字直後がgitで始まる場合のみ疑わしいとみなしfail-closed。
        # それ以外(report/message本文の引用符崩れ等)は無関係commandとして安全にskipする。
        return bool(re.search(r"(^|[;&|\n])\s*git(\s|$)", cmd))
    for seg in segments:
        if not seg or os.path.basename(seg[0]) != "git":
            continue
        idx = 1
        if len(seg) > 2 and seg[1] == "-C":
            idx = 3
        if idx < len(seg) and seg[idx] == "commit":
            return True
    return False


def recover_command():
    payload = os.environ.get("HOOK_PAYLOAD_JSON", "")
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, TypeError):
        return None
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    cmd = tool_input.get("command")
    return cmd if isinstance(cmd, str) else None


_recovered = recover_command()
if _recovered is None:
    # payload復元不能はfail-closed(判定不能な状態を安全側に倒す)
    print("yes")
else:
    print("yes" if is_git_commit(_recovered) else "no")
PY
)"
    if [[ "$_guard1_is_git_commit" == "yes" ]]; then
        # Agent roles are operational ontology, but only GA-231 needs them.
        # Loading this dependency earlier makes unrelated guards crash when an
        # isolated hook copy intentionally omits agent_config.sh.
        if [[ ! -r "$SCRIPT_DIR/scripts/lib/agent_config.sh" ]]; then
            emit_deny "BLOCK(GA-231): agent role config(scripts/lib/agent_config.sh)が欠落。direct git commitをfail-closedで停止"
        fi
        # shellcheck source=scripts/lib/agent_config.sh
        if ! source "$SCRIPT_DIR/scripts/lib/agent_config.sh"; then
            emit_deny "BLOCK(GA-231): agent role config(scripts/lib/agent_config.sh)の読込に失敗。direct git commitをfail-closedで停止"
        fi
        _guard1_agent_id="${TMUX_AGENT_ID:-}"
        if [[ -z "$_guard1_agent_id" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
            _guard1_agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
        fi
        case " $(get_ninja_names) " in
            *" $_guard1_agent_id "*)
                emit_deny "BLOCK(GA-231): 忍者のgit commit直書きは禁止。/ninja-commit または bash scripts/ninja_scope_commit.sh を使い、共有indexの他者stageをcommitから分離せよ"
                ;;
        esac
        # cmd_karo_impl_commander_scope_commit_20260725 (AC1): 指揮官(将軍・家老・軍師)の
        # D0 commitはninja_scope_commit.shの保護対象外だった(GA-231はninjaのみ判定)。
        # 実害: 将軍の設計書commit 0f1c3ea65が才蔵のstage済みdead module削除922行を巻き込んだ。
        # 忍者はtask YAML由来のplanned_pathsがあるが指揮官にはその前提がないため、明示pathspec
        # (-- <path> [path ...])でscopeを与える経路として同一scriptを使わせる。
        case " $(get_commander_names) " in
            *" $_guard1_agent_id "*)
                emit_deny "BLOCK(GA-231c): 指揮官のgit commit直書きは禁止。他者のstage済み変更を巻き込む事故を防ぐため bash scripts/ninja_scope_commit.sh -m \"<message>\" -- <path1> [path2 ...] で変更pathを明示してcommitせよ(task YAMLは不要。忍者と同じscriptを指揮官も直接使える)"
                ;;
        esac
        if ! bash "$SCRIPT_DIR/scripts/dm_signal_research_reflux_guard.sh" check-command "$command"; then
            emit_deny "BLOCK(GA-220): DM-Signal research commit requires matching context reflux fingerprint"
        fi
    fi
    unset _guard1_is_git_commit _guard1_agent_id
fi

# Outer fast-check: --no-verify, HUSKY=0, or potential git commit -n
if [[ "$payload" == *'--no-verify'* || "$payload" == *'HUSKY=0'* ]] || \
   [[ "$payload" == *'commit'* && "$payload" == *' -n '* ]]; then
    if [[ -n "$command" ]]; then
        # --no-verify on any git command (push/merge/rebase/cherry-pick, not just commit)
        if [[ "$command" =~ git[[:space:]] && "$command" == *'--no-verify'* ]]; then
            emit_deny "BLOCKED: --no-verify is forbidden on git commands. Fix hooks, do not bypass them."
        fi
        # git commit -n (short alias for --no-verify, commit only — -n means different things for other subcommands)
        # 貪欲FP族対策(2026-06-10): 全文regexはメッセージ内の「bash -n」等を誤検知(同日実測1件)。
        # shlexトークン化でcommitトークン以降・コマンド区切り前の実引数トークンのみ検査
        # (引用句内文字列は1トークンに畳まれ除外される)。解析失敗時はBLOCK=fail-closed。FN追加ゼロ。
        if [[ "$command" =~ git[[:space:]]+commit[[:space:]] && "$command" =~ [[:space:]]-n([[:space:]]|$) ]]; then
            _commit_n_verdict=$(COMMIT_N_CMD="$command" python3 - <<'PYGUARD' 2>/dev/null || echo BLOCK
import os, shlex, json
cmd = os.environ.get("COMMIT_N_CMD", "")
# awk抽出はJSONエスケープ(\" \n等)を温存する仕様(cmd_2075)。shlex前にデコードする。
try:
    cmd = json.loads('"' + cmd + '"')
except Exception:
    pass  # 非エスケープ形はそのまま
try:
    toks = shlex.split(cmd)
except ValueError:
    print("BLOCK"); raise SystemExit
SEP = {"&&", "||", ";", "|"}
block = False
for i, t in enumerate(toks):
    if t == "commit":
        for k in range(i + 1, len(toks)):
            if toks[k] in SEP:
                break
            if toks[k] == "-n":
                block = True
print("BLOCK" if block else "OK")
PYGUARD
)
            if [[ "$_commit_n_verdict" != "OK" ]]; then
                emit_deny "BLOCKED: git commit -n (--no-verify) is forbidden. Fix hooks, do not bypass them."
            fi
        fi
        # Hook bypass via environment variables
        if [[ "$command" == *'HUSKY=0'* ]]; then
            emit_deny "BLOCKED: HUSKY=0 (hook bypass) is forbidden. Fix hooks, do not bypass them."
        fi
    fi
fi

# === Guard 2: yaml-dump ===
if [[ "$payload" == *'yaml.dump'* || "$payload" == *'yaml.safe_dump'* ]]; then
    if [[ -n "${command:-}" ]]; then
        # 判定対象はraw text中のpythonという単語ではなく、実際に起動される
        # segment先頭argvがPythonである場合だけに限る。rg/grepの検索語に
        # Python書込例が含まれるだけの読取コマンドを実操作と誤認しない。
        _guard2_runs_python="$(COMMAND="$command" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.path.join(os.environ["PROJECT_ROOT"], "scripts", "lib"))
from shell_command_segments import segment_tokens

segments = segment_tokens(os.environ.get("COMMAND", ""))
if segments is None:
    print("yes")  # malformed shell is fail-closed when sensitive text exists
else:
    python_names = {"python", "python3", "python.exe", "python3.exe"}
    print("yes" if any(segment and segment[0].rsplit("/", 1)[-1] in python_names for segment in segments) else "no")
PY
)"
        if [[ "$_guard2_runs_python" == "yes" ]]; then
            for pattern in "queue/" "tasks/" "shogun_to_karo" "karo_snapshot" "inbox/" "reports/"; do
                yaml_open_write_pattern="open[[:space:]]*\\([^)]*${pattern}[^)]*,[^)]*[wax+]"
                yaml_redirect_write_pattern="(>+|tee[[:space:]]+)[[:space:]]*[^;&|[:space:]]*${pattern}"
                if [[ "$command" =~ $yaml_open_write_pattern ]] || [[ "$command" =~ $yaml_redirect_write_pattern ]]; then
                    emit_deny "BLOCKED: yaml.dump on operational YAML is forbidden (data loss risk). Use: bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>"
                fi
            done
        fi
        unset _guard2_runs_python
    fi
fi

# === Guard 3: report-deny (bash redirect/tee to report YAML) ===
if [[ "$payload" == *'queue/reports/'* ]]; then
    if [[ -n "${command:-}" && "$command" != *'report_field_set.sh'* ]]; then
        redirect_pattern='>+[[:space:]]*[^ ]*queue/reports/[^ ]*\.yaml'
        tee_pattern='tee[[:space:]].*queue/reports/[^ ]*\.yaml'
        python3_pattern='python3?.*open[[:space:]]*\([^)]*queue/reports/[^)]*\.yaml[^)]*,[^)]*[wax+]'
        python_path_write_pattern='python3?.*(Path[[:space:]]*\([^)]*queue/reports/[^)]*\.yaml[^)]*\)|[^[:space:];]+)[[:space:]]*\.(write_text|write_bytes)[[:space:]]*\('
        if [[ "$command" =~ $redirect_pattern ]] || [[ "$command" =~ $tee_pattern ]]; then
            emit_deny "報告YAMLへのBashリダイレクト(>/>>/ tee)は禁止。report_field_set.sh経由で書き込みせよ。"
        fi
        if [[ "$command" =~ $python3_pattern ]] || [[ "$command" =~ $python_path_write_pattern ]]; then
            emit_deny "報告YAMLへのpython3 open()直接書込みは禁止。report_field_set.sh経由で書き込みせよ。"
        fi
    fi
fi

# === Guard 3.5: karo_workarounds-deny (bash direct write to workaround log) ===
if [[ "$payload" == *'logs/karo_workarounds.yaml'* ]]; then
    if [[ -n "${command:-}" && "$command" != *'karo_workaround_log.sh'* ]]; then
        wa_redirect_pattern='>+[[:space:]]*[^ ]*logs/karo_workarounds\.yaml'
        wa_tee_pattern='tee[[:space:]].*logs/karo_workarounds\.yaml'
        # 兄弟Guard3(reports)と同型に修正(殿裁定2026-07-23 gate品質バグ即時修正):
        # (a)sed/awkの .* はコマンド境界(;&|)を越えて別ファイル操作+ログ参照を誤結合するため
        #    [^;&|]* に限定 (b)awkは対象ログへのリダイレクト書込のみ(別ファイルへの>は許可)
        #    (c)pythonはopen()に書込モード ,[wax+] がある場合のみ(read open()は許可)
        wa_sed_pattern='(^|[;&|])[[:space:]]*sed[[:space:]][^;&|]*(-i|--in-place)[^;&|]*logs/karo_workarounds\.yaml'
        wa_awk_pattern='awk[[:space:]][^;&|]*>+[[:space:]]*[^ ]*logs/karo_workarounds\.yaml'
        wa_yfs_pattern='(^|[;&|])[[:space:]]*(bash[[:space:]]+)?[^;&|[:space:]]*yaml_field_set\.sh[[:space:]]+logs/karo_workarounds\.yaml'
        wa_python_pattern='python3?[^;&|]*open[[:space:]]*\([^)]*logs/karo_workarounds\.yaml[^)]*,[^)]*[wax+]'
        if [[ "$command" =~ $wa_redirect_pattern ]] || [[ "$command" =~ $wa_tee_pattern ]] \
            || [[ "$command" =~ $wa_sed_pattern ]] || [[ "$command" =~ $wa_awk_pattern ]] \
            || [[ "$command" =~ $wa_yfs_pattern ]] || [[ "$command" =~ $wa_python_pattern ]]; then
            emit_deny "BLOCKED: logs/karo_workarounds.yamlへのBash直接書込み禁止。karo_workaround_log.sh経由で記録せよ。brainwash_checkとALERT経路を迂回させないため。"
        fi
    fi
fi

# === Guard 3.6: queue/tasks-deny (bash direct write to task YAML) ===
# cmd_karo_hotfix_queue_yaml_atomicity_202607110113: queue/tasks/*.yaml は
# queue/reports/ と同様に他エージェント/gateが常時読む共有運用YAML。sed -i/リダイレクト/
# tee/python3 open()での直接書換えはtruncate-writeの一瞬を晒し、読み手側にYAMLError/デコード
# エラーを発生させる(2026-07-11 01:09 kagemaru.yaml破損の実例)。yaml_field_set.sh経由のみ許可する。
if [[ "$payload" == *'queue/tasks/'* ]]; then
    if [[ -n "${command:-}" && "$command" != *'yaml_field_set'* ]]; then
        task_redirect_pattern='>+[[:space:]]*[^ ]*queue/tasks/[^ ]*\.yaml'
        task_tee_pattern='tee[[:space:]].*queue/tasks/[^ ]*\.yaml'
        task_sed_pattern='(^|[;&|])[[:space:]]*sed[[:space:]].*(-i|--in-place).*queue/tasks/[^ ]*\.yaml'
        # Read-only open()/yaml.safe_load() is a normal inspection path.  Deny
        # Python only when the command explicitly requests write capability.
        # Keep this fail-closed for every mutating open mode (w/a/x/+), plus
        # pathlib's direct write helpers.
        task_python_open_write_pattern='python3?.*open[[:space:]]*\([^)]*queue/tasks/[^)]*\.yaml[^)]*,[^)]*[wax+]'
        task_python_open_mode_pattern='python3?.*open[[:space:]]*\([^)]*queue/tasks/[^)]*\.yaml[^)]*,'
        task_python_open_read_mode_pattern="python3?.*open[[:space:]]*\\([^)]*queue/tasks/[^)]*\\.yaml[^)]*,[[:space:]]*[\"']r(b|t)?[\"'][[:space:]]*\\)"
        task_python_path_write_pattern='python3?.*(Path[[:space:]]*\([^)]*queue/tasks/[^)]*\.yaml[^)]*\)|[^[:space:];]+)[[:space:]]*\.(write_text|write_bytes)[[:space:]]*\('
        if [[ "$command" =~ $task_redirect_pattern ]] || [[ "$command" =~ $task_tee_pattern ]] \
            || [[ "$command" =~ $task_sed_pattern ]] \
            || [[ "$command" =~ $task_python_open_write_pattern ]] \
            || { [[ "$command" =~ $task_python_open_mode_pattern ]] \
                && [[ ! "$command" =~ $task_python_open_read_mode_pattern ]]; } \
            || [[ "$command" =~ $task_python_path_write_pattern ]]; then
            emit_deny "BLOCKED: queue/tasks/へのBash直接書換え(sed -i/リダイレクト/tee/python3 open())は禁止。bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value> 経由で書き込みせよ。非atomicな公開は共有readerの破損原因となる。"
        fi
    fi
fi

# === Guard 3.7: GA-228 task-YAML mixed-stage prevention ===
# GA-408 detects this only during git commit, after a mixed index has already
# been created and the failure recorder has fired.  Simulate git add against a
# temporary index here, so the wrong stage is never created in the first place.
if [[ -n "${command:-}" && "$command" == *git* && "$command" == *add* ]]; then
    if ! _ga228_stage_guard_output="$(python3 "$SCRIPT_DIR/scripts/hooks/git-stage-guard.py" "$command" 2>&1)"; then
        emit_deny "${_ga228_stage_guard_output}"
    fi
fi

# === Guard 4: shogun_to_karo.yaml status manipulation block ===
# cmd_2134事故: 将軍がsed/python regexでstatusをdraft→pending→delegatedに強制変更し
# cmd_delegate.shのgate迂回路を開けた。statusの変更はEdit tool(手動確認付き)のみ許可。
# sed/awk/python regexによるshogun_to_karo.yamlのstatus操作はBLOCK。
if [[ -n "${command:-}" ]]; then
    if [[ "$command" == *'shogun_to_karo'* ]]; then
        # 2026-09-01: 読み取り専用の pipeline(grep … | sed -E / awk '{print}' / python で
        # 読むだけ)まで 'sed '/'awk ' の部分文字列で BLOCK していた(将軍が同セッションで 3 回)。
        # 迂回事故(cmd_2134)の実体は「書き戻し」なので、書ける形だけを止める:
        # sed -i / --in-place、> >> tee で当該 yaml へ出力、python の write/'w' open。
        _g4_write=false
        _g4_re_sed='sed[[:space:]]+(-[A-Za-z]*i|--in-place)'
        _g4_re_redir='(>|tee[[:space:]])[^|]*shogun_to_karo'
        _g4_re_pywrite='(\.write\(|open\([^)]*["'"'"'][wa]["'"'"'])'
        if [[ "$command" =~ $_g4_re_sed ]]; then _g4_write=true; fi
        if [[ "$command" =~ $_g4_re_redir ]]; then _g4_write=true; fi
        if [[ "$command" == *"re.sub"* || "$command" == *".replace("* || "$command" == *'awk '* ]] \
            && [[ "$command" =~ $_g4_re_pywrite ]]; then
            _g4_write=true
        fi
        if [[ "$_g4_write" == true ]]; then
            emit_deny "BLOCK: shogun_to_karo.yamlへのsed/regex操作は禁止。変更はEdit tool、読み取りはRead tool(offset/limit指定)を使え。status遷移gateの迂回を防ぐため。"
        fi
    fi
fi

# === Guard 5 removed (cmd_karo_ci_red_remaining_unit_202607151950) ===
# Guard 5 matched bats/tests-unit as raw substrings/regex against the full
# $payload and $command text, so a quoted argument merely *mentioning*
# "bats tests/unit/*.bats" (e.g. an inbox_write.sh message describing this
# very bug) was falsely BLOCKed even though no bats process was invoked.
# Guard 17 below already detects the identical full-dir/glob "bats
# tests/unit" cases through argv-position-aware parsing
# (heavy_job_classify.py: prog must actually be "bats" in some shell
# segment), which is a strict superset of Guard 5's coverage without the
# false-positive surface. Removed rather than patched to eliminate the
# raw-text-matching vector entirely.

# === Guard 5.1: .bats direct shell execution prevention ===
# A .bats file is not a standalone Bash script: invoking it through bash/sh
# bypasses the repository runner's file-mode verdict and PASS/FAIL/SKIP
# accounting. Classify argv positions after quote/heredoc-aware segmentation;
# raw command text would recreate Guard 5's message/heredoc false positives.
if [[ -n "${command:-}" && "$command" == *'.bats'* ]]; then
    # This branch owns the distinct bash/sh <tests/**/*.bats> file-mode
    # boundary. It runs first so malformed shell syntax retains the specific
    # fail-closed Guard 5.1 reason below.
    _bats_direct_path="$({ COMMAND="$command" PYTHONPATH="$SCRIPT_DIR/scripts/lib${PYTHONPATH:+:$PYTHONPATH}" python3 - 2>/dev/null <<'PY'
import os
from pathlib import PurePosixPath

from shell_command_segments import segment_tokens


def is_test_bats(value: str) -> bool:
    normalized = value.replace("\\", "/")
    return normalized.endswith(".bats") and "tests" in PurePosixPath(normalized).parts


segments = segment_tokens(os.environ.get("COMMAND", ""))
if segments is None:
    print("__CLASSIFY_ERROR__")
    raise SystemExit
for tokens in segments:
    if not tokens:
        continue
    index = 0
    if tokens[index] == "env":
        index += 1
        while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
            index += 1
    while index < len(tokens) and "=" in tokens[index] and not tokens[index].startswith(("/", "./")):
        index += 1
    if index >= len(tokens) or PurePosixPath(tokens[index]).name not in {"bash", "sh"}:
        continue
    index += 1
    while index < len(tokens) and tokens[index].startswith("-"):
        # -c consumes command text, not a script pathname.
        if tokens[index] == "-c" or "c" in tokens[index][1:]:
            index = len(tokens)
            break
        if tokens[index] == "--":
            index += 1
            break
        if tokens[index] in {"-o", "-O"}:
            index += 2
            continue
        index += 1
    if index < len(tokens) and is_test_bats(tokens[index]):
        print(tokens[index])
        raise SystemExit
PY
    } || printf '__CLASSIFY_ERROR__';)"
    if [[ "$_bats_direct_path" == "__CLASSIFY_ERROR__" ]]; then
        emit_deny "BLOCK(shell-syntax): shell commandを安全に解析できない。quote/escapeを修正せよ。構文修正後に.bats直実行なら bash scripts/run_tests.sh file <path> を使え。"
    elif [[ -n "$_bats_direct_path" ]]; then
        emit_deny "BLOCK(bats-file-mode): .batsをbash/shで直接実行してはならない。修正: bash scripts/run_tests.sh file ${_bats_direct_path}"
    fi
    unset _bats_direct_path

    # 殿裁定 2026-08-29 00:50『家老自身がテストして再検証は回転速度を落とすバグ』:
    # 家老 pane からの run_tests.sh / bats 実行は ACCEPT の再試験(08-28/29 に 14 回、BATS_CACHE=0 再走 3 回)
    # =fin_c の機械的待ち。判定材料は忍者の test receipt+軍師 LGTM+gate の receipt 検査。
    # E2E/CI 診断だけ KARO_TEST_REASON=e2e|ci_diag を command 内で明示して通す(構造型: 文章規則 karo-operations.md:157 は不発だった)。
    _karo_test_agent="${TMUX_AGENT_ID:-}"
    if [[ -z "$_karo_test_agent" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
        _karo_test_agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ "$_karo_test_agent" == "karo" && "$command" =~ (scripts/run_tests\.sh|bats-exec-|[[:space:]]bats[[:space:]]) \
       && ! "$command" =~ KARO_TEST_REASON=(e2e|ci_diag) ]]; then
        emit_deny "BLOCK(karo-retest): 家老の bats/run_tests 再試験は回転を落とす(殿裁定 2026-08-29 00:50)。ACCEPT は忍者の test receipt(logs/test_receipts、報告 YAML の receipt path/sha)+軍師 LGTM で判定せよ。E2E/CI 診断のみ KARO_TEST_REASON=e2e または ci_diag を command 先頭に付けて実行可。"
    fi
    unset _karo_test_agent

    # The wrapper-aware direct-bats classifier is the single owner of bats
    # executable classification. Keep this call at the Guard 5.1 boundary so
    # Claude and Codex both share the same implementation, and fail closed if
    # the classifier itself cannot complete.
    _direct_bats_guard_output=""
    _direct_bats_guard_rc=0
    if _direct_bats_guard_output="$(printf '%s' "$payload" | bash "$SCRIPT_DIR/scripts/hooks/pre-bash-test-fullrun-guard.sh" 2>&1)"; then
        _direct_bats_guard_rc=0
    else
        _direct_bats_guard_rc=$?
    fi
    if (( _direct_bats_guard_rc != 0 )); then
        _direct_bats_guard_reason="${_direct_bats_guard_output//$'\n'/ }"
        if [[ -z "$_direct_bats_guard_reason" ]]; then
            _direct_bats_guard_reason="BLOCK(bats-classifier): 直接bats実行を安全に分類できない。bash scripts/run_tests.sh file <path> を使え。"
        fi
        emit_deny "$_direct_bats_guard_reason"
    fi
    unset _direct_bats_guard_output _direct_bats_guard_rc _direct_bats_guard_reason
fi

# === Guard 6: capture-pane minimum 30 lines (LK037/LK018: 末尾数行で状態を誤判断する防止) ===
# + LG007: capture-pane=残像リマインダー
if [[ "$payload" == *'capture-pane'* ]]; then
    if [[ -n "${command:-}" && "$command" =~ capture-pane.*-S[[:space:]]+-([0-9]+) ]]; then
        lines="${BASH_REMATCH[1]}"
        if (( lines < 30 )); then
            emit_deny "BLOCK: capture-pane -S -${lines} は不十分。-S -30 以上を使え（末尾${lines}行では忍者の作業状態を見落とす）"
        fi
    fi
    echo "INFO: capture-pane出力は過去の残像。現在の状態はファイルmtime(inbox/task YAML)で確認せよ。" >&2
fi

# === Guard 7: inbox_mark_read without prior Read — prevent stop hook bypass ===
# Why: mark_read before reading inbox content lets agent bypass stop_check_inbox hook
#      without processing messages (confirmed 2026-04-07: karo missed hayate completion)
if [[ "$payload" == *'inbox_mark_read'* ]]; then
    if [[ -n "${command:-}" && "$command" == *'inbox_mark_read.sh'* ]]; then
        mark_agent=""
        if [[ "$command" =~ inbox_mark_read\.sh[[:space:]]+([a-z_]+) ]]; then
            mark_agent="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$mark_agent" ]]; then
            read_log="/tmp/claude_read_log_${mark_agent}.txt"
            inbox_pattern="queue/inbox/${mark_agent}.yaml"
            mark_msg_id=""
            if [[ "$command" =~ inbox_mark_read\.sh[[:space:]]+[a-z_]+[[:space:]]+([^[:space:];&|]+) ]]; then
                mark_msg_id="${BASH_REMATCH[1]}"
            fi
            if [[ -f "$read_log" ]]; then
                recent_reads="$(tail -5 "$read_log" 2>/dev/null || true)"
                if [[ "$recent_reads" != *"$inbox_pattern"* ]]; then
                    if [[ -n "$mark_msg_id" ]]; then
                        echo "[Guard7] WARN: read_logに${inbox_pattern}なし。ただしmsg_id指定の個別既読化はCodex互換のため許可: ${mark_msg_id}" >&2
                    else
                        emit_deny "BLOCK: inbox_mark_read前にRead toolでinboxを読め。中身を確認せずに既読化するとメッセージ処理漏れが発生する。"
                    fi
                fi
            else
                # read_log不在: Codex CLI or 起動直後。BLOCKではなくWARN(所見5: Codex互換)
                echo "[Guard7] WARN: read_log不在(${read_log})。inbox_mark_read前にRead toolでinboxを読むべき" >&2
            fi
        fi
    fi
fi

# === Guard 8: wf_runner.py parallel execution BLOCK (LG025: OOM Kill実証済み) ===
# Quote-aware argv判定。regexは引用文字列の内側から再マッチできるため
# `echo "python3 wf_runner.py"` まで誤BLOCKする。
if [[ "$payload" == *'wf_runner.py'* ]]; then
    if [[ -n "${command:-}" ]] && COMMAND="$command" \
        PYTHONPATH="$SCRIPT_DIR/scripts/lib${PYTHONPATH:+:$PYTHONPATH}" \
        python3 - <<'PY' 2>/dev/null
import os
from pathlib import PurePosixPath
from shell_command_segments import segment_tokens

for segment in segment_tokens(os.environ["COMMAND"]) or []:
    executable = PurePosixPath(segment[0]).name if segment else ""
    if executable in {"python", "python2", "python3"} and any(
        PurePosixPath(token).name == "wf_runner.py" for token in segment[1:]
    ):
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
        emit_deny "BLOCKED: wf_runner.py は並列OOMリスクのため使用禁止。代替: l1_alm_wf_engine.py --csv で1本ずつ直列実行せよ。"
    fi
fi


# === Guard 9: Skill bypass detection (殿裁定2026-05-10: スキル無視はバグ) ===
# 手動操作をBLOCKし、対応スキル使用を強制する (Level 4)
# Note: $command内のcommit message等のテキスト言及を除外するため、
# 実際のファイル操作パターン(cat/echo >> FILE, sed -i FILE)のみ検出
if [[ "$command" =~ (cat|echo|printf)[[:space:]][^\;\&\|]*\>\>[[:space:]]*[^\ \;\&\|]*gunshi_review_log\.yaml ]]; then
    _agent_id="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        emit_deny "BLOCKED: review_log直接追記禁止。/review-bundle スキルを使え (殿裁定: スキル無視はバグ)"
    fi
fi
if [[ "$command" =~ sed[[:space:]]+-i[^\;\&\|]*gunshi_review_log\.yaml ]]; then
    _agent_id="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        emit_deny "BLOCKED: gate_result手動sed禁止。/gate-sync スキルを使え (殿裁定: スキル無視はバグ)"
    fi
fi

# Guard 9b: inbox_writeのmodel_switch type BLOCK (殿裁定2026-06-20: スキル100%使用の仕組み)
# cmd ID・report path・検索語に同じsubstringが含まれるだけでは操作ではない。
# inbox_write.shの独立type tokenとして指定された場合だけBLOCKする。
if [[ "$command" == *inbox_write.sh* ]] &&
   [[ "$command" =~ (^|[[:space:]\"\047=])model_switch([[:space:]\"\047\|\;\&]|$) ]]; then
    emit_deny "BLOCKED: model_switchはスキル経由で実行せよ (殿裁定: スキル無視はバグ)"
fi

# === Guard 10: D0 effect measurement enforcement (覚醒なぜなぜ7回 2026-06-10: commit=仕事の根因) ===
# gunshi_direct_impl通知に数値差分(0-9を含む修正前→修正後パターン)がなければBLOCK
# なぜ7回の根因: D0 commit後→inbox通知の間に「完了感」→計測忘れ。通知時L4で強制
if [[ "$command" == *inbox_write.sh*gunshi_direct_impl* ]]; then
    if ! echo "$command" | grep -qP '[0-9]+.*→.*[0-9]+|[0-9]+件|[0-9]+%'; then
        emit_deny "BLOCKED: D0完了通知に効果計測の数値差分がない。修正前→修正後の数値(例: WARN→OK, 7/10→1/10)を含めよ (覚醒なぜなぜ7回: commit≠仕事)"
    fi
fi

# === Guard 11: bulletin_write action conversion reminder (殿指摘2026-06-10: 出力≠行動) ===
# 掲示板投稿は「出力」であり「行動」ではない。投稿後にコード変更/教訓追記/gate修正まで回せ
if [[ "$command" == *bulletin_write.sh* ]]; then
    echo "[Guard11] INFO(§0.1問い10): 掲示板投稿=出力。行動(コード変更/教訓追記/gate修正)→検証(grep/計測)まで回したか？出力で止まるな" >&2
fi

# === Guard 12: pending_approval commit BLOCK (cmd_3285) ===
# 裁可保留ファイルを含むgit commitをBLOCKする。どの経路のcommitでも保留中ファイルが運ばれない構造
# PENDING_APPROVAL_FILE: テスト時にoverride可能
if [[ -n "${command:-}" && "$command" =~ (^|[[:space:]\;]|&&|\|\|)git[[:space:]]+commit([[:space:]]|$) ]]; then
    _pa_file="${PENDING_APPROVAL_FILE:-$SCRIPT_DIR/queue/pending_approval.yaml}"
    if [[ -f "$_pa_file" ]]; then
        # GUARD12_STAGED_FILES_OVERRIDE: テスト時にgit実行をmockする
        if [[ -n "${GUARD12_STAGED_FILES_OVERRIDE:-}" ]]; then
            _staged_files="$GUARD12_STAGED_FILES_OVERRIDE"
        else
            _staged_files="$(git -C "$SCRIPT_DIR" diff --cached --name-only 2>/dev/null || true)"
        fi
        if [[ -n "$_staged_files" ]]; then
            _pa_block="$(STAGED="$_staged_files" PA_FILE="$_pa_file" python3 - <<'PY'
import os, yaml, sys
staged = set(os.environ.get("STAGED", "").splitlines())
pa_file = os.environ.get("PA_FILE", "")
try:
    with open(pa_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
entries = data.get("entries") or []
for e in entries:
    p = (e.get("path") or "").lstrip("/")
    if p in staged:
        print(p)
        sys.exit(0)
PY
)"
            if [[ -n "$_pa_block" ]]; then
                emit_deny "BLOCK(G12): '$_pa_block' is pending approval. Remove from registry first: bash scripts/pending_approval_set.sh remove '$_pa_block'"
            fi
        fi
    fi
fi

# === Guard 13: respawn-pane直接実行BLOCK (殿命令2026-07-22: CLI種別ミス再発防止) ===
# 根拠: 軍師がrespawn-pane -k直接実行→全忍者にClaude CLI決め打ち→type:codex忍者がClaude化
# 修繕: agent_respawn.sh経由でcli_lookup.shが自動解決。直接respawn-paneは構造的にBLOCK
if [[ "$command" == *respawn-pane* ]] && COMMAND="$command" \
    PYTHONPATH="$SCRIPT_DIR/scripts/lib${PYTHONPATH:+:$PYTHONPATH}" \
    python3 - <<'PY' 2>/dev/null
import os
from pathlib import PurePosixPath
from shell_command_segments import segment_tokens

for segment in segment_tokens(os.environ["COMMAND"]) or []:
    executable = PurePosixPath(segment[0]).name if segment else ""
    if executable == "tmux" and "respawn-pane" in segment[1:]:
        raise SystemExit(0)
raise SystemExit(1)
PY
then
    # ninja_monitor.sh/reset_layout等の内部インフラは除外(既にcli_lookup.sh使用済み)
    if [[ "$command" != *"ninja_monitor"* ]] && [[ "$command" != *"reset_layout"* ]]; then
        emit_deny "BLOCKED: respawn-pane直接実行禁止。bash scripts/agent_respawn.sh <agent_name> を使え（CLI種別を自動解決する）。"
    fi
fi

# === Guard 13.5: CDP direct-command Skill nudge (non-blocking) ===
# CDPを直接叩く前にCDP専用スキル /cdp-browse を起動する正規経路へ誘導する。
# receipt済みなら重複nudgeせず、未receipt時だけFP計測可能なfire logを残す。
if [[ "$command" =~ (cdp_font_probe|remote-debugging|debug[_-]?port) ]] \
    || [[ "$command" =~ curl[[:space:]].*:9222([/[:space:]]|$) ]]; then
    _cdp_skill_log="${SKILL_EXECUTION_LOG_FILE:-$SCRIPT_DIR/logs/skill_execution_log.yaml}"
    _cdp_agent="${SHOGUN_AGENT_ID:-}"
    if [[ -z "$_cdp_agent" && -n "${TMUX_PANE:-}" ]]; then
        _cdp_agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    _cdp_receipt=0
    if [[ -f "$_cdp_skill_log" ]] && awk -v agent="$_cdp_agent" '
        /^- ts:/ { skill=executor=result=used="" }
        /^[[:space:]]+skill:/ { skill=$0; sub(/^[^:]*:[[:space:]]*/, "", skill); gsub(/"/, "", skill) }
        /^[[:space:]]+executor:/ { executor=$0; sub(/^[^:]*:[[:space:]]*/, "", executor); gsub(/"/, "", executor) }
        /^[[:space:]]+result:/ { result=$0; sub(/^[^:]*:[[:space:]]*/, "", result); gsub(/"/, "", result) }
        /^[[:space:]]+used:/ {
            used=$0; sub(/^[^:]*:[[:space:]]*/, "", used); gsub(/"/, "", used)
            if (skill == "cdp-browse" && result == "PASS" && used == "true" &&
                (agent == "" || executor == agent)) found=1
        }
        END { exit(found ? 0 : 1) }
    ' "$_cdp_skill_log"; then
        _cdp_receipt=1
    fi
    if (( !_cdp_receipt )); then
        echo "★CDP直コマンド検知: CDP専用スキル /cdp-browse を先に起動せよ(内部でscripts/cdp/cdp_cli.sh+隔離profile cdp-chrome-XXXX/D009を使う)。本番実測の正本は記憶DB knowledge:776999ee — bash scripts/cdp/cdp_measure.sh <cmd_id> --pages /a /b が起動+認証(auto-ops perf_measure.py: admin Basic Auth→viewer pw→viewer認証)+測定を内包。★viewer認証だけでは不十分、admin認証(Basic Auth)要のPF/ページ有り。稼働中CDP(9222)へ独自測定は cdp_font_probe.py(font)/cdp_ed_probe.py(E/D軸)。claude-in-chrome MCP(browser extension)は使うな — extension未接続で失敗し殿の通常Chromeを汚染する(記憶DB 2026-07-22ルール)。" >&2
        _cdp_fire_log="${GATE_FIRE_LOG_FILE:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
        (
            flock -w 2 200 2>/dev/null || exit 0
            mkdir -p "$(dirname "$_cdp_fire_log")" 2>/dev/null || true
            printf -- '- ts: "%s", gate: "cdp_direct_skill_nudge", result: WARN, reasons: "cdp-browse receipt missing"\n' \
                "$(date '+%Y-%m-%dT%H:%M:%S')" >> "$_cdp_fire_log"
        ) 200>"${_cdp_fire_log}.lock" 2>/dev/null || true
    fi
    unset _cdp_skill_log _cdp_agent _cdp_receipt _cdp_fire_log
fi

# === Guard 14: DB direct connection BLOCK (LS064+LS-A17: /db-check skill強制) ===
# WARN→BLOCK升格(2026-07-01): WARNでは試行錯誤を防げない実証(将軍がpsycopg2で6回試行錯誤)
# /db-checkスキルにスキーマ・接続方式・クエリテンプレート完備。直接接続は不要
# cmd_karo_hotfix_guard14_db_trust_boundary_202607120854: 語彙一律BLOCK→操作意図×信頼境界の構造判定へ置換。
# 旧実装は"psycopg2"等の文字列が command 中に現れるだけでBLOCKし、grep等の参照や
# localhost/sqlite:///:memory:等のローカルCI接続まで誤検知した(hayate blocked report 2026-07-12T08:49:15)。
# 分類器は scripts/lib/guard14_db_trust_classify.py の1箇所に集約(テストからも直接呼べる)。
# DB操作意図(not_connection/connection)と接続先信頼境界(local_ephemeral/untrusted)を
# 接続runtimeを含むsegment自身のトークンだけから構造判定し、Guard14は分類結果だけで判断する。
# 各論allowlist(コマンド名の列挙によるパッチ)は追加しない。
# review_correction(2026-07-12 09:17, karo): 旧"db-check"自由文字列免除はcommand全文への
# 部分文字列一致だったため、production接続の後ろに `; echo db-check` を足すだけで
# 全Guardを迂回できた。免除はclassify側でcheck_pf_config.py(実在スクリプト)を含む
# segmentのみを対象に構造判定するため、ここでは免除チェックを行わない。
# review_correction(2026-07-12 09:30, karo): ファイル先頭のawk抽出はJSON \"エスケープの
# 早期break回避はするが実際のunescapeはしないため、$commandにはPython -c引数の
# バックスラッシュ+quoteがそのまま残り、classifierのshlex token化がquote境界を誤認識する。
# classifier側でregexパッチせず、生のHOOK payload(JSON)をそのまま渡し、
# classifier自身がjson.loadsでtool_input.commandを正規復元してから分類する。
# review_correction(2026-07-12 09:33/09:36, karo): 旧3語(psycopg2/DATABASE_URL/create_db_engine)
# だけの入口ではpsql "postgresql://remote-host/proddb"のようなpsql CLI直接接続が
# classifierへ一切到達せず素通りする。語彙を拡張して条件付きのまま残す代替案は、
# psql以外の未列挙clientを再び漏らす各論パッチそのものであり禁止された。
# review_correction(2026-07-12 09:42/09:45, karo): 全command無条件classifier呼出しは
# WSL2でpython3 -S+lazy import後も実測+29ms/呼び出し(48ms→77ms, N=20 median)で許容不能。
# 外側ifへの回帰ではなく、共通classifier自体を二段化する。fast filter/slow pathの実装は
# 本ファイルへ直書きしない(hook側語彙gate+Python側intentの二重SSOT化を防ぐ)。
# scripts/lib/guard14_db_trust_classify.sh の guard14_classify() が唯一の入口(SSOT)。
# Guard14はその返り値だけを見る。
# review_correction(2026-07-12 09:55, karo): 共有.sh自体が欠落すると`source`失敗が
# set -euoによりexit 1(hookエラー扱い。Codex CLIはこれでクラッシュしうる)で終わり、
# Guard14表記の無い一般的なbashエラーになる。fail-closedの意図(exit 2+明示BLOCK)を
# 保つため、source前に実在確認して専用のGuard14 BLOCKへ倒す。
# review_correction(2026-07-12 10:03, karo): 単純代入 `_g14_classification="$(guard14_classify ...)"`
# はset -euo下で、guard14_classify内部のpython3が失敗した場合その非zero終了statusをそのまま
# 引き継ぎ、if判定に到達する前にset -eでhookが即終了する。この経路ではpython3のstderrを
# 2>/dev/nullで握り潰しているためGuard14表記の無い、失敗理由不明のexitになる(実際の失敗modeに
# よってexit codeも不定)。`if !`形式(set -eの対象外)で明示的に捕捉し、専用Guard14 BLOCK+exit 2へ
# 正規化する。
run_guard14

# === Guard 15: CoDD greenfield generate before extract BLOCK (LS036 L4, cmd_2891事故) ===
# 一次情報確認(2026-07-08, codd v2.19.0 --help): `codd require`はbrownfield専用("Run 'codd extract' first"と明記)、
# `codd spec`はCLI非存在(Error: No such command)。真の時間浪費源はgreenfield限定の`codd generate --wave`ループ
# (wave1-5直列で実測30分超, cmd_2891)。extract未実行(.codd/extract/不在)かつ対象に既存ソースがある場合のみBLOCK。
# 新規空プロジェクトへのgenerateは許可(誤検知回避)。トークン解析(shlex)で実コマンド呼出しのみ判定し、
# echo/grep等の引数内の文字列言及による誤検知(cmd_2075と同種のFPパターン)を避ける。
if [[ -n "${command:-}" && "$command" == *'codd'* && "$command" == *'generate'* && "$command" == *'--wave'* ]]; then
    _codd_block_reason="$(COMMAND="$command" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import os
import sys

command = os.environ.get("COMMAND", "")
sys.path.insert(0, os.path.join(os.environ["PROJECT_ROOT"], "scripts", "lib"))
from shell_command_segments import segment_tokens


def find_path_arg(tokens: list[str]) -> str:
    for i, tok in enumerate(tokens):
        if tok == "--path" and i + 1 < len(tokens):
            return tokens[i + 1]
    return "."


def has_existing_source(root_dir: str, max_depth: int = 3) -> bool:
    if not os.path.isdir(root_dir):
        return False
    exts = (".py", ".sh", ".ts", ".js", ".go", ".java")
    base_depth = root_dir.rstrip(os.sep).count(os.sep)
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in (".codd", "node_modules", ".git")]
        cur_depth = root.count(os.sep) - base_depth
        if cur_depth >= max_depth:
            dirs[:] = []
            continue
        if any(f.endswith(exts) for f in files):
            return True
    return False


for tokens in segment_tokens(command) or []:
    if len(tokens) < 2 or os.path.basename(tokens[0]) != "codd" or tokens[1] != "generate":
        continue
    if "--wave" not in tokens:
        continue
    target = find_path_arg(tokens)
    resolved = target if os.path.isabs(target) else os.path.join(os.getcwd(), target)
    resolved = os.path.realpath(resolved)
    if os.path.isdir(os.path.join(resolved, ".codd", "extract")):
        continue
    if has_existing_source(resolved):
        print(
            "BLOCKED: 既存コードがある対象への codd generate --wave (greenfield)は禁止。"
            f"先に codd extract --path {target} を実行せよ(brownfield逆生成が正解)。"
        )
        break
PY
)"
    if [[ -n "$_codd_block_reason" ]]; then
        emit_deny "$_codd_block_reason"
    fi
    unset _codd_block_reason
fi

# === Guard 17: heavy job admission (host-wide single semaphore) ===
# cmd_karo_hotfix_heavy_job_admission_202607121348: 同一8コアWSL2ホスト上でbats全量/
# pytest全量/DM-Signal golden regressionが無調停で並走し、CPUオーバーサブスクリプション
# (OSスケジューラの強制プリエンプション)でwall時間を増幅する構造バグを根治する
# (実測: golden単独550.82s wall/337.84s CPU, involuntary context switch 306,138件,
# load average最大40.05/8コア。docs/research/cmd_karo_hotfix_dm_golden_standalone_timeout_20260712_findings.md)。
# heavy_job_classify.shが"heavy"と判定したcommandは scripts/heavy_job_admission.sh 経由
# (host-wide flock semaphore、最大同時1)を強制する。
# 除外(BLOCKしない): (a) 既にwrapper経由(command内にheavy_job_admission.shを含む)、
# (b) run_tests.sh経由(runner自身がself-reexecでadmissionを内包する。run_tests.sh参照)。
if [[ -n "${command:-}" && "$command" != *'heavy_job_admission.sh'* && "$command" != *'run_tests.sh'* ]]; then
    if [[ "$command" == *'bats'* || "$command" == *'pytest'* || "$command" =~ python3?([[:space:]]|$) ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/scripts/lib/heavy_job_classify.sh"
        _heavy_job_class="$(heavy_job_classify "$command")"
        case "$_heavy_job_class" in
            heavy)
                emit_deny "BLOCK(heavy-job-admission): 重量テストジョブ(bats複数ファイル/全量、pytest全量、golden regression等)はhost-wide排他制御が必要。'bash scripts/heavy_job_admission.sh -- <元のコマンド全体>' の形で実行せよ。単一の.batsファイル1つや単一の::テスト関数指定は軽量とみなされ対象外。"
                ;;
            malformed)
                emit_deny "BLOCK(shell-syntax): commandの引用符またはshell構文を解析できない。heavy-job wrapperでは解消しないため、まずquote/escapeを修正せよ。"
                ;;
        esac
        unset _heavy_job_class
    fi
fi

# === Guard 18: git stash mutation block (shared worktree protection) ===
# cmd_karo_ci_red_remaining_unit_202607151950: このタスク系列は複数忍者が
# 分離worktreeを持たず共有main working treeへ直接作業する。トップレベルの
# `git stash` はその1つのindex/working treeを全員分まとめて退避してしまう
# (2026-07-15 20:27実例: bare `git stash`が共有worktreeのtracked 23 files(複数忍者+運用差分)を一括退避し、
# 家老が手動`stash@{0} apply`で復旧)。argv位置ベースで実際に"git"が起動され
# "stash"サブコマンドが読み取り専用(list/show)以外の場合のみBLOCKする
# (Guard 5→17の教訓と同じく、raw textの部分一致では判定しない)。
if [[ -n "${command:-}" && "$command" == *'stash'* ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/lib/git_stash_guard_classify.sh"
    if [[ "$(git_stash_guard_classify "$command")" == "block" ]]; then
        emit_deny "BLOCK: git stashは共有worktreeの全員分tracked差分を一括退避し他忍者のWIPを破壊する。指定pathだけを対象にする 'bash scripts/ninja_scope_commit.sh' を使え。読み取り専用の 'git stash list'/'git stash show' はBLOCK対象外。"
    fi
fi

# === Guard 19: gh gist create/edit bypass block ===
# gist操作はgist-shareスキル(scripts/gist_share.sh)経由が正規フロー。
# gist_share.shは`gh api --method POST gists`を使うためこのguardに干渉しない。
# 素の`gh gist create`/`gh gist edit`は重複チェック・meta管理・verified writeを迂回する。
# origin: [[殿指摘_gist重複_20260806]] -> [[gh_gist_create直接実行]] -> [[Guard19_gist_skill_bypass_block]]
if [[ -n "${command:-}" && "$command" == *'gh gist'* ]]; then
    if [[ "$command" == *'gh gist create'* || "$command" == *'gh gist edit'* ]]; then
        emit_deny "BLOCK [Guard19]: 素の gh gist create/edit は重複・meta管理を迂回する。/gist-share スキル(scripts/gist_share.sh)を使え。削除は gh gist delete を直接実行してよい。"
    fi
fi

# === Guard 4: block_destructive (complex, needs python3 for path checks) ===
[[ "$payload" != *'rm '* && "$payload" != *'sudo'* && "$payload" != *'su '* && \
   "$payload" != *'kill'* && "$payload" != *'git push'* && "$payload" != *'git merge'* && "$payload" != *'git reset'* && \
   "$payload" != *'git cherry-pick'* && "$payload" != *'git rebase'* && "$payload" != *'git revert'* && "$payload" != *'git am '* && \
   "$payload" != *'git checkout'* && "$payload" != *'git restore'* && "$payload" != *'git clean'* && \
   "$payload" != *'mkfs'* && "$payload" != *'fdisk'* && "$payload" != *'mount'* && "$payload" != *'umount'* && \
   "$payload" != *'dd '* && "$payload" != *'chrome'* && "$payload" != *'chromium'* && \
   "$payload" != *'curl'* && "$payload" != *'wget'* && \
   "$payload" != *'chmod'* && "$payload" != *'chown'* && \
   "$payload" != *'tmux kill'* ]] && { emit_memory_db_for_knowledge_grep; exit 0; }

# Dangerous keyword detected — extract command and run python3 checker
[[ -z "${command:-}" ]] && exit 0

needs_destructive_python() {
    local cmd="$1"

    # shellcheck disable=SC2221,SC2222  # FP: independent glob patterns in same case arm
    case "$cmd" in
        *"rm "*|*"sudo"*|*"su "*|*"kill"*|*"git push"*|*"git merge"*|*"git reset"*|*"git checkout"*|*"git restore"*|*"git clean"*|*"tmux kill"*) return 0 ;;
        *"git cherry-pick"*|*"git rebase"*|*"git revert"*|*"git am "*) return 0 ;;
        *"mkfs"*|*"fdisk"*|*"mount"*|*"umount"*) return 0 ;;
    esac
    if [[ "$cmd" == *'curl'* || "$cmd" == *'wget'* ]]; then
        [[ "$cmd" =~ \|[[:space:]]*(bash|sh)([[:space:]]|$) ]] && return 0
        return 1
    fi
    if [[ "$cmd" == *'chmod'* || "$cmd" == *'chown'* ]]; then
        [[ "$cmd" =~ (^|[[:space:]])--recursive([[:space:]]|$) || "$cmd" =~ (^|[[:space:]])-[^[:space:]]*R[^[:space:]]*([[:space:]]|$) ]] && return 0
        return 1
    fi
    if [[ "$cmd" == *'dd '* ]]; then
        [[ "$cmd" =~ (^|[[:space:]])if= ]] && return 0
        return 1
    fi
    if [[ "$cmd" == *'chrome'* || "$cmd" == *'chromium'* ]]; then
        [[ "$cmd" == *'--headless'* ]] && return 0
        return 1
    fi
    return 1
}

if ! needs_destructive_python "$command"; then
    emit_memory_db_for_knowledge_grep
    exit 0
fi

approval_reason="$(destructive_approval_reason)"
if [[ -n "$approval_reason" ]]; then
    emit_deny "$approval_reason"
fi

reason="$(
    COMMAND="$command" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import os
import re
import subprocess
import sys

command = os.environ.get("COMMAND", "")
project_root = os.path.realpath(os.environ.get("PROJECT_ROOT", "."))
cwd = os.path.realpath(os.getcwd())
sys.path.insert(0, os.path.join(project_root, "scripts", "lib"))
from shell_command_segments import segment_tokens


def outside_project(path: str):
    expanded = os.path.expanduser(path)
    prefix = re.split(r"[\*\?\[]", expanded, maxsplit=1)[0]
    if prefix == "":
        prefix = expanded or "."
    candidate = prefix if os.path.isabs(prefix) else os.path.join(cwd, prefix)
    resolved = os.path.realpath(candidate)
    in_project = resolved == project_root or resolved.startswith(project_root + os.sep)
    return (not in_project), resolved


def is_system_path(resolved: str):
    if resolved == "/":
        return True
    prefixes = (
        "/etc", "/usr", "/var", "/bin", "/sbin", "/lib", "/lib64", "/opt",
        "/home", "/mnt/c", "/mnt/d",
    )
    return any(resolved == p or resolved.startswith(p + "/") for p in prefixes)


def check_pipe_to_shell(cmd: str):
    patterns = (
        r"(^|[ \t;&|])curl\b[^\n|]*\|[ \t]*(bash|sh)\b",
        r"(^|[ \t;&|])wget\b[^\n|]*-O-[^\n|]*\|[ \t]*sh\b",
    )
    for pattern in patterns:
        if re.search(pattern, cmd):
            return "D008: pipe-to-shell pattern is forbidden (curl/wget -> sh/bash)"
    return ""


def check_rm(tokens):
    has_r = has_f = False
    paths = []
    after_double_dash = False
    for tok in tokens[1:]:
        if tok == "--":
            after_double_dash = True
            continue
        if not after_double_dash and tok.startswith("-"):
            if tok == "--recursive": has_r = True; continue
            if tok == "--force": has_f = True; continue
            flags = tok[1:].lower()
            if "r" in flags: has_r = True
            if "f" in flags: has_f = True
            continue
        paths.append(tok)
    if not (has_r and has_f):
        return ""
    for raw in paths:
        if raw in ("/", "~") or raw.startswith("/mnt/*") or raw.startswith("/home/*"):
            return "D001: rm -rf on root/system wildcard path is forbidden"
        outside, resolved = outside_project(raw)
        if outside:
            return f"D002: rm -rf outside project tree is forbidden ({resolved})"
    return ""


def _git_guard_known_agents():
    # SSOT = config/settings.yaml via scripts/lib/agent_config.sh (no hardcoded roster).
    try:
        result = subprocess.run(
            ["bash", "-c", f'source "{project_root}/scripts/lib/agent_config.sh" && get_all_agents'],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return set()
    if result.returncode != 0:
        return set()
    return {name for name in result.stdout.split() if name}


def _git_guard_agent_identities():
    # PD-106: shared-worktree ownership signal. Test seam first (avoids
    # touching real queue/tasks/*.yaml or requiring a live tmux server);
    # production falls back to the same TMUX_PANE->agent_id lookup G2 uses.
    override = os.environ.get("PRE_BASH_GIT_GUARD_IDENTITY")
    if override is not None:
        return {token for token in override.split(",") if token}
    agent_id = ""
    tmux_pane = os.environ.get("TMUX_PANE", "")
    if tmux_pane:
        try:
            agent_id = subprocess.run(
                ["tmux", "display-message", "-t", tmux_pane, "-p", "#{@agent_id}"],
                capture_output=True, text=True, timeout=3,
            ).stdout.strip()
        except Exception:
            agent_id = ""
    identities = set()
    if agent_id:
        identities.add(agent_id)
        task_yaml = os.path.join(project_root, "queue", "tasks", f"{agent_id}.yaml")
        if os.path.isfile(task_yaml):
            try:
                import yaml
                with open(task_yaml, encoding="utf-8") as fh:
                    data = yaml.safe_load(fh) or {}
                task = data.get("task", data) if isinstance(data, dict) else {}
                for key in ("task_id", "subtask_id", "parent_cmd"):
                    value = str(task.get(key) or "").strip()
                    if value:
                        identities.add(value)
            except Exception:
                pass
    return identities


def _git_guard_classify_subject(subject, identities):
    # Same convention as ninja_scope_commit.sh's test_necessity same-task
    # check and gate_report_format_main.py's commit identity check: a
    # cmd_id-shaped token in the subject is the SSOT for "whose task".
    cmd_tokens = re.findall(r"cmd_[A-Za-z0-9_]+", subject)
    if cmd_tokens:
        if identities and any(identity and identity in subject for identity in identities):
            return "mine"
        return "other"
    known_agents = _git_guard_known_agents()
    found_agents = {
        agent for agent in known_agents
        if re.search(r"(?<![A-Za-z0-9_])" + re.escape(agent) + r"(?![A-Za-z0-9_])", subject)
    }
    if not found_agents:
        return "ambiguous"
    my_agent = next((identity for identity in identities if identity in known_agents), None)
    if my_agent and found_agents == {my_agent}:
        return "mine"
    if my_agent and my_agent in found_agents:
        return "ambiguous"
    return "other"


def _git_guard_effective_cwd(full_cmd):
    # Mirrors check_main_branch_protection's own `cd <path>` resolution
    # below: this guard's tokens come from segment_tokens(command), which
    # only sees the current segment, not any leading `cd <dir> &&` that
    # redirects where the real git process would run.
    effective = cwd
    cd_match = re.search(r"\bcd\s+(\S+)", full_cmd)
    if cd_match:
        cd_target = cd_match.group(1)
        expanded = os.path.expanduser(cd_target)
        candidate = expanded if os.path.isabs(expanded) else os.path.join(cwd, expanded)
        effective = os.path.realpath(candidate)
    return effective


def _git_guard_reset_head_move_target(args, effective_cwd):
    # git reset only moves HEAD when there is exactly one commit-ish
    # positional and no `-- <path>` pathspec form (which never touches HEAD).
    if "--" in args:
        return None
    non_flags = [tok for tok in args if not tok.startswith("-")]
    if len(non_flags) != 1:
        return None
    candidate = non_flags[0]
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", candidate + "^{commit}"],
            cwd=effective_cwd, capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def check_shared_worktree_reset(args, full_cmd):
    effective_cwd = _git_guard_effective_cwd(full_cmd)
    target_sha = _git_guard_reset_head_move_target(args, effective_cwd)
    if not target_sha:
        return ""
    try:
        head_result = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=effective_cwd, capture_output=True, text=True, timeout=5,
        )
        if head_result.returncode != 0:
            return ""
        old_head = head_result.stdout.strip()
        if old_head == target_sha:
            return ""
        log_result = subprocess.run(
            ["git", "log", "--format=%s", f"{target_sha}..{old_head}"],
            cwd=effective_cwd, capture_output=True, text=True, timeout=5,
        )
        if log_result.returncode != 0:
            return ""
        subjects = [line for line in log_result.stdout.splitlines() if line]
    except Exception:
        return ""
    if not subjects:
        return ""
    identities = _git_guard_agent_identities()
    for subject in subjects:
        if _git_guard_classify_subject(subject, identities) == "other":
            return (
                "D011: git reset would drop a commit that belongs to another agent/task "
                f"({subject[:80]!r}); shared worktree — verify ownership before resetting past it, "
                "or use 'bash scripts/ninja_scope_commit.sh' to only touch your own scope"
            )
    return ""


def check_git(tokens):
    if len(tokens) < 2:
        return ""
    sub = tokens[1]
    args = tokens[2:]
    if sub == "push":
        if "--force-with-lease" not in args and ("--force" in args or "-f" in args):
            return "D003: git push --force/-f is forbidden (use --force-with-lease)"
        return ""
    if sub == "merge" and cwd == project_root:
        return (
            "D012: direct git merge in the shared project worktree is forbidden; "
            "use bash scripts/safe_shared_main_ff.sh <target> so ref/index/worktree "
            "convergence is verified"
        )
    # 2026-08-28 23:45 T163: a karo cherry-pick in the shared worktree left
    # '<<<<<<< HEAD' inside scripts/hooks/codex_inbox_priority_guard.sh for 12
    # minutes; the live hook then failed on every karo tool call (self-deadlock).
    # Any history-rewriting op that can leave conflict markers in hot scripts
    # must run in an isolated worktree, never in the shared root.
    if sub in ("cherry-pick", "rebase", "revert", "am") and cwd == project_root:
        if "--continue" in args or "--abort" in args or "--skip" in args or "--quit" in args:
            return ""
        return (
            "D012: direct git " + sub + " in the shared project worktree is forbidden "
            "(conflict markers land in live hooks/scripts); run it in an isolated "
            "worktree (git worktree add) and converge with bash scripts/safe_shared_main_ff.sh"
        )
    if sub == "reset" and "--hard" in args:
        return "D004: git reset --hard is forbidden"
    if sub == "reset" and "--hard" not in args:
        reason = check_shared_worktree_reset(args, command)
        if reason:
            return reason
    if sub == "checkout" and "--" in args:
        idx = args.index("--")
        if idx + 1 < len(args) and args[idx + 1] == ".":
            return "D004: git checkout -- . is forbidden"
    if sub == "restore" and "." in args:
        return "D004: git restore . is forbidden"
    if sub == "clean":
        for tok in args:
            if tok == "--force":
                return "D004: git clean -f/--force is forbidden"
            if tok.startswith("-") and "f" in tok[1:] and tok != "-n":
                return "D004: git clean -f/--force is forbidden"
    return ""


def check_recursive_system_chmod_chown(tokens, cmd0):
    recursive = False
    for tok in tokens[1:]:
        if tok == "--recursive": recursive = True; break
        if tok.startswith("-") and "R" in tok[1:]: recursive = True; break
    if not recursive:
        return ""
    non_options = [t for t in tokens[1:] if not t.startswith("-")]
    if not non_options:
        return ""
    paths = non_options[1:] if len(non_options) >= 2 else non_options
    for raw in paths:
        outside, resolved = outside_project(raw)
        if outside and is_system_path(resolved):
            return f"D005: {cmd0} -R on system path is forbidden ({resolved})"
    return ""


def check_main_branch_protection(tokens, full_cmd):
    """G2: Block push to main/master in external repos."""
    if len(tokens) < 2 or tokens[0] != "git" or tokens[1] != "push":
        return ""
    args = tokens[2:]
    non_flag = [a for a in args if not a.startswith("-")]
    has_main_target = any(
        a in ("main", "master") or a.endswith(":main") or a.endswith(":master")
        for a in non_flag
    )
    if not has_main_target:
        return ""
    # Determine effective working directory from cd in the full command
    effective = cwd
    cd_match = re.search(r"\bcd\s+(\S+)", full_cmd)
    if cd_match:
        cd_target = cd_match.group(1)
        expanded = os.path.expanduser(cd_target)
        candidate = expanded if os.path.isabs(expanded) else os.path.join(cwd, expanded)
        effective = os.path.realpath(candidate)
    # If in project tree, allow (infra repo uses main branch directly)
    if effective == project_root or effective.startswith(project_root + os.sep):
        return ""
    # Allow shogun/karo/gunshi to push to external repos (they have judgment authority)
    # Ninja push requires push_allowed: true in task YAML (karo sets per-cmd)
    try:
        tmux_pane = os.environ.get("TMUX_PANE", "")
        if tmux_pane:
            agent_id = subprocess.run(
                ["tmux", "display-message", "-t", tmux_pane, "-p", "#{@agent_id}"],
                capture_output=True, text=True, timeout=3
            ).stdout.strip()
            if agent_id in ("shogun", "karo", "gunshi"):
                return ""
            if agent_id:
                task_yaml = os.path.join(project_root, "queue", "tasks", f"{agent_id}.yaml")
                if os.path.isfile(task_yaml):
                    with open(task_yaml) as f:
                        for line in f:
                            if re.match(r'\s*push_allowed:\s*true\s*$', line, re.IGNORECASE):
                                return ""
    except Exception:
        pass  # On any error, fall through to block (safe default)
    return f"G2: Direct push to main/master in external repo is forbidden ({effective})"


def _is_kill_null_signal_only(args):
    # kill -0 / killall -0 / pkill -0 (and -s 0 / --signal 0) send no signal
    # at all (POSIX null signal) -- existence/permission check only, never
    # destructive. Any other or additional signal spec (numeric, name, or
    # none at all = default SIGTERM) must still be blocked.
    signal_specs = []
    i = 0
    while i < len(args):
        tok = args[i]
        if tok in ("-s", "--signal"):
            if i + 1 >= len(args):
                return False
            signal_specs.append(args[i + 1])
            i += 2
            continue
        if tok.startswith("-") and tok != "-":
            signal_specs.append(tok[1:])
        i += 1
    if not signal_specs:
        return False
    return all(spec == "0" for spec in signal_specs)


reason = check_pipe_to_shell(command)
if reason:
    print(reason)
    raise SystemExit(0)

for tokens in segment_tokens(command) or []:
    if not tokens:
        continue
    cmd0 = os.path.basename(tokens[0])
    if cmd0 in {"sudo", "su"}:
        print("D005: sudo/su is forbidden"); raise SystemExit(0)
    if cmd0 in {"kill", "killall", "pkill"}:
        if not _is_kill_null_signal_only(tokens[1:]):
            print("D006: kill/killall/pkill is forbidden"); raise SystemExit(0)
    if cmd0 == "tmux" and len(tokens) >= 2 and tokens[1] in {"kill-server", "kill-session"}:
        print("D006: tmux kill-server/kill-session is forbidden"); raise SystemExit(0)
    if cmd0 == "rm":
        reason = check_rm(tokens)
        if reason: print(reason); raise SystemExit(0)
    if cmd0 == "git":
        reason = check_git(tokens)
        if reason: print(reason); raise SystemExit(0)
        reason = check_main_branch_protection(tokens, command)
        if reason: print(reason); raise SystemExit(0)
    # filter-repo is blocked by Guard 0 (bash fast-check)
    if cmd0 in {"chmod", "chown"}:
        reason = check_recursive_system_chmod_chown(tokens, cmd0)
        if reason: print(reason); raise SystemExit(0)
    if cmd0.startswith("mkfs") or cmd0 in {"fdisk", "mount", "umount"}:
        print(f"D007: {cmd0} is forbidden"); raise SystemExit(0)
    if cmd0 == "dd" and any(tok.startswith("if=") for tok in tokens[1:]):
        print("D007: dd with if= is forbidden"); raise SystemExit(0)
    if cmd0 in {"chrome", "chrome.exe", "chromium", "google-chrome", "google-chrome-stable"}:
        has_headless = any(tok == "--headless" or tok.startswith("--headless=") for tok in tokens[1:])
        if has_headless:
            has_user_data_dir = any(tok.startswith("--user-data-dir") for tok in tokens[1:])
            if not has_user_data_dir:
                print("D009: chrome --headless requires --user-data-dir"); raise SystemExit(0)
PY
)"

if [ -n "$reason" ]; then
    emit_deny "$reason"
fi

emit_memory_db_for_knowledge_grep

exit 0
