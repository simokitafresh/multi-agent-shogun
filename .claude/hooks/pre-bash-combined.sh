#!/usr/bin/env bash
# Combined Bash PreToolUse guard: block_destructive + no-verify + report-deny + yaml-dump
# cmd_1661: 4 hooks → 1 script. Eliminates 3 bash startup costs (~60ms each).
set -euo pipefail

if [ -n "${HOOK_PAYLOAD+x}" ]; then
    payload="$HOOK_PAYLOAD"
else
    payload="$(cat)"
fi
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Bash"'* ]] && exit 0
command=""
# cmd_2075: jq → awk置換 (jq≈4ms → awk≈2ms, 前回revertとの差: サブシェル維持/ツール軽量化)
# awk char-by-char で \"エスケープを正しく処理
if [[ "$payload" == *'"tool_input"'* && "$payload" == *'"command"'* ]]; then
    command="$(awk '
        match($0, /"command"[[:space:]]*:[[:space:]]*"/) {
            s = substr($0, RSTART + RLENGTH)
            n = length(s); result = ""
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (c == "\\" && i < n) { result = result substr(s, i, 2); i++; continue }
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
unset _pre_bash_self

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
if [[ -z "${BATS_TEST_FILENAME:-}" ]] && ! bash "$SCRIPT_DIR/scripts/hooks/three_layer_preflight.sh" verify "Bash" "" "$command" >/dev/null 2>&1; then
    emit_deny "BLOCK: 三層preflight証跡なし/無効。UserPromptSubmitごとに記憶DB・semantic・Obsidian検索を完了せよ"
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

    query="$(COMMAND="$command" python3 - <<'PY'
import os
import re
import shlex

command = os.environ.get("COMMAND", "")
knowledge_roots = ("context", "docs", "projects", "memory")
infra_roots = ("scripts/gates/", "scripts/hooks/", ".claude/hooks/")


def split_segments(cmd: str):
    return [seg.strip() for seg in re.split(r"(?:&&|\|\||;|\|)", cmd) if seg.strip()]


def normalize_tokens(segment: str):
    try:
        tokens = shlex.split(segment, posix=True)
    except ValueError:
        return []
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


for segment in split_segments(command):
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

emit_memory_db_for_knowledge_grep() {
    local query agent_id hash_file now last rows sql query_sql agent_sql like_sql

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
    rows="$(bash "$SCRIPT_DIR/scripts/memory_db_query.sh" "$sql" 2>/dev/null || true)"
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
    COMMAND="$command" LORD_CONVERSATION_FILE="$conversation_file" python3 - <<'PY'
import json
import os
import re
import shlex

command = os.environ.get("COMMAND", "")
conversation_file = os.environ.get("LORD_CONVERSATION_FILE", "")


def split_segments(cmd: str):
    return [seg.strip() for seg in re.split(r"(?:&&|\|\||;|\|)", cmd) if seg.strip()]


def destructive_families(cmd: str) -> list[str]:
    families: list[str] = []
    for segment in split_segments(cmd):
        try:
            tokens = shlex.split(segment, posix=True)
        except ValueError:
            continue
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
    _guard1_is_git_commit="$(HOOK_PAYLOAD_JSON="$payload" python3 - <<'PY'
import json
import os
import re
import shlex

HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
OPERATORS = {";", "&", "|", "&&", "||"}


def strip_heredocs(text):
    lines = text.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        i += 1
        m = HEREDOC_RE.search(line)
        if not m:
            continue
        strip_tabs = m.group(1) == "-"
        delim = m.group(3)
        while i < n:
            body_line = lines[i]
            probe = body_line.lstrip("\t") if strip_tabs else body_line
            i += 1
            if probe == delim:
                break
    return "\n".join(out)


def tokenize(cmd):
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    return list(lexer)


def split_into_segments(tokens):
    segments = []
    current = []
    for tok in tokens:
        if tok in OPERATORS:
            if current:
                segments.append(current)
            current = []
            continue
        current.append(tok)
    if current:
        segments.append(current)
    return segments


def is_git_commit(cmd):
    stripped = strip_heredocs(cmd)
    try:
        tokens = tokenize(stripped)
    except ValueError:
        # 構造判定: 行頭 or 区切り文字直後がgitで始まる場合のみ疑わしいとみなしfail-closed。
        # それ以外(report/message本文の引用符崩れ等)は無関係commandとして安全にskipする。
        return bool(re.search(r"(^|[;&|])\s*git(\s|$)", stripped))
    for seg in split_into_segments(tokens):
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
        if ! bash "$SCRIPT_DIR/scripts/dm_signal_research_reflux_guard.sh" check-command "$command"; then
            emit_deny "BLOCK(GA-220): DM-Signal research commit requires matching context reflux fingerprint"
        fi
    fi
    unset _guard1_is_git_commit
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
        if [[ "$command" == *'python3'* || "$command" == *'python '* || "$command" == *'python	'* || "$command" == *'python -'* ]]; then
            for pattern in "queue/" "tasks/" "shogun_to_karo" "karo_snapshot" "inbox/" "reports/"; do
                if [[ "$command" == *"$pattern"* ]]; then
                    emit_deny "BLOCKED: yaml.dump on operational YAML is forbidden (data loss risk). Use: bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>"
                fi
            done
        fi
    fi
fi

# === Guard 3: report-deny (bash redirect/tee to report YAML) ===
if [[ "$payload" == *'queue/reports/'* ]]; then
    if [[ -n "${command:-}" && "$command" != *'report_field_set.sh'* ]]; then
        redirect_pattern='>+[[:space:]]*[^ ]*queue/reports/[^ ]*\.yaml'
        tee_pattern='tee[[:space:]].*queue/reports/[^ ]*\.yaml'
        python3_pattern='python3.*open.*queue/reports/.*\.yaml'
        if [[ "$command" =~ $redirect_pattern ]] || [[ "$command" =~ $tee_pattern ]]; then
            emit_deny "報告YAMLへのBashリダイレクト(>/>>/ tee)は禁止。report_field_set.sh経由で書き込みせよ。"
        fi
        if [[ "$command" =~ $python3_pattern ]]; then
            emit_deny "報告YAMLへのpython3 open()直接書込みは禁止。report_field_set.sh経由で書き込みせよ。"
        fi
    fi
fi

# === Guard 3.5: karo_workarounds-deny (bash direct write to workaround log) ===
if [[ "$payload" == *'logs/karo_workarounds.yaml'* ]]; then
    if [[ -n "${command:-}" && "$command" != *'karo_workaround_log.sh'* ]]; then
        wa_redirect_pattern='>+[[:space:]]*[^ ]*logs/karo_workarounds\.yaml'
        wa_tee_pattern='tee[[:space:]].*logs/karo_workarounds\.yaml'
        wa_sed_pattern='(^|[;&|])[[:space:]]*sed[[:space:]].*(-i|--in-place).*logs/karo_workarounds\.yaml'
        wa_awk_pattern='(^|[;&|])[[:space:]]*awk[[:space:]].*logs/karo_workarounds\.yaml.*>+'
        wa_yfs_pattern='(^|[;&|])[[:space:]]*(bash[[:space:]]+)?[^;&|[:space:]]*yaml_field_set\.sh[[:space:]]+logs/karo_workarounds\.yaml'
        wa_python_pattern='python3?.*open.*logs/karo_workarounds\.yaml'
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
        task_python_path_write_pattern='python3?.*(Path[[:space:]]*\([^)]*queue/tasks/[^)]*\.yaml[^)]*\)|[^[:space:];]+)[[:space:]]*\.(write_text|write_bytes)[[:space:]]*\('
        if [[ "$command" =~ $task_redirect_pattern ]] || [[ "$command" =~ $task_tee_pattern ]] \
            || [[ "$command" =~ $task_sed_pattern ]] \
            || [[ "$command" =~ $task_python_open_write_pattern ]] \
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
        if [[ "$command" == *'sed '* || "$command" == *'sed -'* || "$command" == *"re.sub"* || "$command" == *".replace("* || "$command" == *'awk '* ]]; then
            emit_deny "BLOCK: shogun_to_karo.yamlへのsed/regex操作は禁止。Edit toolで手動変更せよ。status遷移gateの迂回を防ぐため。"
        fi
    fi
fi

# === Guard 5: bats full-run block (test_optimization_journal) ===
# cmd_karo_hotfix_heavy_job_admission_202607121348: heavy_job_admission.sh経由の
# コマンドは、元コマンド(bats tests/unit/等)がcommand文字列の末尾に含まれるため
# 誤って本Guardにも一致してしまう。wrapper経由なら本Guardより下のGuard17が
# admission契約を強制するため、本Guardはスキップしてよい。
if [[ "$payload" == *'bats '* && "$payload" == *'tests/unit'* && "$command" != *'heavy_job_admission.sh'* ]]; then
    if [[ "$command" =~ bats[[:space:]]+tests/unit/?[[:space:]]*$ ]] || \
       [[ "$command" =~ bats[[:space:]]+tests/unit/\* ]]; then
        emit_deny "BLOCK: bats tests/unit/ 全量実行は禁止。変更対象のテストファイルのみ指定せよ(見込み12分超)。"
    fi
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
# Note: regex limits to python execution context to avoid blocking mentions in message strings
if [[ "$payload" == *'wf_runner.py'* ]]; then
    if [[ -n "${command:-}" && "$command" =~ python[23]?[[:space:]].*wf_runner\.py ]]; then
        emit_deny "BLOCKED: wf_runner.py は並列OOMリスクのため使用禁止。代替: l1_alm_wf_engine.py --csv で1本ずつ直列実行せよ。"
    fi
fi


# === Guard 9: Skill bypass detection (殿裁定2026-05-10: スキル無視はバグ) ===
# 手動操作をBLOCKし、対応スキル使用を強制する (Level 4)
# Note: $command内のcommit message等のテキスト言及を除外するため、
# 実際のファイル操作パターン(cat/echo >> FILE, sed -i FILE)のみ検出
if [[ "$command" =~ (cat|echo|printf)[[:space:]].*\>\>[[:space:]]*.*gunshi_review_log\.yaml ]]; then
    _agent_id="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        emit_deny "BLOCKED: review_log直接追記禁止。/review-bundle スキルを使え (殿裁定: スキル無視はバグ)"
    fi
fi
if [[ "$command" =~ sed[[:space:]]+-i.*gate_result.*gunshi_review_log\.yaml || "$command" =~ sed[[:space:]]+-i.*gunshi_review_log\.yaml.*gate_result ]]; then
    _agent_id="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || true)}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        emit_deny "BLOCKED: gate_result手動sed禁止。/gate-sync スキルを使え (殿裁定: スキル無視はバグ)"
    fi
fi

# Guard 9b: inbox_writeのmodel_switch type BLOCK (殿裁定2026-06-20: スキル100%使用の仕組み)
# respawn-paneは正規操作（殿指摘2026-06-21: pane殺す→起動が正道）。BLOCKしない
# model_switchのみBLOCK対象（inbox_write経由のmodel切替を防止）
if [[ "$command" =~ model_switch ]] && [[ ! "$command" =~ ninja_monitor|reset_layout|shogun-cli-switch|gate_|startup|yaml_field_set|switch_cli_mode|memory_db_query|inbox_write|semantic_search|send-keys ]]; then
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

# Guard 13: 削除(2026-06-20)。各論パッチ(respawn-paneのみBLOCK)はバグ。
# 原理的解決=三層記憶skill_routing概念。検索すれば正しいスキルに到達する。

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
if [[ ! -f "$SCRIPT_DIR/scripts/lib/guard14_db_trust_classify.sh" ]]; then
    echo "BLOCK [Guard14]: DB接続分類器(scripts/lib/guard14_db_trust_classify.sh)が見つからない。fail-closedのため全DB関連コマンドをBLOCKする。" >&2
    exit 2
fi
# shellcheck source=scripts/lib/guard14_db_trust_classify.sh
source "$SCRIPT_DIR/scripts/lib/guard14_db_trust_classify.sh"
# review_correction(2026-07-12 10:03, karo): 単純代入 `_g14_classification="$(guard14_classify ...)"`
# はset -euo下で、guard14_classify内部のpython3が失敗した場合その非zero終了statusをそのまま
# 引き継ぎ、if判定に到達する前にset -eでhookが即終了する。この経路ではpython3のstderrを
# 2>/dev/nullで握り潰しているためGuard14表記の無い、失敗理由不明のexitになる(実際の失敗modeに
# よってexit codeも不定)。`if !`形式(set -eの対象外)で明示的に捕捉し、専用Guard14 BLOCK+exit 2へ
# 正規化する。
if ! _g14_classification="$(guard14_classify "$payload" "$command")"; then
    echo "BLOCK [Guard14]: DB接続分類器(guard14_classify)の実行に失敗した。fail-closedのためBLOCKする。" >&2
    exit 2
fi
if [[ "$_g14_classification" != "not_connection" && "$_g14_classification" != "connection:local_ephemeral" ]]; then
    echo "BLOCK [Guard14]: DB直接接続禁止(判定=${_g14_classification:-classification_error})。/db-checkスキルを使え(skills/db-check/SKILL.md)。スキーマ・接続方式・クエリテンプレート全て完備。試行錯誤ゼロで到達できる。localhost/127.0.0.1/::1/Unix socket/sqlite:///:memory: を使うローカルCI接続は自動許可対象。" >&2
    exit 2
fi

# === Guard 15: CoDD greenfield generate before extract BLOCK (LS036 L4, cmd_2891事故) ===
# 一次情報確認(2026-07-08, codd v2.19.0 --help): `codd require`はbrownfield専用("Run 'codd extract' first"と明記)、
# `codd spec`はCLI非存在(Error: No such command)。真の時間浪費源はgreenfield限定の`codd generate --wave`ループ
# (wave1-5直列で実測30分超, cmd_2891)。extract未実行(.codd/extract/不在)かつ対象に既存ソースがある場合のみBLOCK。
# 新規空プロジェクトへのgenerateは許可(誤検知回避)。トークン解析(shlex)で実コマンド呼出しのみ判定し、
# echo/grep等の引数内の文字列言及による誤検知(cmd_2075と同種のFPパターン)を避ける。
if [[ -n "${command:-}" && "$command" == *'codd'* && "$command" == *'generate'* && "$command" == *'--wave'* ]]; then
    _codd_block_reason="$(COMMAND="$command" python3 - <<'PY'
import os
import re
import shlex

command = os.environ.get("COMMAND", "")


def split_segments(cmd: str):
    return [seg.strip() for seg in re.split(r"(?:&&|\|\||;|\|)", cmd) if seg.strip()]


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


for segment in split_segments(command):
    try:
        tokens = shlex.split(segment, posix=True)
    except ValueError:
        continue
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
        if [[ "$(heavy_job_classify "$command")" == "heavy" ]]; then
            emit_deny "BLOCK(heavy-job-admission): 重量テストジョブ(bats複数ファイル/全量、pytest全量、golden regression等)はhost-wide排他制御が必要。'bash scripts/heavy_job_admission.sh -- <元のコマンド全体>' の形で実行せよ。単一の.batsファイル1つや単一の::テスト関数指定は軽量とみなされ対象外。"
        fi
    fi
fi

# === Guard 4: block_destructive (complex, needs python3 for path checks) ===
[[ "$payload" != *'rm '* && "$payload" != *'sudo'* && "$payload" != *'su '* && \
   "$payload" != *'kill'* && "$payload" != *'git push'* && "$payload" != *'git reset'* && \
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
        *"rm "*|*"sudo"*|*"su "*|*"kill"*|*"git push"*|*"git reset"*|*"git checkout"*|*"git restore"*|*"git clean"*|*"tmux kill"*) return 0 ;;
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
import shlex
import subprocess

command = os.environ.get("COMMAND", "")
project_root = os.path.realpath(os.environ.get("PROJECT_ROOT", "."))
cwd = os.path.realpath(os.getcwd())


def split_segments(cmd: str):
    return [seg.strip() for seg in re.split(r"(?:&&|\|\||;|\|)", cmd) if seg.strip()]


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


def check_git(tokens):
    if len(tokens) < 2:
        return ""
    sub = tokens[1]
    args = tokens[2:]
    if sub == "push":
        if "--force-with-lease" not in args and ("--force" in args or "-f" in args):
            return "D003: git push --force/-f is forbidden (use --force-with-lease)"
        return ""
    if sub == "reset" and "--hard" in args:
        return "D004: git reset --hard is forbidden"
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


reason = check_pipe_to_shell(command)
if reason:
    print(reason)
    raise SystemExit(0)

for segment in split_segments(command):
    try:
        tokens = shlex.split(segment, posix=True)
    except ValueError:
        continue
    if not tokens:
        continue
    cmd0 = os.path.basename(tokens[0])
    if cmd0 in {"sudo", "su"}:
        print("D005: sudo/su is forbidden"); raise SystemExit(0)
    if cmd0 in {"kill", "killall", "pkill"}:
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
