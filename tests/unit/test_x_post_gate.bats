#!/usr/bin/env bats
# test_necessity: x_post_gate.sh is the sole fail-close checkpoint before any X post reaches the
# API (P1). Regression here means a holding/ticker leak, a standalone multiplier, a disallowed
# URL, a missing disclaimer, a forbidden word, or first-line internal jargon could reach
# production posting undetected.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GATE="$PROJECT_ROOT/scripts/x_ops/x_post_gate.sh"
    FIXTURE_DIR="$BATS_TEST_TMPDIR"

    cat > "$FIXTURE_DIR/signals.json" <<'EOF'
{"data":{"portfolios":[{"name":"Basic-DualMomentum","signal":"XLU"},{"name":"Premium-ShinYotsume","signal":"XLK 100.0%"}]}}
EOF
    export X_GATE_SIGNALS_JSON="$FIXTURE_DIR/signals.json"
}

run_gate() {
    run bash "$GATE" "$1"
}

@test "PASS: 枠A教材再掲の下書き(数字なし、免責なし、許可URLのみ)" {
    cat > "$FIXTURE_DIR/pass_a.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。その資産は現金より強いか。弱ければ退避。確認は月1回。

詳細と検証は無料ガイド。
https://note.com/tokyojibika/n/n171daa7f92a1
EOF
    run_gate "$FIXTURE_DIR/pass_a.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

@test "PASS: 枠B検証の一切れの下書き(倍率は期間/CAGR/MaxDD/ベンチと同一段落)" {
    cat > "$FIXTURE_DIR/pass_b.txt" <<'EOF'
市場の追い風を差し引いた実力を検証した。
2011年〜2026年の約14年間、SPYは年率15.6%、対する検証対象は年率101.9%。最大ドローダウンはSPY-23.8%に対し-17.7%だった。

期間と前提は記事に全部ある。
https://note.com/tokyojibika/n/n171daa7f92a1
EOF
    run_gate "$FIXTURE_DIR/pass_b.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

@test "FAIL rule1: Basic-DualMomentum以外の保有ticker(XLK)が本文にあればFAIL" {
    cat > "$FIXTURE_DIR/fail1.txt" <<'EOF'
プレミアム限定戦略はXLKを中心に運用しています。
EOF
    run_gate "$FIXTURE_DIR/fail1.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule1_holding_or_ticker_leak:XLK"* ]]
}

@test "FAIL rule2: 単独倍率(期間/CAGR/MaxDD/ベンチのいずれとも同一段落に無い)はFAIL" {
    cat > "$FIXTURE_DIR/fail2.txt" <<'EOF'
このポートフォリオは資産を7倍にしました。
EOF
    run_gate "$FIXTURE_DIR/fail2.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule2_standalone_multiplier"* ]]
}

@test "FAIL rule3: 完全ガイド/How toマガジン/dm-signal.com以外のURLはFAIL" {
    cat > "$FIXTURE_DIR/fail3.txt" <<'EOF'
詳細はこちら。
https://example.com/spam
EOF
    run_gate "$FIXTURE_DIR/fail3.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule3_disallowed_url:https://example.com/spam"* ]]
}

@test "FAIL rule4: 免責・言い訳文(教育目的/推奨ではない/保証しない)があればFAIL(殿裁定 2026-09-04)" {
    draft="$(mktemp)"
    cat >"$draft" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か、その資産は現金より強いか。
https://note.com/tokyojibika/n/n171daa7f92a1
教育目的。推奨ではない。過去は将来を保証しない。
EOF
    run bash "$GATE" "$draft" A
    [ "$status" -ne 0 ]
    [[ "$output" == *"rule4_disclaimer_present"* ]]
}

@test "FAIL rule5: 禁止語(劇薬など)があればFAIL" {
    cat > "$FIXTURE_DIR/fail5.txt" <<'EOF'
この劇薬のような戦略はすごい。
EOF
    run_gate "$FIXTURE_DIR/fail5.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule5_forbidden_word:劇薬"* ]]
}

@test "FAIL rule6: 第一文に内部用語(FoFなど)があればFAIL" {
    cat > "$FIXTURE_DIR/fail6.txt" <<'EOF'
FoFの仕組みで運用しています。
EOF
    run_gate "$FIXTURE_DIR/fail6.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule6_internal_term_in_first_line:FoF"* ]]
}

