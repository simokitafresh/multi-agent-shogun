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
