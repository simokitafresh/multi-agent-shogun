#!/usr/bin/env bash
# X投稿CLI: draft -> gate -> approve -> post.
# postは公式XDKのOAuth2 user contextだけを使い、承認・認証・画像上限をfail-closeする。
set -euo pipefail
export LC_ALL=C.UTF-8

SELF_PATH="${BASH_SOURCE[0]:-$0}"
[[ "$SELF_PATH" = /* ]] || SELF_PATH="$PWD/$SELF_PATH"
SCRIPT_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DRAFTS_DIR="${X_POST_DRAFTS_DIR:-$REPO_ROOT/queue/x_drafts}"
LEDGER_FILE="${X_POST_LEDGER_FILE:-$REPO_ROOT/skills/x-post-pipeline/stock_ledger.yaml}"
SLOT_CALENDAR_FILE="${X_POST_SLOT_CALENDAR_FILE:-$REPO_ROOT/skills/x-post-pipeline/slot_calendar.yaml}"
# 2026-09-04 12:50 殿裁定(方針の根本見直し): v5=投資・数学・検証の人の文体、DM-Signal は主語にしない
SYSTEM_PROMPT_FILE="${X_POST_SYSTEM_PROMPT_FILE:-$REPO_ROOT/skills/x-post-pipeline/system_prompt_v5.txt}"
LEDGER_LOOKUP="${X_POST_LEDGER_LOOKUP:-$SCRIPT_DIR/x_post_ledger_lookup.py}"
GATE_SCRIPT="${X_POST_GATE_SCRIPT:-$SCRIPT_DIR/x_post_gate.sh}"
NTFY_SCRIPT="${X_POST_NTFY_SCRIPT:-$REPO_ROOT/scripts/ntfy_action.sh}"
API_ENV_FILE="${X_POST_API_ENV_FILE:-$REPO_ROOT/config/x_api.env}"
TOKEN_REFRESH_SCRIPT="${X_TOKEN_REFRESH_SCRIPT:-$SCRIPT_DIR/x_token_refresh.py}"
FAILURE_LOG_FILE="${X_POST_FAILURE_LOG:-$REPO_ROOT/logs/x_post_draft_failures.log}"

if [[ -n "${X_POST_LLM_CMD:-}" ]]; then
    LLM_CMD="$X_POST_LLM_CMD"
else
    # latest Claude正本を既定にする(pinned ~/bin/claudeはモデル未対応のAPI Error 400を返す)。
    # モデル名は指定しない(未指定=CLI既定)。オペレータがX_POST_LLM_MODELを設定した時のみ付与する。
    LLM_LATEST_BIN="$HOME/.local/bin/claude"
    [[ -x "$LLM_LATEST_BIN" ]] || LLM_LATEST_BIN="claude"
    LLM_CMD='timeout '"${X_POST_LLM_TIMEOUT:-150}"' '"$LLM_LATEST_BIN"' --print'
    if [[ -n "${X_POST_LLM_MODEL:-}" ]]; then
        LLM_CMD+=' --model "$X_POST_LLM_MODEL"'
    fi
    # system_prompt_v4.txtの内容をsystem promptとして分離注入する。
    # (stdinへ混入させるとClaudeが前置き・見出し・区切り線を書く傾向が実測で確認されたため)
    LLM_CMD+=' --system-prompt "$SYSTEM_PROMPT_TEXT"'
fi
# 2026-09-04 10:38 殿裁定: 免責文(『教育目的。推奨ではない。過去は将来を保証しない。』)は蛇足。言い訳を
# 投稿本文に付けるのは論理的におかしい→合成しない。空文字なら compose は URL のみを付ける。
X_POST_DISCLAIMER=''

usage() {
    cat >&2 <<'EOF'
Usage:
  x_post.sh draft <slot> <ledger_key>
  x_post.sh gate <draft_id> <slot>
  x_post.sh approve <draft_id>
  x_post.sh post <draft_id> [--media <png>]
EOF
    exit 2
}

draft_file() { printf '%s/%s.txt' "$DRAFTS_DIR" "$1"; }
approved_file() { printf '%s/%s.approved' "$DRAFTS_DIR" "$1"; }
posted_file() { printf '%s/%s.posted' "$DRAFTS_DIR" "$1"; }

# 失敗理由(パターン名・安全な要約のみ)を永続ログへ残す。秘密値(トークン等)は一切含めない。
log_draft_failure() {
    local draft_id="$1" slot="$2" key="$3" reasons="$4"
    mkdir -p "$(dirname "$FAILURE_LOG_FILE")"
    printf '%s draft_id=%s slot=%s key=%s reasons=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$draft_id" "$slot" "$key" "$reasons" >> "$FAILURE_LOG_FILE"
}

cmd_draft() {
    local slot="${1:-}" key="${2:-}"
    [[ "$slot" =~ ^[A-G]$ ]] && [[ -n "$key" ]] || {
        echo "x_post.sh draft: slot A-G and ledger_key are required" >&2
        exit 2
    }
    [[ -f "$LEDGER_FILE" && -f "$LEDGER_LOOKUP" ]] || {
        echo "x_post.sh draft: ledger or lookup helper not found" >&2
        exit 2
    }
    local lookup_args=("$LEDGER_FILE" "$key")
    if [[ -f "$SLOT_CALENDAR_FILE" ]]; then
        lookup_args+=("$SLOT_CALENDAR_FILE" "$slot")
    fi
    local record
    if ! record="$(python3 "$LEDGER_LOOKUP" "${lookup_args[@]}")"; then
        echo "x_post.sh draft: ledger key or slot not found: $key/$slot" >&2
        exit 1
    fi
    [[ -f "$SYSTEM_PROMPT_FILE" ]] || {
        echo "x_post.sh draft: system prompt not found: $SYSTEM_PROMPT_FILE" >&2
        exit 2
    }

    mkdir -p "$DRAFTS_DIR"
    local draft_id="$(date -u +%Y-%m-%d)_${slot}"
    local output_file prompt_file composed_file
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    composed_file="$(mktemp)"
    trap 'rm -f "$prompt_file" "$output_file" "$composed_file"' RETURN
    {
        printf '\n--- slot instruction ---\nslot: %s\n' "$slot"
        python3 - "$record" <<'PY'
import json, sys
record = json.loads(sys.argv[1])
entry = record.get("entry", record)
slot = record.get("slot", {})
for label, value in (
    ("angle", slot.get("angle", "")),
    ("draft_seed", slot.get("draft_seed", "")),
    ("url", entry.get("url", "")),
    ("title", entry.get("title", "")),
    ("usable_numbers", slot.get("usable_numbers") or entry.get("usable_numbers", "")),
    ("first_line_candidate", entry.get("first_line_candidate", "")),
):
    print(f"{label}: {value}")
PY
    } > "$prompt_file"

    local system_prompt_text
    system_prompt_text="$(cat "$SYSTEM_PROMPT_FILE")"
    if ! SYSTEM_PROMPT_TEXT="$system_prompt_text" X_POST_LLM_MODEL="${X_POST_LLM_MODEL:-}" bash -c "$LLM_CMD" < "$prompt_file" > "$output_file"; then
        echo "x_post.sh draft: LLM command failed" >&2
        exit 1
    fi

    local ledger_usable_numbers ledger_url
    ledger_usable_numbers="$(python3 -c '
import json, sys
record = json.loads(sys.argv[1])
entry = record.get("entry", record)
slot = record.get("slot", {})
print(slot.get("usable_numbers") or entry.get("usable_numbers", ""))
' "$record")"
    ledger_url="$(python3 -c '
import json, sys
record = json.loads(sys.argv[1])
entry = record.get("entry", record)
print(entry.get("url", ""))
' "$record")"

    local validation_reasons
    if ! validation_reasons="$(X_POST_VALIDATE_NUMBERS="$ledger_usable_numbers" X_POST_VALIDATE_URL="$ledger_url" python3 - "$output_file" <<'PY'
import os, re, sys

path = sys.argv[1]
usable_numbers = os.environ.get("X_POST_VALIDATE_NUMBERS", "")
allowed_url = os.environ.get("X_POST_VALIDATE_URL", "")

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    text = fh.read()

reasons = []
raw_bytes = len(text.encode("utf-8"))

for pat in ("Execution error", "API Error", "invalid_request_error", "error_code"):
    if pat in text:
        reasons.append(f"error_pattern:{pat}")

if raw_bytes < 40:
    reasons.append(f"too_short_bytes:{raw_bytes}")

META_LINE_PATTERNS = [
    r"^-{3,}\s*$",
    r"^\*\*.+\*\*\s*$",
    r"以下が",
    r"本文です",
    r"字\(全角換算",
    r"字以内",
    r"最終投稿",
    r"\[MEM:",
    r"^angle:",
    r"^draft_seed:",
    r"^usable_numbers:",
    r"^slot:",
    r"^first_line_candidate:",
]
for line in text.splitlines():
    for pat in META_LINE_PATTERNS:
        if re.search(pat, line):
            reasons.append(f"meta_word:{pat}")

urls = re.findall(r'https?://[^\s<>"]+', text)
url_set = set(urls)
if allowed_url:
    # LLMは本文のみを担当する。URLはscript側が台帳から合成するため、
    # 本文中にURLが無いこと自体はFAILにしない。ただし台帳外URLの混入はFAILとする。
    bad_urls = sorted(u for u in url_set if allowed_url not in u)
    if bad_urls:
        reasons.append(f"url_mismatch:{','.join(bad_urls)}")
elif url_set:
    reasons.append(f"url_unexpected:{','.join(sorted(url_set))}")

text_no_url = re.sub(r'https?://[^\s<>"]+', "", text)
char_count = len(text_no_url.strip())
if char_count > 280:
    reasons.append(f"too_long_chars:{char_count}")

# 免責はscript側が固定文言を合成するため、本文中に無いこと自体はFAILにしない。

allowed_numbers = set(re.findall(r"\d+(?:\.\d+)?", usable_numbers or ""))
body_numbers = set(re.findall(r"\d+(?:\.\d+)?", text_no_url))
off_ledger = sorted(body_numbers - allowed_numbers)
if off_ledger:
    reasons.append(f"off_ledger_numbers:{','.join(off_ledger)}")

if reasons:
    print(";".join(reasons))
    sys.exit(1)
sys.exit(0)
PY
    )"; then
        echo "x_post.sh draft: invalid LLM output, draft not saved: $validation_reasons" >&2
        log_draft_failure "$draft_id" "$slot" "$key" "$validation_reasons"
        exit 1
    fi

    # LLM本文からURL/免責の重複混入を除去し、台帳由来URLと固定免責をscript側で決定的に合成する。
    if ! X_POST_COMPOSE_URL="$ledger_url" X_POST_COMPOSE_DISCLAIMER="$X_POST_DISCLAIMER" python3 - "$output_file" > "$composed_file" <<'PY'
import os, re, sys

path = sys.argv[1]
url = os.environ.get("X_POST_COMPOSE_URL", "")
disclaimer = os.environ.get("X_POST_COMPOSE_DISCLAIMER", "")

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    text = fh.read()

text = re.sub(r'https?://[^\s<>"]+', "", text)
if disclaimer:
    text = text.replace(disclaimer, "")
body = text.strip()

parts = [body]
if url:
    parts.append(url)
if disclaimer:
    parts.append(disclaimer)
sys.stdout.write("\n".join(parts) + "\n")
PY
    then
        echo "x_post.sh draft: compose failed, draft not saved" >&2
        exit 1
    fi

    cp "$composed_file" "$(draft_file "$draft_id")"
    printf '%s\n' "$(draft_file "$draft_id")"
}

cmd_gate() {
    local draft_id="${1:-}" slot="${2:-}"
    [[ -n "$draft_id" && -n "$slot" ]] || { echo "x_post.sh gate: draft_id and slot are required" >&2; exit 2; }
    local file="$(draft_file "$draft_id")"
    [[ -f "$file" ]] || { echo "x_post.sh gate: draft not found: $file" >&2; exit 2; }
    [[ -x "$GATE_SCRIPT" || -f "$GATE_SCRIPT" ]] || { echo "x_post.sh gate: gate not found" >&2; exit 2; }
    bash "$GATE_SCRIPT" "$file" "$slot"
}

cmd_approve() {
    local draft_id="${1:-}"
    [[ -n "$draft_id" ]] || { echo "x_post.sh approve: draft_id is required" >&2; exit 2; }
    local file="$(draft_file "$draft_id")"
    [[ -f "$file" ]] || { echo "x_post.sh approve: draft not found: $file" >&2; exit 2; }
    local message
    message="X投稿の承認待ち\ndraft: $file\n---\n$(cat "$file")"
    if ! bash "$NTFY_SCRIPT" "$message"; then
        echo "x_post.sh approve: notification failed" >&2
        exit 1
    fi
    local marker="$(approved_file "$draft_id")"
    local wait_seconds="${X_POST_APPROVAL_WAIT_SECONDS:-300}"
    [[ "$wait_seconds" =~ ^[0-9]+$ ]] || wait_seconds=300
    local deadline=$((SECONDS + wait_seconds))
    while [[ ! -f "$marker" ]]; do
        (( SECONDS >= deadline )) && {
            echo "x_post.sh approve: approved marker not received: $marker" >&2
            exit 1
        }
        sleep 1
    done
    printf '%s\n' "$marker"
}

cmd_post() {
    local draft_id="${1:-}" media=""
    [[ -n "$draft_id" ]] || { echo "x_post.sh post: draft_id is required" >&2; exit 2; }
    shift || true
    if [[ "${1:-}" = "--media" ]]; then
        media="${2:-}"
        [[ -n "$media" && -z "${3:-}" ]] || { echo "x_post.sh post: --media requires one PNG" >&2; exit 2; }
    elif [[ -n "${1:-}" ]]; then
        echo "x_post.sh post: unknown argument: $1" >&2
        exit 2
    fi
    local file="$(draft_file "$draft_id")" marker="$(approved_file "$draft_id")" posted="$(posted_file "$draft_id")"
    [[ -f "$file" ]] || { echo "x_post.sh post: draft not found: $file" >&2; exit 2; }
    [[ -f "$marker" ]] || { echo "x_post.sh post: not approved, stopping: $draft_id" >&2; exit 1; }
    if [[ -f "$posted" ]]; then
        echo "x_post.sh post: already posted, stopping: $draft_id" >&2
        exit 1
    fi
    if [[ -n "$media" ]]; then
        [[ -f "$media" ]] || { echo "x_post.sh post: media not found: $media" >&2; exit 2; }
        [[ "$media" = *.png ]] || { echo "x_post.sh post: media must be a PNG" >&2; exit 2; }
        local size
        size="$(stat -c '%s' "$media")"
        (( size <= 5242880 )) || { echo "x_post.sh post: media exceeds 5MB" >&2; exit 2; }
    fi
    [[ -f "$API_ENV_FILE" ]] || { echo "x_post.sh post: credentials file not found: $API_ENV_FILE" >&2; exit 2; }
    [[ -f "$TOKEN_REFRESH_SCRIPT" ]] || { echo "x_post.sh post: token refresh helper not found: $TOKEN_REFRESH_SCRIPT" >&2; exit 2; }
    if ! python3 "$TOKEN_REFRESH_SCRIPT" "$API_ENV_FILE" >/dev/null 2>&1; then
        echo "x_post.sh post: token refresh failed" >&2
        exit 1
    fi
    local python_status result_file
    result_file="$(mktemp)"
    export X_POST_RESULT_FILE="$result_file"
    set +e
    python3 - "$file" "$media" "$API_ENV_FILE" "$posted" <<'PY'
import base64, json, os, sys, tempfile, time
from collections.abc import Mapping
from pathlib import Path

draft_path, media_path, env_path, posted_path = sys.argv[1:]
values = {}
for line in Path(env_path).read_text(encoding="utf-8").splitlines():
    if "=" not in line or line.lstrip().startswith("#"):
        continue
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip().strip('"').strip("'")
access = values.get("X_ACCESS_TOKEN", "").strip()
refresh = values.get("X_REFRESH_TOKEN", "").strip()
token_json = values.get("X_TOKEN_JSON", "").strip()
if token_json:
    try:
        tokens = json.loads(token_json)
    except json.JSONDecodeError:
        print("x_post.sh post: X_TOKEN_JSON is invalid", file=sys.stderr)
        raise SystemExit(2)
else:
    tokens = {"access_token": access}
    if refresh:
        tokens["refresh_token"] = refresh
if not access and not tokens.get("access_token"):
    print("x_post.sh post: token empty", file=sys.stderr)
    raise SystemExit(2)


def token_fields(token):
    if hasattr(token, "model_dump"):
        token = token.model_dump(exclude_none=True)
    if isinstance(token, Mapping):
        return {
            "access_token": token.get("access_token"),
            "refresh_token": token.get("refresh_token"),
        }
    return {
        "access_token": getattr(token, "access_token", None),
        "refresh_token": getattr(token, "refresh_token", None),
    }


def atomic_persist_tokens(path, token):
    refreshed = token_fields(token)
    access_value = str(refreshed.get("access_token") or access or "").strip()
    refresh_value = str(refreshed.get("refresh_token") or refresh or "").strip()
    if not access_value or not refresh_value:
        raise RuntimeError("post token is incomplete")
    replacements = {
        "X_ACCESS_TOKEN": access_value,
        "X_REFRESH_TOKEN": refresh_value,
    }
    lines = path.read_text(encoding="utf-8").splitlines()
    output = []
    seen = set()
    for line in lines:
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in replacements:
            output.append(f"{key}={replacements[key]}")
            seen.add(key)
        else:
            output.append(line)
    for key, value in replacements.items():
        if key not in seen:
            output.append(f"{key}={value}")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write("\n".join(output) + "\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp_name, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise
try:
    from xdk.oauth2_auth import OAuth2PKCEAuth
    from xdk import Client
except ImportError:
    print("x_post.sh post: official xdk is not installed", file=sys.stderr)
    raise SystemExit(2)

scope = "tweet.read tweet.write users.read media.write offline.access"
try:
    OAuth2PKCEAuth(
        client_id=values.get("X_CLIENT_ID") or None,
        client_secret=values.get("X_CLIENT_SECRET") or None,
        redirect_uri=values.get("X_REDIRECT_URI", "http://127.0.0.1:8585/callback"),
        scope=scope,
        token=tokens,
    )
    try:
        client = Client(
            token=tokens,
            client_id=values.get("X_CLIENT_ID") or None,
            client_secret=values.get("X_CLIENT_SECRET") or None,
            redirect_uri=values.get("X_REDIRECT_URI", "http://127.0.0.1:8585/callback"),
            scope=scope,
        )
    except TypeError:
        client = Client(token=tokens)
    payload = {"text": Path(draft_path).read_text(encoding="utf-8")}
    if media_path:
        raw = base64.b64encode(Path(media_path).read_bytes()).decode("ascii")
        media_id = None
        try:
            from xdk.media.models import UploadRequest
            upload_body = UploadRequest(media=raw, media_category="tweet_image")
            response = client.media.upload(body=upload_body)
        except (ImportError, AttributeError, TypeError):
            response = client.media.upload(media_path)
        data = response.get("data") if isinstance(response, dict) else getattr(response, "data", None)
        if isinstance(data, dict):
            media_id = data.get("id")
        else:
            media_id = getattr(data, "id", None)
        media_id = media_id or (response.get("id") if isinstance(response, dict) else getattr(response, "id", None))
        if not media_id:
            raise RuntimeError("media upload returned no media_id")
        payload["media"] = {"media_ids": [str(media_id)]}
    try:
        response = client.posts.create(post_data=payload)
    except TypeError:
        try:
            from xdk.posts.models import CreateRequest
            response = client.posts.create(body=CreateRequest(**payload))
        except (ImportError, AttributeError, TypeError):
            response = client.posts.create(body=payload)
except Exception as exc:
    status = getattr(getattr(exc, "response", None), "status_code", None)
    if status == 401 or "401" in str(exc):
        print("x_post.sh post: unauthorized (HTTP 401)", file=sys.stderr)
    else:
        print(f"x_post.sh post: XDK request failed: {type(exc).__name__}", file=sys.stderr)
    raise SystemExit(1)

def as_json(value):
    if isinstance(value, Mapping):
        return {
            key: as_json(item)
            for key, item in value.items()
            if key.lower() not in {"access_token", "refresh_token", "token"}
        }
    if hasattr(value, "model_dump"):
        return as_json(value.model_dump(exclude_none=True))
    if isinstance(value, list):
        return [as_json(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)

result = as_json(response)
result_json = json.dumps(result, ensure_ascii=False)
Path(os.environ["X_POST_RESULT_FILE"]).write_text(result_json, encoding="utf-8")


def write_posted_marker(token_persistence, error=None):
    marker = {
        "posted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "media": media_path,
        "token_persistence": token_persistence,
        "result": result,
    }
    if error:
        marker["error"] = error
    fd, tmp_name = tempfile.mkstemp(prefix=f".{Path(posted_path).name}.", suffix=".tmp", dir=Path(posted_path).parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(marker, out, ensure_ascii=False)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp_name, posted_path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


write_posted_marker("pending")
try:
    atomic_persist_tokens(Path(env_path), client.token)
except Exception:
    try:
        write_posted_marker("failed", "client token was not persisted")
    except Exception:
        pass
    print("x_post.sh post: token persistence failed", file=sys.stderr)
    raise SystemExit(1)
write_posted_marker("persisted")
PY
    python_status=$?
    set -e
    if (( python_status != 0 )); then exit "$python_status"; fi
    cat "$result_file"
    rm -f "$result_file"
    unset X_POST_RESULT_FILE
}

case "${1:-}" in
    draft) shift; cmd_draft "$@" ;;
    gate) shift; cmd_gate "$@" ;;
    approve) shift; cmd_approve "$@" ;;
    post) shift; cmd_post "$@" ;;
    *) usage ;;
esac