# test_necessity: /api/signals のweight付きticker表記("TMV 50.0%"のような重み付き構成ticker)が
# blocklist生成時に正しく単一tickerへ剥離されないと、非公開FoFのholdingがgateをすり抜ける
# (cmd_karo_hotfix_x_post_gate_blocklist_fail_close_202609031003の直接契機)。
@test "FAIL rule1(signals API): 非BasicのFoF重み付きholding(TMV等)を含む下書きはFAIL" {
    cat > "$FIXTURE_DIR/signals_fof.json" <<'EOF'
{"data":{"portfolios":[{"name":"Basic-DualMomentum","signal":"XLU"},{"name":"裏Ave-X","signal":"GLD 50.0%, TMV 50.0%"}]}}
EOF
    export X_GATE_SIGNALS_JSON="$FIXTURE_DIR/signals_fof.json"
    cat > "$FIXTURE_DIR/fail_fof.txt" <<'EOF'
プレミアム限定戦略はTMVを中心に運用しています。
EOF
    run_gate "$FIXTURE_DIR/fail_fof.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule1_holding_or_ticker_leak:TMV"* ]]
}

# test_necessity: 本番API不達(接続失敗)時にblocklistが取得できないと、旧実装は{}へ
# 沈黙フォールバックしrule1が無条件でスキップされていた(殿裁定B-6違反)。fail-closeへの
# 転換を固定する回帰テスト。
@test "FAIL rule1: API不達(接続失敗)はfail-close" {
    unset X_GATE_SIGNALS_JSON
    export X_GATE_SIGNALS_URL="http://127.0.0.1:9/"
    cat > "$FIXTURE_DIR/fail_unreachable.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。
EOF
    run_gate "$FIXTURE_DIR/fail_unreachable.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"x_post_gate: FAIL rule1 blocklist unavailable (fail-close)"* ]]
}

# test_necessity: blocklistが空集合(非Basic全PFがBasicと同一holdingのみ、または
# portfolios自体が空)の時、旧実装はrule1を無条件PASS扱いした。空集合もfail-closeに
# 倒すことを固定する回帰テスト。
@test "FAIL rule1: blocklist空JSONはfail-close" {
    cat > "$FIXTURE_DIR/signals_empty.json" <<'EOF'
{"data":{"portfolios":[{"name":"Basic-DualMomentum","signal":"XLU"}]}}
EOF
    export X_GATE_SIGNALS_JSON="$FIXTURE_DIR/signals_empty.json"
    cat > "$FIXTURE_DIR/fail_empty_blocklist.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。
EOF
    run_gate "$FIXTURE_DIR/fail_empty_blocklist.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"x_post_gate: FAIL rule1 blocklist unavailable (fail-close)"* ]]
}

