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

@test "PASS: 枠A教材再掲の下書き(数字なし、免責あり、許可URLのみ)" {
    cat > "$FIXTURE_DIR/pass_a.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。その資産は現金より強いか。弱ければ退避。確認は月1回。

詳細と検証は無料ガイド。
https://note.com/tokyojibika/n/n171daa7f92a1
助言ではない。過去は未来を保証しない。
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
教育目的。特定銘柄の推奨ではない。過去の検証は将来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/pass_b.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

@test "FAIL rule1: Basic-DualMomentum以外の保有ticker(XLK)が本文にあればFAIL" {
    cat > "$FIXTURE_DIR/fail1.txt" <<'EOF'
プレミアム限定戦略はXLKを中心に運用しています。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail1.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule1_holding_or_ticker_leak:XLK"* ]]
}

@test "FAIL rule2: 単独倍率(期間/CAGR/MaxDD/ベンチのいずれとも同一段落に無い)はFAIL" {
    cat > "$FIXTURE_DIR/fail2.txt" <<'EOF'
このポートフォリオは資産を7倍にしました。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail2.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule2_standalone_multiplier"* ]]
}

@test "FAIL rule3: 完全ガイド/How toマガジン/dm-signal.com以外のURLはFAIL" {
    cat > "$FIXTURE_DIR/fail3.txt" <<'EOF'
詳細はこちら。
https://example.com/spam
助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail3.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule3_disallowed_url:https://example.com/spam"* ]]
}

@test "FAIL rule4: 免責1行(助言ではない/保証しない)が無ければFAIL" {
    cat > "$FIXTURE_DIR/fail4.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。
EOF
    run_gate "$FIXTURE_DIR/fail4.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule4_missing_disclaimer"* ]]
}

@test "FAIL rule5: 禁止語(劇薬など)があればFAIL" {
    cat > "$FIXTURE_DIR/fail5.txt" <<'EOF'
この劇薬のような戦略はすごい。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail5.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule5_forbidden_word:劇薬"* ]]
}

@test "FAIL rule6: 第一文に内部用語(FoFなど)があればFAIL" {
    cat > "$FIXTURE_DIR/fail6.txt" <<'EOF'
FoFの仕組みで運用しています。助言ではない。過去は未来を保証しない。
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
プレミアム限定戦略はTMVを中心に運用しています。助言ではない。過去は未来を保証しない。
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
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。助言ではない。過去は未来を保証しない。
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
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail_empty_blocklist.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"x_post_gate: FAIL rule1 blocklist unavailable (fail-close)"* ]]
}

# test_necessity: x_post.sh のXDK境界をfixtureで固定する。承認なし・認証なし・media有無・
# 201/401を同じCLIで確認し、誤投稿と画像media_id欠落を防ぐ。
setup_x_post() {
    X_POST="$PROJECT_ROOT/scripts/x_ops/x_post.sh"
    export X_POST_DRAFTS_DIR="$FIXTURE_DIR/x_drafts"
    export X_POST_API_ENV_FILE="$FIXTURE_DIR/x_api.env"
    export XDK_CALL_LOG="$FIXTURE_DIR/xdk_calls.log"
    mkdir -p "$X_POST_DRAFTS_DIR" "$FIXTURE_DIR/fake_xdk/xdk/media" "$FIXTURE_DIR/fake_xdk/xdk/posts"
    cat > "$FIXTURE_DIR/fake_xdk/xdk/__init__.py" <<'PY'
import json, os
class _ResponseError(RuntimeError):
    def __init__(self, status):
        super().__init__(f"HTTP {status}")
        self.response = type("Response", (), {"status_code": status})()
class _Media:
    def upload(self, *args, **kwargs):
        with open(os.environ["XDK_CALL_LOG"], "a", encoding="utf-8") as f:
            f.write("media " + json.dumps({"args": len(args), "kwargs": list(kwargs)}) + "\n")
        return {"data": {"id": "media-1"}}
class _Posts:
    def create(self, *args, **kwargs):
        if os.environ.get("XDK_STATUS") == "401":
            raise _ResponseError(401)
        with open(os.environ["XDK_CALL_LOG"], "a", encoding="utf-8") as f:
            f.write("post " + json.dumps(list(kwargs)) + "\n")
        return {"data": {"id": "post-1"}}
class Client:
    def __init__(self, token=None, **kwargs):
        self.token = token
        self.media = _Media()
        self.posts = _Posts()
PY
    cat > "$FIXTURE_DIR/fake_xdk/xdk/oauth2_auth.py" <<'PY'
class OAuth2PKCEAuth:
    def __init__(self, **kwargs):
        self.kwargs = kwargs
PY
    cat > "$FIXTURE_DIR/fake_xdk/xdk/media/models.py" <<'PY'
class UploadRequest:
    def __init__(self, media, media_category):
        self.media = media
        self.media_category = media_category
PY
    cat > "$FIXTURE_DIR/fake_xdk/xdk/posts/models.py" <<'PY'
class CreateRequest:
    def __init__(self, **kwargs):
        self.kwargs = kwargs
PY
    cat > "$X_POST_DRAFTS_DIR/2026-09-03_A.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。助言ではない。過去は将来を保証しない。
EOF
    printf 'approved\n' > "$X_POST_DRAFTS_DIR/2026-09-03_A.approved"
    printf 'X_ACCESS_TOKEN=test-token\n' > "$X_POST_API_ENV_FILE"
}

