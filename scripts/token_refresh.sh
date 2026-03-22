#!/usr/bin/env bash
# scripts/token_refresh.sh
# Claude OAuth accessToken 自動リフレッシュ
#
# Usage: bash scripts/token_refresh.sh [--account primary|secondary|all]
# Env:   DRY_RUN=1           API呼び出しをスキップ（テスト用）
#        OAUTH_CLIENT_ID     OAuth client ID（未設定時は内部定数を使用）
#        CURL_TIMEOUT        curl タイムアウト秒数（デフォルト: 30）
#
# 注入教訓:
#   L016: refreshTokenは1回限り使用。リフレッシュ後は新しいrefreshTokenを必ず保存
#   L015: CLAUDE_CONFIG_DIR=~/.claude丸ごと切替、CLAUDE_CODE_OAUTH_TOKEN=認証のみ切替

set -euo pipefail

# ─── 定数 ────────────────────────────────────────────────────────────
readonly TOKEN_ENDPOINT="https://platform.claude.com/v1/oauth/token"
readonly CLIENT_ID="${OAUTH_CLIENT_ID:-9d1c250a-e61b-44d9-88ed-5944d1962f5e}"
readonly CURL_TIMEOUT="${CURL_TIMEOUT:-30}"
readonly SCOPES="user:inference user:mcp_servers user:profile user:sessions:claude_code"

# ─── 引数デフォルト ────────────────────────────────────────────────────
ACCOUNT_ARG="all"
DRY_RUN="${DRY_RUN:-0}"

# ─── 引数解析 ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)
      ACCOUNT_ARG="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      printf '[ERROR] Unknown argument: %s\n' "$1" >&2
      printf 'Usage: %s [--account primary|secondary|all]\n' "$0" >&2
      exit 1
      ;;
  esac
done

if [[ "$ACCOUNT_ARG" != "primary" && "$ACCOUNT_ARG" != "secondary" && "$ACCOUNT_ARG" != "all" ]]; then
  printf '[ERROR] --account must be primary, secondary, or all\n' >&2
  exit 1
fi

# ─── ログ関数 ──────────────────────────────────────────────────────────
log_info() {
  printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >&2
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"
}

# ─── 依存チェック ──────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required. Install: sudo apt-get install jq"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  log_error "curl is required but not found"
  exit 1
fi