# test_necessity: x_post.sh のX API urllib境界をfixtureで固定する。承認なし・認証なし・
# media有無・201/401を同じCLIで確認し、誤投稿と画像media_id欠落を防ぐ。
setup_x_post() {
    X_POST="$PROJECT_ROOT/scripts/x_ops/x_post.sh"
    export X_POST_DRAFTS_DIR="$FIXTURE_DIR/x_drafts"
    export X_POST_API_ENV_FILE="$FIXTURE_DIR/x_api.env"
    export X_API_CALL_LOG="$FIXTURE_DIR/x_api_calls.log"
    mkdir -p "$X_POST_DRAFTS_DIR" "$FIXTURE_DIR/fake_api"
    cat > "$FIXTURE_DIR/fake_api/sitecustomize.py" <<'PY'
import io
import json
import os
import urllib.error
import urllib.request


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


def _urlopen(request, timeout=60):
    url = request.full_url
    body = request.data or b""
    with open(os.environ["X_API_CALL_LOG"], "a", encoding="utf-8") as log:
        log.write("request " + json.dumps({"url": url, "timeout": timeout}, sort_keys=True) + "\n")
    if os.environ.get("X_API_STATUS") == "401":
        raise urllib.error.HTTPError(url, 401, "unauthorized", {}, io.BytesIO(b'{"error":"unauthorized"}'))
    if url.endswith("/media/upload"):
        with open(os.environ["X_API_CALL_LOG"], "a", encoding="utf-8") as log:
            log.write("media " + body.decode("utf-8") + "\n")
        payload = {"data": {"id": "media-1"}}
    else:
        with open(os.environ["X_API_CALL_LOG"], "a", encoding="utf-8") as log:
            log.write("post " + body.decode("utf-8") + "\n")
        payload = {"data": {"id": "post-1"}}
    return _Response(json.dumps(payload).encode("utf-8"))


urllib.request.urlopen = _urlopen
PY
    cat > "$X_POST_DRAFTS_DIR/2026-09-03_A.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か、その資産は現金より強いか。
EOF
    printf 'approved\n' > "$X_POST_DRAFTS_DIR/2026-09-03_A.approved"
    cat > "$X_POST_API_ENV_FILE" <<'EOF'
X_CLIENT_ID=test-client-id
X_CLIENT_SECRET=test-client-secret
X_REDIRECT_URI=http://127.0.0.1:8585/callback
X_ACCESS_TOKEN=initial-access-token
X_REFRESH_TOKEN=initial-refresh-token
EOF
    chmod 600 "$X_POST_API_ENV_FILE"
    cat > "$FIXTURE_DIR/x_token_refresh_stub.py" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
if os.environ.get("X_REFRESH_FAIL") == "1":
    print("refresh failed with secret refresh-token", file=sys.stderr)
    raise SystemExit(1)
lines = path.read_text(encoding="utf-8").splitlines()
out = []
seen = set()
for line in lines:
    key = line.split("=", 1)[0] if "=" in line else ""
    if key == "X_ACCESS_TOKEN":
        out.append("X_ACCESS_TOKEN=refreshed-access-token")
        seen.add(key)
    elif key == "X_REFRESH_TOKEN" and os.environ.get("X_REFRESH_ROTATE") == "1":
        out.append("X_REFRESH_TOKEN=refreshed-rotated-refresh-token")
        seen.add(key)
    else:
        out.append(line)
path.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
    export X_TOKEN_REFRESH_SCRIPT="$FIXTURE_DIR/x_token_refresh_stub.py"
}

@test "x_post post: urllibでmediaなし201を投稿済みmarkerへ記録" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    [[ "$output" == *"post-1"* ]]
    ! grep -q '/media/upload' "$X_API_CALL_LOG"
    grep -q '/2/tweets' "$X_API_CALL_LOG"
    [ -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

# test_necessity: response serialization must preserve the API schema while removing only secret
# token keys; recursive scalar wrapping would corrupt the durable/API result shape.
@test "x_post post: API responseの非secret scalar構造を同値保持" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    python3 -c 'import json, sys; assert json.loads(sys.argv[1]) == {"data": {"id": "post-1"}}' "$output"
}

@test "x_post post: PNGをAPI media.uploadしmedia_ids付き201を投稿" {
    setup_x_post
    printf '\x89PNG\r\n\x1a\n' > "$FIXTURE_DIR/experience.png"
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A --media "$FIXTURE_DIR/experience.png"
    [ "$status" -eq 0 ]
    grep -q '^media ' "$X_API_CALL_LOG"
    grep -q '^post ' "$X_API_CALL_LOG"
    [ -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

@test "x_post post: API HTTP401は投稿済みmarkerを作らずexit1" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" X_API_STATUS=401 bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTTP 401"* ]]
    [ ! -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

@test "x_post post: 承認marker不在はAPIを呼ばずexit1" {
    setup_x_post
    rm -f "$X_POST_DRAFTS_DIR/2026-09-03_A.approved"
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"not approved"* ]]
    [ ! -f "$X_API_CALL_LOG" ]
}

@test "x_post post: creds file不在はexit2でAPIを呼ばない" {
    setup_x_post
    rm -f "$X_POST_API_ENV_FILE"
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 2 ]
    [[ "$output" == *"credentials file not found"* ]]
}

# test_necessity: refresh token rotation is performed by the helper before the API call; the
# urllib posting boundary must not rotate or rewrite tokens after a successful post.
@test "x_post post: refresh後のrotate済みtokenをhelper結果として保持" {
    setup_x_post
    export X_REFRESH_ROTATE=1
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
    grep -q '^X_REFRESH_TOKEN=refreshed-rotated-refresh-token$' "$X_POST_API_ENV_FILE"
    [ "$(stat -c '%a' "$X_POST_API_ENV_FILE")" = "600" ]
    [[ "$output" != *"refreshed-access-token"* ]]
    [[ "$output" != *"refreshed-rotated-refresh-token"* ]]
}