@test "x_post post: XDKでmediaなし201を投稿済みmarkerへ記録" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_xdk" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 0 ]
    [[ "$output" == *"post-1"* ]]
    [ ! -s "$XDK_CALL_LOG" ] || ! grep -q '^media ' "$XDK_CALL_LOG"
    [ -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

@test "x_post post: PNGをXDK media.uploadしmedia_ids付き201を投稿" {
    setup_x_post
    printf '\x89PNG\r\n\x1a\n' > "$FIXTURE_DIR/experience.png"
    run env PYTHONPATH="$FIXTURE_DIR/fake_xdk" bash "$X_POST" post 2026-09-03_A --media "$FIXTURE_DIR/experience.png"
    [ "$status" -eq 0 ]
    grep -q '^media ' "$XDK_CALL_LOG"
    grep -q '^post ' "$XDK_CALL_LOG"
    [ -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

@test "x_post post: XDK HTTP401は投稿済みmarkerを作らずexit1" {
    setup_x_post
    run env PYTHONPATH="$FIXTURE_DIR/fake_xdk" XDK_STATUS=401 bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTTP 401"* ]]
    [ ! -f "$X_POST_DRAFTS_DIR/2026-09-03_A.posted" ]
}

@test "x_post post: 承認marker不在はXDKを呼ばずexit1" {
    setup_x_post
    rm -f "$X_POST_DRAFTS_DIR/2026-09-03_A.approved"
    run env PYTHONPATH="$FIXTURE_DIR/fake_xdk" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 1 ]
    [[ "$output" == *"not approved"* ]]
    [ ! -f "$XDK_CALL_LOG" ]
}

@test "x_post post: creds file不在はexit2でXDKを呼ばない" {
    setup_x_post
    rm -f "$X_POST_API_ENV_FILE"
    run env PYTHONPATH="$FIXTURE_DIR/fake_xdk" bash "$X_POST" post 2026-09-03_A
    [ "$status" -eq 2 ]
    [[ "$output" == *"credentials file not found"* ]]
}

@test "x_post draft: 日付_slot名へslot instructionと台帳値を注入" {
    setup_x_post
    cat > "$FIXTURE_DIR/ledger.yaml" <<'EOF'
entries:
- key: demo
  url: https://note.com/tokyojibika/n/demo
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
    export X_POST_LLM_CMD="cat"
    run bash "$X_POST" draft A demo
    [ "$status" -eq 0 ]
    [[ "$output" == "$X_POST_DRAFTS_DIR/20"*"_A.txt" ]]
    grep -q '^angle: 定義$' "$output"
    grep -q '^draft_seed: 二つだけ見る。$' "$output"
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
