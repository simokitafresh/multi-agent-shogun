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
SYSTEM_PROMPT_FILE="${X_POST_SYSTEM_PROMPT_FILE:-$REPO_ROOT/skills/x-post-pipeline/system_prompt_v4.txt}"
LEDGER_LOOKUP="${X_POST_LEDGER_LOOKUP:-$SCRIPT_DIR/x_post_ledger_lookup.py}"
GATE_SCRIPT="${X_POST_GATE_SCRIPT:-$SCRIPT_DIR/x_post_gate.sh}"
NTFY_SCRIPT="${X_POST_NTFY_SCRIPT:-$REPO_ROOT/scripts/ntfy.sh}"
LLM_CMD="${X_POST_LLM_CMD:-claude --print}"
API_ENV_FILE="${X_POST_API_ENV_FILE:-$REPO_ROOT/config/x_api.env}"

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

cmd_draft() {
    local slot="${1:-}" key="${2:-}"
    [[ "$slot" =~ ^[A-E]$ ]] && [[ -n "$key" ]] || {
        echo "x_post.sh draft: slot A-E and ledger_key are required" >&2
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
    local output_file prompt_file
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    trap 'rm -f "$prompt_file" "$output_file"' RETURN
    {
        cat "$SYSTEM_PROMPT_FILE"
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
    if ! bash -c "$LLM_CMD" < "$prompt_file" > "$output_file"; then
        echo "x_post.sh draft: LLM command failed" >&2
        exit 1
    fi
    [[ -s "$output_file" ]] || { echo "x_post.sh draft: empty LLM output" >&2; exit 1; }
    cp "$output_file" "$(draft_file "$draft_id")"
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
    local file="$(draft_file "$draft_id")" marker="$(approved_file "$draft_id")"
    [[ -f "$file" ]] || { echo "x_post.sh post: draft not found: $file" >&2; exit 2; }
    [[ -f "$marker" ]] || { echo "x_post.sh post: not approved, stopping: $draft_id" >&2; exit 1; }
    if [[ -n "$media" ]]; then
        [[ -f "$media" ]] || { echo "x_post.sh post: media not found: $media" >&2; exit 2; }
        [[ "$media" = *.png ]] || { echo "x_post.sh post: media must be a PNG" >&2; exit 2; }
        local size
        size="$(stat -c '%s' "$media")"
        (( size <= 5242880 )) || { echo "x_post.sh post: media exceeds 5MB" >&2; exit 2; }
    fi
    [[ -f "$API_ENV_FILE" ]] || { echo "x_post.sh post: credentials file not found: $API_ENV_FILE" >&2; exit 2; }
    local python_status result_file
    result_file="$(mktemp)"
    export X_POST_RESULT_FILE="$result_file"
    set +e
    python3 - "$file" "$media" "$API_ENV_FILE" <<'PY'
import base64, json, os, sys
from pathlib import Path

draft_path, media_path, env_path = sys.argv[1:]
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
    if isinstance(value, dict):
        return value
    if hasattr(value, "model_dump"):
        return value.model_dump(exclude_none=True)
    return {"response": str(value)}

result = as_json(response)
print(json.dumps(result, ensure_ascii=False))
Path(os.environ["X_POST_RESULT_FILE"]).write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
PY
    python_status=$?
    set -e
    if (( python_status != 0 )); then exit "$python_status"; fi
    printf 'posted_at=%s\nmedia=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$media" > "$(posted_file "$draft_id")"
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