# test_necessity: the API boundary does not rotate refresh_token. The existing refresh token
# must remain usable while the newly refreshed access token is written back.
@test "x_post post: 非rotate時はrefresh tokenを保持しaccess tokenのみ更新" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
    grep -q '^X_REFRESH_TOKEN=initial-refresh-token$' "$X_POST_API_ENV_FILE"
}

# test_necessity: refresh failure is fail-closed and must prevent any API call or posted marker.
@test "x_post post: 投稿前refresh失敗はAPIを呼ばず投稿済みmarkerを作らない" {
    setup_x_post
    export X_REFRESH_FAIL=1
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"token refresh failed"* ]]
    [ ! -s "$X_API_CALL_LOG" ]
    [ ! -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
    grep -q '^X_ACCESS_TOKEN=initial-access-token$' "$X_POST_API_ENV_FILE"
    [[ "$output" != *"refresh-token"* ]]
}

# test_necessity: a post failure must not mutate credentials; only the refresh helper may advance
# local token state before the API request.
@test "x_post post: 投稿失敗時はAPI側token変異を永続化しない" {
    setup_x_post
    export X_API_STATUS=401
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTTP 401"* ]]
    [ ! -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
    grep -q '^X_REFRESH_TOKEN=initial-refresh-token$' "$X_POST_API_ENV_FILE"
    [[ "$output" != *"post-failed-refresh-token"* ]]
}

# test_necessity: the credentials file must end every refresh/API cycle with owner-only mode,
# even if an operator supplied a weaker mode before invocation.
@test "x_post post: refresh後のcredentials modeを0600へ固定" {
    setup_x_post
    chmod 640 "$X_POST_API_ENV_FILE"
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$X_POST_API_ENV_FILE")" = "600" ]
}

# test_necessity: a successful remote post must leave a durable posted marker and block retries,
# even though token persistence is owned by the pre-post refresh helper.
@test "x_post post: 成功markerを記録し再投稿を遮断" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    [ -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
    grep -q '"token_persistence": "persisted"' "$X_POST_DRAFTS_DIR/2026-09-03_A.posted"
    [ "$(grep -c '^post ' "$X_API_CALL_LOG")" -eq 1 ]
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"already posted"* ]]
    [ "$(grep -c '^post ' "$X_API_CALL_LOG")" -eq 1 ]
}

# x_token_keeper.sh(cron)へX_TOKEN_OBTAINED_ATを指定秒数前に見せかける。
set_token_obtained_age() {
    local env_file="$1" age_sec="$2" ts
    ts="$(date -u -d "@$(( $(date -u +%s) - age_sec ))" +%Y-%m-%dT%H:%M:%S%z)"
    if grep -q '^X_TOKEN_OBTAINED_AT=' "$env_file"; then
        sed -i "s/^X_TOKEN_OBTAINED_AT=.*/X_TOKEN_OBTAINED_AT=${ts}/" "$env_file"
    else
        printf 'X_TOKEN_OBTAINED_AT=%s\n' "$ts" >> "$env_file"
    fi
}

# test_necessity: x_token_keeper.sh(cron、90分閾値で成功時にX_TOKEN_OBTAINED_ATを更新)と
# x_post.shの投稿直前refreshが同時にrefresh_tokenをrotateすると、Xの再利用検知が後着の
# refreshでgrantをrevokeしうる(実測: keeper cronの実発火分がx_slot_post cronの分と一致する
# 時間帯を確認、cmd_karo_hotfix_x_refresh_collision_20260906 AC1)。keeperの直近refresh成功が
# 閾値内ならx_post.sh側refreshをskipする契約(AC2)の回帰を防ぐ。
@test "x_post post: keeperのrefresh成功が閾値内(90分)なら投稿直前refreshをskipする" {
    setup_x_post
    set_token_obtained_age "$X_POST_API_ENV_FILE" 600
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=initial-access-token$' "$X_POST_API_ENV_FILE"
    grep -q '/2/tweets' "$X_API_CALL_LOG"
}

# test_necessity: skipの誤爆が実際の同時rotation競合を再現する最悪ケース――keeperの
# refreshが(ロック等で)失敗しうる状況でも、fresh判定によりx_post.sh側は再度refresh
# helperを呼ばないことを固定する。呼んでいたらhelper失敗のfail-closeでexit 1になるはず。
@test "x_post post: 同時rotation競合re現時もfresh判定はrefresh helperを再度呼ばない" {
    setup_x_post
    set_token_obtained_age "$X_POST_API_ENV_FILE" 300
    export X_REFRESH_FAIL=1
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    [[ "$output" == *"post-1"* ]]
}

