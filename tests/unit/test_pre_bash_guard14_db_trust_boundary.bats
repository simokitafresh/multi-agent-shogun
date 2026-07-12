#!/usr/bin/env bats
# test_pre_bash_guard14_db_trust_boundary.bats - Guard 14: DB操作意図×接続先信頼境界の構造判定
# (cmd_karo_hotfix_guard14_db_trust_boundary_202607120854)
#
# 旧実装は command 中に psycopg2/DATABASE_URL/create_db_engine の文字列があれば
# 検索(grep/rg/cat)やlocalhost/sqlite:///:memory:のローカルCI接続まで一律BLOCKしていた
# (hayate blocked report 2026-07-12T08:49:15)。本テストは修正後の分類器
# (scripts/lib/guard14_db_trust_classify.py)が not_connection /
# connection:local_ephemeral / connection:untrusted の3値判定でローカルCIを妨げず
# 本番誤接続を防ぐことを、(1)分類器単体、(2)実hook経由の両方で表形式fixture検証する。
#
# review_correction(2026-07-12 09:05〜09:24, karo) 5ラウンド対応:
# - candidate抽出は接続runtimeを含むsegment自身のトークンだけを対象とし、他segment
#   (echo等)のlocal風文字列で誤許可しないことをADVERSARIALケースで確認する。
# - セグメント分割は shlex.shlex(punctuation_chars=";&|") で空白有無に関わらず
#   &&/||/;/|/単独& を演算子境界とする(空白なし演算子の融合バグ対応)。
# - host候補の空文字列(host=空値・URL authority欠落かつquery override無し)はfail-closedで
#   untrusted。URLはurllib.parseで構造的にhostname/queryを解析する。
# - db-check/check_pf_config免除は自由文字列一致を廃止し、python系segmentの実行スクリプト
#   operandがconfig/projects.yaml(SSOT)由来の正規check_pf_config.py realpathとsamefile一致
#   する場合のみ構造的に免除する(basename一致やtoken位置不問の免除はなりすまし可能)。
# - BLOCK系テストはHOOK終了コードだけでなくstderrにGuard14文言が含まれることも確認し、
#   別Guardの偶発BLOCKでPASSに見えることを防ぐ。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    export CLASSIFY_SCRIPT="$PROJECT_ROOT/scripts/lib/guard14_db_trust_classify.py"
    [ -f "$HOOK_SCRIPT" ] || return 1
    [ -f "$CLASSIFY_SCRIPT" ] || return 1
    # shellcheck source=scripts/lib/project_path.sh
    source "$PROJECT_ROOT/scripts/lib/project_path.sh"
    export DMS_CHECK_PF_CONFIG
    DMS_CHECK_PF_CONFIG="$(get_project_path dm-signal)/scripts/check_pf_config.py"
    [ -f "$DMS_CHECK_PF_CONFIG" ] || return 1
}

_run_hook_cmd() {
    local cmd="$1"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$cmd")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

_classify() {
    local cmd="$1"
    run bash -c 'COMMAND="$1" python3 "$2"' _ "$cmd" "$CLASSIFY_SCRIPT"
}

# --- ALLOW: local_ephemeral connection (localhost/127.0.0.1/::1/Unix socket/sqlite memory) ---

@test "Guard14 classifier: local pytest with localhost:5432 DATABASE_URL -> connection:local_ephemeral" {
    _classify 'DATABASE_URL=postgresql://postgres:postgres@localhost:5432/dm_signal_test python -m pytest -c backend/pytest.ini backend/tests'
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14: local pytest with localhost:5432 DATABASE_URL is ALLOWED (CI-equivalent repro)" {
    _run_hook_cmd 'DATABASE_URL=postgresql://postgres:postgres@localhost:5432/dm_signal_test python -m pytest -c backend/pytest.ini backend/tests'
    [ "$status" -eq 0 ]
}

@test "Guard14 classifier: libpq Unix socket (host=/var/run/postgresql) -> connection:local_ephemeral" {
    _classify 'DATABASE_URL=postgresql://postgres@/testdb?host=/var/run/postgresql python -m pytest backend/tests'
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14: pytest with libpq Unix socket (host=/var/run/postgresql) is ALLOWED" {
    _run_hook_cmd 'DATABASE_URL=postgresql://postgres@/testdb?host=/var/run/postgresql python -m pytest backend/tests'
    [ "$status" -eq 0 ]
}

@test "Guard14 classifier: Unix socket URL via query is resolved through urllib.parse -> connection:local_ephemeral" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect('postgresql://postgres@/testdb?host=/var/run/postgresql')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14: create_db_engine with sqlite in-memory is ALLOWED" {
    _run_hook_cmd "python3 -c \"from app.db.database import create_db_engine; e = create_db_engine('sqlite:///:memory:')\""
    [ "$status" -eq 0 ]
}

