#!/usr/bin/env bats
# test_pre_bash_guard14_fast_filter_sync.bats - Guard14 二段化classifierの同期検証
# (cmd_karo_hotfix_guard14_db_trust_boundary_202607120854, review_correction 09:42/09:45 karo)
#
# scripts/lib/guard14_db_trust_classify.sh の guard14_classify() が Guard14の唯一の入口
# (SSOT)。全Bash commandを無条件でpython3 -S classify.pyへ渡すと実測+29ms/呼び出し
# (N=20 median, WSL2)で許容不能だったため、内部でguard14_maybe_connection()という
# 保守的negative filterを先に通す二段構成にした。
#
# negative filterは特定client名の列挙(psycopg2/create_db_engine等)ではなく、
# scripts/lib/guard14_db_trust_classify.py の _segment_has_db_marker が
# connection intentと判定し得る構造的signalカテゴリ(DSN URLスキーム/DB系env変数名/
# 接続API呼出の形 `.connect(` /engine factory呼出の形 `create_*engine(` /host指定/
# in-memoryマーカー)を1対1でミラーする。psycopg v3・asyncpg等の異種clientでも
# `.connect(` という共通の呼出形で捕捉される。
#
# 本テストは guard14_maybe_connection() の実体(sedで.shファイルから直接抽出=正本テスト、
# 複製ではない)を、classify.pyの全fixture(BLOCK/local_ephemeralになる全ケース、異種client
# 含む)に対して実行し、fast filterが1件も取りこぼさない(false negativeが無い)ことを
# 保証する。fast filterがfalse negativeを起こすと、本来BLOCK/local_ephemeralになるべき
# commandがnot_connection扱いで無審査ALLOWされる致命的な乖離になるため、これは正しさの
# 回帰テストであり、性能テストではない。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    export CLASSIFY_SCRIPT="$PROJECT_ROOT/scripts/lib/guard14_db_trust_classify.py"
    export CLASSIFY_SH="$PROJECT_ROOT/scripts/lib/guard14_db_trust_classify.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
    [ -f "$CLASSIFY_SCRIPT" ] || return 1
    [ -f "$CLASSIFY_SH" ] || return 1

    # 正本(guard14_db_trust_classify.sh)から guard14_maybe_connection() 関数定義を
    # そのまま抽出してsourceする。複製・再実装ではなく、実行対象そのものをテストする。
    # BATS_TEST_TMPDIRはsetup_fileスコープでは未設定のためBATS_FILE_TMPDIRを使う。
    export FAST_FILTER_SRC="$BATS_FILE_TMPDIR/g14_fast_filter_extracted.sh"
    sed -n '/^guard14_maybe_connection() {/,/^}/p' "$CLASSIFY_SH" > "$FAST_FILTER_SRC"
    [ -s "$FAST_FILTER_SRC" ] || return 1
}

_fast_filter_says_maybe() {
    local cmd="$1"
    bash -c 'source "$1"; guard14_maybe_connection "$2"' _ "$FAST_FILTER_SRC" "$cmd"
}

_classify() {
    local cmd="$1"
    run bash -c 'COMMAND="$1" python3 "$2"' _ "$cmd" "$CLASSIFY_SCRIPT"
}