# test_necessity: keeperの成功記録が閾値(90分)を超えている場合はfail-closeし、
# 既存の必須refresh動作(AC2「90分超はfail closed」)を維持する回帰テスト。
@test "x_post post: keeper成功記録が閾値超過(90分超)なら投稿直前refreshをfail-closeで実行" {
    setup_x_post
    set_token_obtained_age "$X_POST_API_ENV_FILE" 5500
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
}

# test_necessity: X_TOKEN_OBTAINED_AT欠落はkeeper成功記録なしと同義であり、
# fail-closeで既存の必須refresh動作を維持する回帰テスト(AC2「成功記録欠落はfail closed」)。
@test "x_post post: X_TOKEN_OBTAINED_AT欠落は投稿直前refreshをfail-closeで実行" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
}

# test_necessity: X_TOKEN_OBTAINED_ATがparse不能(malformed)な場合もfail-closeし、
# 既存の必須refresh動作を維持する回帰テスト(AC2「malformedはfail closed」)。
@test "x_post post: X_TOKEN_OBTAINED_ATがmalformedなら投稿直前refreshをfail-closeで実行" {
    setup_x_post
    printf 'X_TOKEN_OBTAINED_AT=not-a-timestamp\n' >> "$X_POST_API_ENV_FILE"
    run env PYTHONPATH="$FIXTURE_DIR/fake_api" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    grep -q '^X_ACCESS_TOKEN=refreshed-access-token$' "$X_POST_API_ENV_FILE"
}

# draft生成テスト専用の軽量setup。setup_x_postはdate依存の固定ファイル名
# (2026-09-03_A.txt)を事前生成するため、当日日付での衝突を避けて分離する。
setup_x_post_minimal() {
    X_POST="$PROJECT_ROOT/scripts/x_ops/x_post.sh"
    export X_POST_DRAFTS_DIR="$FIXTURE_DIR/x_drafts_min"
    mkdir -p "$X_POST_DRAFTS_DIR"
}

setup_x_post_draft_ledger() {
    cat > "$FIXTURE_DIR/ledger.yaml" <<'EOF'
entries:
- key: demo
  url: https://note.com/tokyojibika/n/n171daa7f92a1
  title: デモ記事
  usable_numbers: '期間2020年〜2024年、CAGR 10%、MaxDD -20%、ベンチSPY'
  first_line_candidate: 最初の一文。
EOF
    cat > "$FIXTURE_DIR/slots.yaml" <<'EOF'
slots:
- slot: A
  angle: 定義
  draft_seed: 二つだけ見る。
  usable_numbers: '期間2020年〜2024年、CAGR 10%、MaxDD -20%、ベンチSPY'
EOF
    export X_POST_LEDGER_FILE="$FIXTURE_DIR/ledger.yaml"
    export X_POST_SLOT_CALENDAR_FILE="$FIXTURE_DIR/slots.yaml"
    export X_POST_SYSTEM_PROMPT_FILE="$PROJECT_ROOT/skills/x-post-pipeline/system_prompt_v4.txt"
}

# stdinを$X_POST_LLM_CAPTUREへ保存し、契約に準拠した本文をstdoutへ返すstub。
make_compliant_llm_stub() {
    cat > "$FIXTURE_DIR/llm_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > "$X_POST_LLM_CAPTURE"
cat <<'BODY'
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
https://note.com/tokyojibika/n/n171daa7f92a1
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_stub.sh"
}

# test_necessity: x_post.sh draft はLLM出力をそのままdraft保存する唯一の入口(P1)。
# system promptを分離注入し、台帳データ(angle/draft_seed等)がユーザーメッセージへ
# 正しく渡ることを固定する回帰テスト。Execution error/API Errorをdraft保存前に
# fail-closeする契約(cmd_karo_hotfix_x_draft_generation_contract_202609031802)の前提。
@test "x_post draft: slot instructionと台帳値をLLMへ注入し契約準拠の本文をdraft保存" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    make_compliant_llm_stub
    export X_POST_LLM_CAPTURE="$FIXTURE_DIR/llm_capture.txt"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 0 ]
    [[ "$output" == "$X_POST_DRAFTS_DIR/20"*"_A.txt" ]]
    grep -q '^angle: 定義$' "$FIXTURE_DIR/llm_capture.txt"
    grep -q '^draft_seed: 二つだけ見る。$' "$FIXTURE_DIR/llm_capture.txt"
    run bash "$GATE" "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# test_necessity: 過去に既定LLM(pinned CLI)がExecution errorをdraftへ丸ごと保存した