@test "Guard14: psycopg2.connect to 127.0.0.1 is ALLOWED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='127.0.0.1', port=5432, dbname='testdb')\""
    [ "$status" -eq 0 ]
}

@test "Guard14: psycopg2.connect to ::1 is ALLOWED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='::1', port=5432, dbname='testdb')\""
    [ "$status" -eq 0 ]
}

# --- ALLOW: not_connection (text search/reference, no runtime connection) ---

@test "Guard14 classifier: grep for DATABASE_URL string -> not_connection" {
    _classify 'grep -rn "DATABASE_URL" backend/tests/'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "Guard14: grep for DATABASE_URL string is ALLOWED (not_connection)" {
    _run_hook_cmd 'grep -rn "DATABASE_URL" backend/tests/'
    [ "$status" -eq 0 ]
}

@test "Guard14: rg for psycopg2 string is ALLOWED (not_connection)" {
    _run_hook_cmd 'rg -n psycopg2 backend/app/'
    [ "$status" -eq 0 ]
}

@test "Guard14: cat of a file mentioning psycopg2 is ALLOWED (not_connection)" {
    _run_hook_cmd 'cat backend/tests/integration/conftest.py'
    [ "$status" -eq 0 ]
}

@test "Guard14: quoted/compound command with only text-only segments is ALLOWED" {
    _run_hook_cmd 'echo "note: mentions psycopg2 and DATABASE_URL in comment" && grep -rn psycopg2 backend/'
    [ "$status" -eq 0 ]
}

# --- BLOCK: production/remote/credential-source/unknown (fail-closed) ---

@test "Guard14 classifier: remote Render host -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', dbname='dm_signal')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14: psycopg2.connect to remote Render host is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', dbname='dm_signal')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14: psycopg2.connect to arbitrary remote host is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='db.example.com', dbname='x')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier: unresolved env var expansion -> connection:untrusted (fail-closed)" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14: psycopg2.connect via unresolved env var expansion is BLOCKED (fail-closed unknown target)" {
    _run_hook_cmd "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14: backend/.env load then connect is BLOCKED (credential source)" {
    _run_hook_cmd "cd backend && python3 -c \"from dotenv import load_dotenv; load_dotenv(); import psycopg2, os; psycopg2.connect(os.environ['DATABASE_URL'])\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier: skill-example full connect (quoted semicolon inside -c) -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; conn = psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', port=5432, dbname='dm_signal', user='dm_signal_user', password='x', sslmode='require')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14: full psycopg2 direct connect with credentials (skill example) is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; conn = psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', port=5432, dbname='dm_signal', user='dm_signal_user', password='x', sslmode='require')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14: compound command with a connecting segment to remote host is BLOCKED" {
    _run_hook_cmd "grep -c psycopg2 backend/app/db/database.py && python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

# --- BLOCK: adversarial cases, round 1-3 (review_correction 09:05/09:12, karo) ---
# 全文scanのlocal_hit/candidate抽出は、実際は無関係な"localhost"やhost=風文字列が
# 別引数/別segmentに存在するだけでlocal誤許可してしまう。candidate抽出は接続runtimeを
# 含むsegment自身のトークンだけに限定し、他segmentの文字列は一切見ない。

@test "Guard14 classifier ADVERSARIAL: remote connect followed by unrelated 'echo localhost' -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='remote-prod.example.com', dbname='x')\" && echo localhost"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: remote connect followed by unrelated 'echo localhost' is BLOCKED (not fooled by trailing local string)" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='remote-prod.example.com', dbname='x')\" && echo localhost"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: comment mentioning localhost alongside real remote connect -> connection:untrusted" {
    _classify "python3 -c \"# localhost is not used here\nimport psycopg2; psycopg2.connect(host='remote-prod.example.com')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: comment mentioning localhost alongside a real remote connect is BLOCKED (not fooled by unrelated text)" {
    _run_hook_cmd "python3 -c \"# localhost is not used here\nimport psycopg2; psycopg2.connect(host='remote-prod.example.com')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: quoted semicolon inside -c argument does not fragment segment parsing -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; conn = psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', port=5432, dbname='dm_signal', user='dm_signal_user', password='x', sslmode='require')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: quoted semicolon inside -c argument does not fragment segment parsing and BLOCKs remote connect" {
    _run_hook_cmd "python3 -c \"import psycopg2; conn = psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com', port=5432, dbname='dm_signal', user='dm_signal_user', password='x', sslmode='require')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: unresolved connection target plus local-looking string in a DIFFERENT segment (&&) -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\" && echo host=/tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: unresolved connection target plus local-looking string in a different segment (&&) is BLOCKED" {
    _run_hook_cmd "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\" && echo host=/tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

# --- BLOCK: adversarial cases, round 4 (review_correction 09:17, karo) ---
# 空白なし演算子("cmd"&&echo)の融合、host=空値/URL authority欠落の空文字許可、
# db-check自由文字列免除の3脆弱性。

@test "Guard14 classifier ADVERSARIAL: no-whitespace && operator fusion does not merge segments -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\"&&echo host=/tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: no-whitespace && operator fusion is BLOCKED" {
    _run_hook_cmd "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\"&&echo host=/tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: empty-authority URL with no query override -> connection:untrusted (fail-closed)" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect('postgresql:///testdb')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: empty-authority URL with no query override is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect('postgresql:///testdb')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: host= empty value -> connection:untrusted (fail-closed)" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='', dbname='x')\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: host= empty value is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='', dbname='x')\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: remote connect ; echo db-check no longer bypasses (free-text exemption removed) -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\"; echo db-check"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: remote connect ; echo db-check no longer bypasses Guard14 (BLOCKED)" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\"; echo db-check"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

# --- BLOCK: adversarial cases, round 5-6 (review_correction 09:22/09:24, karo) ---
# 単独&(バックグラウンド演算子)の未境界化、免除判定の全token走査によるなりすまし、
# basename一致だけでの同名別ファイルなりすましの3脆弱性。

@test "Guard14 classifier ADVERSARIAL: standalone & (background operator) does not merge segments -> connection:untrusted" {
    _classify "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\" & echo host=/tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: standalone & (background operator) fusion is BLOCKED" {
    _run_hook_cmd "python3 -c \"import os,psycopg2; psycopg2.connect(os.environ['DATABASE_URL'])\" & echo host=/tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: exemption via trailing-argument impersonation (not the script operand) -> connection:untrusted" {
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\" check_pf_config.py"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 ADVERSARIAL: exemption via trailing-argument impersonation is BLOCKED" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\" check_pf_config.py"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier ADVERSARIAL: decoy same-basename different-realpath check_pf_config.py is NOT exempt -> connection:untrusted" {
    skip_decoy="${BATS_TEST_TMPDIR}/check_pf_config.py"
    printf '# decoy, not the real DM-Signal script\n' > "$skip_decoy"
    _classify "python3 -c \"import psycopg2; psycopg2.connect(host='remote.example.com')\" && python3 ${skip_decoy}"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14 classifier: genuine check_pf_config.py realpath (SSOT dm-signal.path) is exempt even with a remote DSN marker present -> connection:local_ephemeral" {
    _classify "python3 ${DMS_CHECK_PF_CONFIG} --dsn=postgresql://remote-prod.example.com/db"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14 classifier: genuine check_pf_config.py with no DB marker at all is not_connection (still ALLOWED)" {
    _classify "python3 ${DMS_CHECK_PF_CONFIG} --mode=full"
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "Guard14: genuine check_pf_config.py exemption is preserved (ALLOWED via hook)" {
    _run_hook_cmd "python3 ${DMS_CHECK_PF_CONFIG} --mode=full"
    [ "$status" -eq 0 ]
}

# --- BLOCK: db-check free-text marker no longer exempts anything (superseded behavior) ---

@test "Guard14: trailing comment mentioning /db-check skill no longer exempts a real remote connect (BLOCKED)" {
    _run_hook_cmd "python3 -c \"import psycopg2; psycopg2.connect(host='dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com')\" # via /db-check skill"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

# --- ALLOW: no trigger token present at all / benign python/pytest with no DB marker ---
# (review_correction 09:33/09:39, karo: Guard14は全Bash commandを無条件でclassify()へ渡す。
# DBと無関係なbenign python/pytestまでBLOCKしないことを明示的に確認する)

@test "Guard14 classifier: benign pytest with no DB marker -> not_connection" {
    _classify 'python3 -m pytest backend/tests/test_unrelated.py'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "Guard14: pytest with no trigger token is ALLOWED (benign, still passes through unconditional classifier)" {
    _run_hook_cmd 'python3 -m pytest backend/tests/test_unrelated.py'
    [ "$status" -eq 0 ]
}

@test "Guard14 classifier: benign python one-liner with no DB marker -> not_connection" {
    _classify 'python3 -c "print(1+1)"'
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
}

@test "Guard14: benign python one-liner is ALLOWED" {
    _run_hook_cmd 'python3 -c "print(1+1)"'
    [ "$status" -eq 0 ]
}

# --- psql CLI: no longer bypasses the classifier (review_correction 09:33, karo) ---

@test "Guard14 classifier: psql remote URL -> connection:untrusted" {
    _classify "psql \"postgresql://user:pass@remote.example.com:5432/proddb\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14: psql remote URL is BLOCKED" {
    _run_hook_cmd "psql \"postgresql://user:pass@remote.example.com:5432/proddb\""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14 classifier: psql local via postgresql:// URL -> connection:local_ephemeral" {
    _classify "psql \"postgresql://localhost:5432/testdb\""
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14: psql local via postgresql:// URL is ALLOWED" {
    _run_hook_cmd "psql \"postgresql://localhost:5432/testdb\""
    [ "$status" -eq 0 ]
}

@test "Guard14 classifier: psql local via native -h flag -> connection:local_ephemeral" {
    _classify 'psql -h localhost -d testdb -U postgres'
    [ "$status" -eq 0 ]
    [ "$output" = "connection:local_ephemeral" ]
}

@test "Guard14: psql local via native -h flag is ALLOWED" {
    _run_hook_cmd 'psql -h localhost -d testdb -U postgres'
    [ "$status" -eq 0 ]
}

@test "Guard14 classifier: psql with no arguments at all -> connection:untrusted (fail-closed, unresolved target)" {
    _classify 'psql'
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
}

@test "Guard14: psql with no arguments at all is BLOCKED" {
    _run_hook_cmd 'psql'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
}

@test "Guard14: non-Bash tool payload is ALLOWED" {
    run bash -c 'printf "%s" "$1" | bash "$2"' _ '{"tool_name":"Read","tool_input":{"file_path":"foo.py"}}' "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
}