# ─── トークンリフレッシュ関数 ────────────────────────────────────────
# L016: refreshTokenは単一使用トークン。
#       リフレッシュ後は必ずレスポンスの新refreshTokenを保存すること
refresh_account() {
  local config_dir="$1"
  local account_name="$2"
  local credentials_file="${config_dir}/.credentials.json"
  local lock_file="${config_dir}/.credentials.json.lock"

  log_info "[${account_name}] Processing: ${credentials_file}"

  if [[ ! -f "$credentials_file" ]]; then
    log_error "[${account_name}] credentials file not found: ${credentials_file}"
    return 1
  fi

  # ─── refreshToken取得 ─────────────────────────────────────────────
  local refresh_token
  refresh_token=$(jq -r '.claudeAiOauth.refreshToken // empty' "$credentials_file" 2>/dev/null)

  if [[ -z "$refresh_token" ]]; then
    log_error "[${account_name}] refreshToken not found in ${credentials_file}"
    return 1
  fi

  # ─── expiresAt確認（ログ用） ──────────────────────────────────────
  local expires_at now_ms remaining_min
  expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' "$credentials_file" 2>/dev/null)
  now_ms=$(date +%s%3N)
  if [[ "$expires_at" -gt "$now_ms" ]]; then
    remaining_min=$(( (expires_at - now_ms) / 60000 ))
    log_info "[${account_name}] Current token expires in ${remaining_min} min. Refreshing anyway."
  else
    log_info "[${account_name}] Current token has expired. Refreshing."
  fi

  # ─── DRY_RUN モード ──────────────────────────────────────────────
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "[${account_name}] DRY_RUN=1: skipping API call"
    log_info "[${account_name}] Would POST to: ${TOKEN_ENDPOINT}"
    log_info "[${account_name}] grant_type=refresh_token, client_id=${CLIENT_ID}"
    log_info "[${account_name}] refreshToken length=${#refresh_token}"
    log_info "[${account_name}] DRY_RUN complete (no changes made)"
    return 0
  fi

  # ─── OAuth token endpoint へ POST ────────────────────────────────
  log_info "[${account_name}] Requesting token refresh..."

  local raw_response http_code response_body
  local json_body
  json_body=$(jq -n \
    --arg gt "refresh_token" \
    --arg rt "$refresh_token" \
    --arg ci "$CLIENT_ID" \
    --arg sc "$SCOPES" \
    '{grant_type: $gt, refresh_token: $rt, client_id: $ci, scope: $sc}')

  raw_response=$(curl -s -w '\n%{http_code}' \
    --max-time "${CURL_TIMEOUT}" \
    -X POST "${TOKEN_ENDPOINT}" \
    -H "Content-Type: application/json" \
    -d "$json_body" \
    2>/dev/null) || {
    log_error "[${account_name}] curl failed (network error or timeout)"
    return 1
  }

  http_code=$(printf '%s' "$raw_response" | tail -1)
  response_body=$(printf '%s' "$raw_response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    log_error "[${account_name}] Token refresh failed: HTTP ${http_code}"
    log_error "[${account_name}] Response: $(printf '%s' "$response_body" | head -c 300)"
    return 1
  fi

  # ─── レスポンスからトークン抽出 ──────────────────────────────────
  local new_access_token new_refresh_token new_expires_in
  new_access_token=$(printf '%s' "$response_body" | jq -r '.access_token // .accessToken // empty' 2>/dev/null)
  # L016: refreshTokenが返ってきた場合は必ず保存する（単一使用トークン）
  new_refresh_token=$(printf '%s' "$response_body" | jq -r '.refresh_token // .refreshToken // empty' 2>/dev/null)
  new_expires_in=$(printf '%s' "$response_body" | jq -r '.expires_in // empty' 2>/dev/null)

  if [[ -z "$new_access_token" ]]; then
    log_error "[${account_name}] No access_token in response"
    log_error "[${account_name}] Response: $(printf '%s' "$response_body" | head -c 300)"
    return 1
  fi

  if [[ -z "$new_refresh_token" ]]; then
    log_warn "[${account_name}] No refresh_token in response. Keeping existing token."
    new_refresh_token="$refresh_token"
  fi

  # ─── expiresAt計算（ミリ秒タイムスタンプ） ──────────────────────
  local new_expires_at_ms
  if [[ -n "$new_expires_in" && "$new_expires_in" =~ ^[0-9]+$ ]]; then
    new_expires_at_ms=$(( $(date +%s%3N) + new_expires_in * 1000 ))
  else
    new_expires_at_ms=$(( $(date +%s%3N) + 3600000 ))
    log_warn "[${account_name}] Could not parse expires_in. Setting expiresAt to 1 hour from now."
  fi

  # ─── flock排他制御でcredentials.json書き戻し ─────────────────────
  # L016: accessToken+refreshToken+expiresAtを原子的に更新
  (
    flock -w 10 200 || { log_error "[${account_name}] Failed to acquire lock"; exit 1; }

    TR_TMP="${credentials_file}.tmp.$$"
    jq \
      --arg at  "$new_access_token" \
      --arg rt  "$new_refresh_token" \
      --argjson ea "$new_expires_at_ms" \
      '.claudeAiOauth.accessToken = $at |
       .claudeAiOauth.refreshToken = $rt |
       .claudeAiOauth.expiresAt = $ea' \
      "$credentials_file" > "$TR_TMP"

    mv "$TR_TMP" "$credentials_file"

    log_info "[${account_name}] credentials.json updated successfully"
    log_info "[${account_name}] accessToken length=${#new_access_token}, expiresAt=${new_expires_at_ms}"
  ) 200>"$lock_file"

  return 0
}

# ─── メイン ────────────────────────────────────────────────────────────
PRIMARY_DIR="${HOME}/.claude"
SECONDARY_DIR="${HOME}/.claude-secondary"
OVERALL_EXIT=0

log_info "token_refresh.sh start. account=${ACCOUNT_ARG} dry_run=${DRY_RUN}"

case "$ACCOUNT_ARG" in
  primary)
    refresh_account "$PRIMARY_DIR" "primary" || OVERALL_EXIT=$?
    ;;
  secondary)
    if [[ ! -d "$SECONDARY_DIR" ]]; then
      log_error "Secondary account directory not found: ${SECONDARY_DIR}"
      exit 1
    fi
    refresh_account "$SECONDARY_DIR" "secondary" || OVERALL_EXIT=$?
    ;;
  all)
    refresh_account "$PRIMARY_DIR" "primary" || OVERALL_EXIT=$?
    if [[ -d "$SECONDARY_DIR" && -f "${SECONDARY_DIR}/.credentials.json" ]]; then
      refresh_account "$SECONDARY_DIR" "secondary" || OVERALL_EXIT=$?
    else
      log_info "[secondary] skipped: directory or .credentials.json not found"
    fi
    ;;
esac

if [[ "$OVERALL_EXIT" -eq 0 ]]; then
  log_info "All done. Token refresh completed successfully."
else
  log_error "Token refresh completed with errors (exit code: ${OVERALL_EXIT})"
  exit "$OVERALL_EXIT"
fi
