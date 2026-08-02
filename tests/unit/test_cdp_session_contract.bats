#!/usr/bin/env bats

# test_necessity: T5-4/7/9/11の境界でreceipt欠落・権限非同値・deploy不包含・境界外cleanupを必ずfail-closedにする契約を守る。
@test "CDP session contract fixtures are binary and fail closed" {
  run python3 - "$BATS_TEST_DIRNAME/../../docs/research/cdp-session-contract-v1.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
required = set(d['receipt_contract']['required'])
def valid(x):
    r = x.get('receipt')
    if not r or not required <= set(r): return False
    if not (r['issued_at'] <= x['now'] < r['expires_at']): return False
    if x.get('granted_capability') != x.get('required_capability'): return False
    if x.get('target_commit') not in x.get('deployed_commits', []): return False
    if x.get('cleanup_pid') != r['chrome_pid']: return False
    if x.get('cleanup_profile') != r['profile_path']: return False
    return True
for name, fixture in d['fixtures'].items():
    actual = 'pass' if valid(fixture) else 'fail'
    assert actual == fixture['expected'], (name, actual, fixture['expected'])
assert set(d['t5_mapping']['contract_layer']) == {4, 7, 9, 11}
print('fixtures=5 pass=1 fail_closed=4 t5_contract=4')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "fixtures=5 pass=1 fail_closed=4 t5_contract=4" ]
}

# test_necessity: T5-7/10/12のconsumer境界で全入口が同一receipt発行元を消費し、用途層の直起動を再導入できない契約を守る。
@test "all CDP consumers require the shared session receipt" {
  run python3 - "$BATS_TEST_DIRNAME/../.." <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
consumers = [
 "scripts/cdp/cdp_server.py", "scripts/cdp/cdp_tier_probe.py",
 "scripts/cdp/cdp_maxdisplay_probe.py", "scripts/cdp/cdp_font_probe.py",
 "scripts/cdp/cdp_ed_probe.py", "scripts/cdp/cdp_contrast_probe.py",
 "scripts/cdp/cdp_card_probe.py", "scripts/cdp/cdp_measure.sh",
 "scripts/note_draft.sh",
]
texts = {p: (root / p).read_text() for p in consumers}
assert all("receipt" in text for text in texts.values())
forbidden = ("preflight_cdp_flow", "cleanup_chrome", "--remote-debugging-port")
assert not [(p, token) for p, text in texts.items() for token in forbidden if token in text]
assert "CDP_PORT=\"${CDP_PORT:-9234}\"" in texts["scripts/note_draft.sh"]
print("consumers=9 receipt=9 direct_launch=0 note_port=9234")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "consumers=9 receipt=9 direct_launch=0 note_port=9234" ]
}

# test_necessity: T5-10の同時2起動・再実行・全fallback占有を独立fixtureで二値検証する契約を守る。
@test "session establishment is idempotent and finite-fallback fail closed" {
  run env PYTHONPATH="$BATS_TEST_DIRNAME/../../scripts/cdp" python3 - <<'PY'
from cdp_session import SessionError, establish
alive_ports = {9222}
def alive(port): return port in alive_ports
def launcher(port, profile): alive_ports.add(port); return 1000 + port
r1 = establish("inspection", ports=(9222,), alive=alive, launcher=launcher)
r2 = establish("measurement", ports=(9222,), alive=alive, launcher=launcher)
assert r1["endpoint"] == r2["endpoint"] and not r1["owned"] and not r2["owned"]
try:
    establish("note", ports=(9234, 9235), alive=lambda _: False,
              launcher=lambda port, profile: port, startup_timeout=0)
except SessionError:
    print("concurrent=PASS rerun=PASS fallback_exhausted=PASS")
else:
    raise AssertionError("finite fallback did not fail closed")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "concurrent=PASS rerun=PASS fallback_exhausted=PASS" ]
}