# 実障害(cmd_karo_hotfix_x_draft_generation_contract_202609031802起票根拠)の回帰テスト。
# fail-closeせず保存すると無効な投稿候補が承認導線に載る。
@test "x_post draft: LLM出力がExecution errorならdraft保存前にfail-close" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_error_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'Execution error'
EOF
    chmod +x "$FIXTURE_DIR/llm_error_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_error_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid LLM output"* ]]
    [[ "$output" == *"error_pattern:Execution error"* ]]
    [ ! -f "$X_POST_DRAFTS_DIR/$(date -u +%Y-%m-%d)_A.txt" ]
}

# test_necessity: latest ClaudeがAPI Error本文をrc=0で返す経路のfail-close回帰。
@test "x_post draft: LLM出力がAPI ErrorならFAIL・draft保存なし" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_apierr_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'API Error: 400 {"type":"error"}'
EOF
    chmod +x "$FIXTURE_DIR/llm_apierr_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_apierr_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"error_pattern:API Error"* ]]
}

# test_necessity: 40byte未満の短文出力(空・切断応答)はSNSに投稿できる本文たり得ない。
@test "x_post draft: 40byte未満の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_short_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'OK'
EOF
    chmod +x "$FIXTURE_DIR/llm_short_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_short_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"too_short_bytes"* ]]
}

# test_necessity: 「以下が最終投稿本文です」等のメタ発話混入は実測(latest Claude既定応答)で
# 再現した障害。本文と地の文が混在すると投稿がそのままメタ発話を含んでしまう。
@test "x_post draft: メタ語(前置き)混入の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_meta_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
以下が最終投稿本文です。
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
https://note.com/tokyojibika/n/n171daa7f92a1
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_meta_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_meta_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"meta_word"* ]]
}

# test_necessity: Markdown区切り線(---)混入は本文と前置き/補足の境界を示すメタ記法であり、
# 投稿本文に含めてはならない。
@test "x_post draft: 区切り線(---)混入の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_sep_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
---
https://note.com/tokyojibika/n/n171daa7f92a1
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_sep_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_sep_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"meta_word"* ]]
}

# test_necessity: 280字超はX投稿として成立しない長さであり、システムプロンプトの
# 140字目標を大きく逸脱した出力を機械的に弾く最終防御線。
@test "x_post draft: 280字超の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_long_stub.sh" <<EOF
#!/usr/bin/env bash
cat > /dev/null
printf '%s' "$(python3 -c "print('あ' * 300)")"
printf ''
EOF
    chmod +x "$FIXTURE_DIR/llm_long_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_long_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"too_long_chars"* ]]
}

# test_necessity: usable_numbersに無い数字(台帳外)の混入は誤った実績値のねつ造・誤記混入を
# 検出できないと防げない。殿裁定B-6(数字の欠落時不使用)の裏面。
@test "x_post draft: 台帳外数字混入の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_offnum_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
CAGR999%、MaxDD-20%、2020年〜2024年、SPY比較。
https://note.com/tokyojibika/n/n171daa7f92a1
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_offnum_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_offnum_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"off_ledger_numbers:999"* ]]
}

# test_necessity: ledgerが渡した1本以外のURLが混入すると、未許可リンクへの誘導になる。
@test "x_post draft: URL不一致の出力はFAIL" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_badurl_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
https://example.com/spam
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_badurl_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_badurl_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [[ "$output" == *"url_mismatch"* ]]
}

# test_necessity: LLMは本文のみを担当し、URLはscript側が台帳から決定的に合成する契約(AC1)。
# 本文にURLが無い出力でもfail-closeせず、合成後にgateがPASSすることを固定する回帰テスト。
@test "x_post draft: URL欠落LLM出力は台帳URL合成後gate PASS" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_nourl_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_nourl_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_nourl_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 0 ]
    local draft_path="$output"
    grep -qF 'https://note.com/tokyojibika/n/n171daa7f92a1' "$draft_path"
    run bash "$GATE" "$draft_path"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# test_necessity: 免責は合成しない契約(殿裁定 2026-09-04『言い訳は削除せよ』)。LLM が免責を書いても