_run_hook_cmd_local() {
    local cmd="$1"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$cmd")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

# --- pre-bash-combined.shが二重SSOT化していないことの確認(直書き禁止の回帰防止) ---

@test "pre-bash-combined.sh sources the shared classifier, does not redefine fast-filter logic inline" {
    run grep -c "guard14_db_trust_classify.sh" "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c "_g14_maybe_connection() {" "$HOOK_SCRIPT"
    [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
}

# --- fast filterは「必要条件の抽出元」自体が壊れていないことをまず確認する ---

@test "fast filter extraction: function body is non-empty and well-formed" {
    run cat "$FAST_FILTER_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"guard14_maybe_connection"* ]]
    [[ "$output" == *"return 1"* ]]
}

# --- 乖離防止: classify()が non-not_connection を返す全ケースで fast filter は必ず0(maybe)を返す ---

@test "sync: local pytest with localhost DATABASE_URL -> fast filter says maybe" {
    run _fast_filter_says_maybe 'DATABASE_URL=postgresql://postgres:postgres@localhost:5432/dm_signal_test python -m pytest -c backend/pytest.ini backend/tests'
    [ "$status" -eq 0 ]
}

@test "sync: libpq Unix socket via query -> fast filter says maybe" {
    run _fast_filter_says_maybe 'DATABASE_URL=postgresql://postgres@/testdb?host=/var/run/postgresql python -m pytest backend/tests'
    [ "$status" -eq 0 ]
}

@test "sync: sqlite in-memory create_db_engine -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"from app.db.database import create_db_engine; e = create_db_engine('sqlite:///:memory:')\""
    [ "$status" -eq 0 ]
}

@test "sync: psycopg2.connect 127.0.0.1 -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import psycopg2; psycopg2.connect(host='127.0.0.1')\""
    [ "$status" -eq 0 ]
}

@test "sync: remote Render psycopg2 connect -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import psycopg2; psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com')\""
    [ "$status" -eq 0 ]
}

@test "sync: unresolved DATABASE_URL env var -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\""
    [ "$status" -eq 0 ]
}

@test "sync: psql remote URL -> fast filter says maybe" {
    run _fast_filter_says_maybe "psql \"postgresql://user:pass@remote.example.com:5432/proddb\""
    [ "$status" -eq 0 ]
}

@test "sync: psql local via -h flag -> fast filter says maybe" {
    run _fast_filter_says_maybe 'psql -h localhost -d testdb -U postgres'
    [ "$status" -eq 0 ]
}

@test "sync: psql with no arguments -> fast filter says maybe" {
    run _fast_filter_says_maybe 'psql'
    [ "$status" -eq 0 ]
}

@test "sync: bare host= keyword (no other marker) -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\""
    [ "$status" -eq 0 ]
}

@test "sync: standalone & operator fusion adversarial -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\" & echo host=/tmp"
    [ "$status" -eq 0 ]
}

@test "sync: decoy check_pf_config.py plus remote psycopg2 connect -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\" && python3 /tmp/check_pf_config.py"
    [ "$status" -eq 0 ]
}

# --- .env単独はDB intentではない ---
# .envはHTTP API等の非DB資格情報にも使われる。DB固有構造が無い限りnot_connection。

@test "sync: backend/.env load with NO DB marker -> fast filter rejects maybe" {
    run _fast_filter_says_maybe "python3 -c \"from dotenv import load_dotenv; load_dotenv('backend/.env'); import myorm; myorm.init_from_env()\""
    [ "$status" -eq 1 ]
}

@test "classifier: Render API credentials from backend/.env plus requests.get -> not_connection" {
    _classify "python3 -c \"from dotenv import load_dotenv; load_dotenv('backend/.env'); import os,requests; requests.get(os.environ['API_URL'], headers={'Authorization': os.environ['RENDER_API_KEY'], 'X-Service': os.environ['RENDER_SERVICE_ID']})\""
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "sync: bare .env (no path prefix) with no other marker -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"from dotenv import load_dotenv; load_dotenv('.env')\""
    [ "$status" -eq 1 ]
}