# 本文でもfail-closeせず、合成後にgateがPASSすることを固定する回帰テスト。
@test "x_post draft: 免責は合成されない(殿裁定 2026-09-04)、URL 合成後 gate PASS" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    cat > "$FIXTURE_DIR/llm_nodisclaimer_stub.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
cat <<'BODY'
CAGR10%、MaxDD-20%、2020年〜2024年、SPY比較。
https://note.com/tokyojibika/n/n171daa7f92a1
BODY
EOF
    chmod +x "$FIXTURE_DIR/llm_nodisclaimer_stub.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_nodisclaimer_stub.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 0 ]
    local draft_path="$output"
    ! grep -qF '保証しない' "$draft_path"
    run bash "$GATE" "$draft_path"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# test_necessity: fail-close時の失敗理由はパターン名のみの安全な要約とし、秘密値(トークン等)を
# 含まず永続ログへ残す契約(AC1)を固定する回帰テスト。
@test "x_post draft: 失敗理由は秘密値なしで永続ログへ記録される" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    export X_POST_FAILURE_LOG="$FIXTURE_DIR/x_post_draft_failures.log"
    cat > "$FIXTURE_DIR/llm_short_stub2.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'OK'
EOF
    chmod +x "$FIXTURE_DIR/llm_short_stub2.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_short_stub2.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    [ -f "$X_POST_FAILURE_LOG" ]
    grep -q 'draft_id=' "$X_POST_FAILURE_LOG"
    grep -q 'reasons=too_short_bytes' "$X_POST_FAILURE_LOG"
    ! grep -qE 'X_ACCESS_TOKEN|X_CLIENT_SECRET|ADMIN_PASS|Bearer ' "$X_POST_FAILURE_LOG"
}

# test_necessity: fail-close発火時に既存の有効draftを破壊しないことを固定する回帰テスト。
# 上書きしてしまうと承認待ちの正常な下書きが無効出力で失われる。
@test "x_post draft: fail-close時は既存の有効draftを上書きしない" {
    setup_x_post_minimal
    setup_x_post_draft_ledger
    mkdir -p "$X_POST_DRAFTS_DIR"
    local existing="$X_POST_DRAFTS_DIR/$(date -u +%Y-%m-%d)_A.txt"
    printf '既存の有効な下書き本文。\n' > "$existing"
    cat > "$FIXTURE_DIR/llm_error_stub2.sh" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'Execution error'
EOF
    chmod +x "$FIXTURE_DIR/llm_error_stub2.sh"
    export X_POST_LLM_CMD="$FIXTURE_DIR/llm_error_stub2.sh"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 1 ]
    grep -qF '既存の有効な下書き本文' "$existing"
}

@test "x_post approve: 本文全文とpathを通知し外部approved markerを待つ" {
    setup_x_post
    cat > "$FIXTURE_DIR/ntfy_stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$NTFY_CAPTURE"
printf 'approved\n' > "$X_POST_APPROVED_MARKER"
EOF
    chmod +x "$FIXTURE_DIR/ntfy_stub.sh"
    export NTFY_CAPTURE="$FIXTURE_DIR/ntfy_message"
    export X_POST_APPROVED_MARKER="$X_POST_DRAFTS_DIR/2026-09-03_A.approved"
    export X_POST_NTFY_SCRIPT="$FIXTURE_DIR/ntfy_stub.sh"
    export X_POST_APPROVAL_WAIT_SECONDS=2
    run bash "$X_POST" approve 2026-09-03_A
    [ "$status" -eq 0 ]
    [ "$output" = "$X_POST_APPROVED_MARKER" ]
    grep -qF "$X_POST_DRAFTS_DIR/2026-09-03_A.txt" "$NTFY_CAPTURE"
    grep -qF 'デュアルモメンタムは2つだけ見る' "$NTFY_CAPTURE"
}

# test_necessity: approval is an operator-action route and must select the
# physically separated transport by default; the override remains available
# for isolated callers/tests without changing the production default.
@test "x_post approve defaults to action notification transport" {
    local x_post="$BATS_TEST_DIRNAME/../../scripts/x_ops/x_post.sh"
    grep -qF 'NTFY_SCRIPT="${X_POST_NTFY_SCRIPT:-$REPO_ROOT/scripts/ntfy_action.sh}"' "$x_post"
    ! grep -qF 'NTFY_SCRIPT="${X_POST_NTFY_SCRIPT:-$REPO_ROOT/scripts/ntfy.sh}"' "$x_post"
}