@test "classifier: bare .env with no other marker -> not_connection" {
    _classify "python3 -c \"from dotenv import load_dotenv; load_dotenv('.env')\""
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

# source .env後も、後続segmentにDB固有構造が無ければnot_connection。

@test "sync: source backend/.env as its own segment, followed by marker-less python -> fast filter says maybe" {
    run _fast_filter_says_maybe 'source backend/.env && python3 -c "import myorm; myorm.init_from_env()"'
    [ "$status" -eq 1 ]
}

@test "classifier: source backend/.env followed by marker-less python -> not_connection" {
    _classify 'source backend/.env && python3 -c "import myorm; myorm.init_from_env()"'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "Guard14 (hook): source backend/.env then marker-less python is allowed" {
    _run_hook_cmd_local 'source backend/.env && python3 -c "import myorm; myorm.init_from_env()"'
    [ "$status" -eq 0 ]
}

@test "Guard14 (hook): source backend/.env then explicit DB connect remains blocked" {
    _run_hook_cmd_local 'source backend/.env && python3 -c "import psycopg; psycopg.connect(host=\"remote.example.com\")"'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

# --- env var regex の DB意味トークン要求(review_correction 09:51/09:55, karo) ---
# API_URL/SENTRY_DSN等の無関係env varはfast filterでmaybe扱いにしない(DB/DATABASE/
# POSTGRES/PGのいずれも含まないため)。過検知によるslow-path経由のunknown BLOCKを防ぐ。
# 逆にDATABASE_URL/DB_URL/POSTGRES_DSNはそれぞれ単体でmarker認識することも直接確認する。

@test "fast path proof: unrelated API_URL env var (no DB semantic token) takes the fast path" {
    run _fast_filter_says_maybe 'API_URL=https://api.example.com/v1 python3 -c "print(1)"'
    [ "$status" -eq 1 ]
}

@test "classifier: unrelated API_URL env var agrees (not_connection)" {
    _classify 'API_URL=https://api.example.com/v1 python3 -c "print(1)"'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "fast path proof: unrelated SENTRY_DSN env var (no DB semantic token) takes the fast path" {
    run _fast_filter_says_maybe 'SENTRY_DSN=https://sentry.io/x python3 -c "print(1)"'
    [ "$status" -eq 1 ]
}

@test "classifier: unrelated SENTRY_DSN env var agrees (not_connection)" {
    _classify 'SENTRY_DSN=https://sentry.io/x python3 -c "print(1)"'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "unit: DATABASE_URL alone (unresolved) is recognized as a DB marker -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "unit: DB_URL alone (unresolved) is recognized as a DB marker -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DB_URL'])\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "unit: POSTGRES_DSN alone (unresolved) is recognized as a DB marker -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['POSTGRES_DSN'])\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

# --- 異種client(psycopg v3 / asyncpg)でも構造signalで捕捉されることの確認 ---
# (review_correction 09:45, karo: 個別client名列挙ではなく`.connect(`等の構造shapeで判定)

@test "sync: psycopg v3 (no '2' suffix) .connect( to remote host -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import psycopg; psycopg.connect(host='remote-prod.example.com')\""
    [ "$status" -eq 0 ]
}

@test "classifier: psycopg v3 (no '2' suffix) .connect( to remote host -> connection:untrusted" {
    _classify "python3 -c \"import psycopg; psycopg.connect(host='remote-prod.example.com')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "sync: asyncpg .connect( with postgresql:// DSN to remote host -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import asyncpg; await asyncpg.connect('postgresql://remote-prod.example.com/db')\""
    [ "$status" -eq 0 ]
}

@test "classifier: asyncpg .connect( with postgresql:// DSN to remote host -> connection:untrusted" {
    _classify "python3 -c \"import asyncpg; await asyncpg.connect('postgresql://remote-prod.example.com/db')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "sync: asyncpg .connect( to localhost -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"import asyncpg; await asyncpg.connect(host='localhost')\""
    [ "$status" -eq 0 ]
}

@test "classifier: asyncpg .connect( to localhost -> connection:local_ephemeral" {
    _classify "python3 -c \"import asyncpg; await asyncpg.connect(host='localhost')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "sync: generic create_engine( (non-DM-Signal SQLAlchemy factory name) with remote host -> fast filter says maybe" {
    run _fast_filter_says_maybe "python3 -c \"from sqlalchemy import create_engine; e = create_engine('postgresql://remote-prod.example.com/db')\""
    [ "$status" -eq 0 ]
}

@test "classifier: generic create_engine( with remote host -> connection:untrusted" {
    _classify "python3 -c \"from sqlalchemy import create_engine; e = create_engine('postgresql://remote-prod.example.com/db')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

# --- benignケースは実際にfast pathを通る(python3を起動しない)ことも確認する ---
# (over-inclusion=安全側なので必須ではないが、性能最適化が実在することの証跡として記録)

@test "fast path proof: benign pytest with no DB marker takes the fast path (filter says NOT maybe)" {
    run _fast_filter_says_maybe 'python3 -m pytest backend/tests/test_unrelated.py'
    [ "$status" -eq 1 ]
}

@test "fast path proof: unrelated ls command takes the fast path (filter says NOT maybe)" {
    run _fast_filter_says_maybe 'ls -la /tmp'
    [ "$status" -eq 1 ]
}

@test "fast path proof: git status takes the fast path (filter says NOT maybe)" {
    run _fast_filter_says_maybe 'git status'
    [ "$status" -eq 1 ]
}

@test "fast path proof: benign python one-liner takes the fast path (filter says NOT maybe)" {
    run _fast_filter_says_maybe 'python3 -c "print(1+1)"'
    [ "$status" -eq 1 ]
}

# --- benignケースでも classify() 自体を直接呼べば整合して not_connection になる(理論保証) ---

@test "cross-check: benign pytest classify() agrees with fast filter (not_connection)" {
    _classify 'python3 -m pytest backend/tests/test_unrelated.py'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

# --- helper欠落時のfail-closed(review_correction 10:03, karo: 実hook callerで再現する永続test) ---
# 実ファイルは操作せず、隔離コピー環境(SCRIPT_DIRが解決される正しい相対構造)を都度作成して
# helperを意図的に欠落させる。set -euo下での単純代入`_g14_classification="$(guard14_classify ...)"`
# はpython3失敗時にif判定へ到達する前にhookを即終了させ得るため、`if !`形式での明示捕捉が
# 正しく機能し、Guard14表記+exit 2になることを検証する。

_make_isolated_hook_copy() {
    local iso_root="$1"
    mkdir -p "${iso_root}/.claude/hooks" "${iso_root}/scripts/lib" "${iso_root}/scripts/hooks"
    cp "$HOOK_SCRIPT" "${iso_root}/.claude/hooks/pre-bash-combined.sh"
    # pre-bash-combined.sh冒頭の三層preflight実在チェック(Guard14より前段)を満たすため、
    # 依存ファイルも複製する。verify()自体はBATS_TEST_FILENAME設定時にskipされる仕様
    # (ファイル冒頭 `[[ -z "${BATS_TEST_FILENAME:-}" ]] && ...verify...` )。
    cp "$PROJECT_ROOT/scripts/hooks/three_layer_preflight.sh" "${iso_root}/scripts/hooks/three_layer_preflight.sh"
    chmod +x "${iso_root}/scripts/hooks/three_layer_preflight.sh"
}

@test "Guard14 (isolated hook copy): Python classifier (.py) missing on a DB-triggering command -> explicit Guard14 BLOCK + exit 2" {
    local iso="$BATS_TEST_TMPDIR/iso_py_missing"
    _make_isolated_hook_copy "$iso"
    cp "$CLASSIFY_SH" "${iso}/scripts/lib/guard14_db_trust_classify.sh"
    # guard14_db_trust_classify.py をわざと配置しない(欠落を再現)

    local cmd payload
    cmd="python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\""
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$cmd")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "${iso}/.claude/hooks/pre-bash-combined.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 (isolated hook copy): shared shell helper (.sh) missing -> explicit Guard14 BLOCK + exit 2" {
    local iso="$BATS_TEST_TMPDIR/iso_sh_missing"
    _make_isolated_hook_copy "$iso"
    # guard14_db_trust_classify.sh をわざと配置しない(欠落を再現)。
    # .sh欠落チェックはtrigger語彙に関わらず常に評価されるためbenign commandでも検証できる。

    local payload
    payload='{"tool_name": "Bash", "tool_input": {"command": "ls -la /tmp"}}'
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "${iso}/.claude/hooks/pre-bash-combined.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Guard14"* ]]
}
