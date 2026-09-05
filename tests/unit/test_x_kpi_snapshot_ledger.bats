#!/usr/bin/env bats
# test_necessity: x_kpi_snapshot must never glue a snapshot onto the next entry's
# "- draft_id:" line, and must refuse to write a ledger that does not parse or that
# changes the entry count. 2026-09-05 ledger.yaml L275 was corrupted by the
# `\s*$` replacement eating the newline after `snapshots: {}`.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export ROOT
}

run_py() {
    python3 - "$ROOT" "$@" <<'PY'
import importlib.util, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("kpi", f"{root}/scripts/x_ops/x_kpi_snapshot.py")
kpi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kpi)
mode = sys.argv[2]
entry_a = "- draft_id: R5-L-0\n  post_id: '1'\n  posted_at: '2026-09-04T05:49:21Z'\n  snapshots: {}\n"
entry_b = "- draft_id: R5-L-1\n  draft_file: x.txt\n"
snap = "    t24h:\n      ts: 2026-09-05T15:15:01+09:00\n      np_impression_count: 768\n"
if mode == "empty_map":
    out = kpi.apply_snapshot(entry_a, snap)
    text = "entries:\n" + out + entry_b
    kpi.validate_ledger_text(text, expected_entries=2)
    assert "np_impression_count: 768\n- draft_id: R5-L-1" in text, text
    print("OK")
elif mode == "existing_block":
    a2 = entry_a.replace("  snapshots: {}\n", "  snapshots:\n    t1h:\n      ts: x\n")
    out = kpi.apply_snapshot(a2, snap)
    text = "entries:\n" + out + entry_b
    kpi.validate_ledger_text(text, expected_entries=2)
    assert out.count("    t24h:") == 1 and out.count("    t1h:") == 1
    print("OK")
elif mode == "glued_rejected":
    bad = "entries:\n" + entry_a.replace("  snapshots: {}\n", "  snapshots:\n    t24h:\n      np_impression_count: 768") + entry_b
    try:
        kpi.validate_ledger_text(bad, expected_entries=2)
    except ValueError as exc:
        assert "glued" in str(exc) or "safe_load" in str(exc), exc
        print("REJECTED")
    else:
        raise SystemExit("glued text was accepted")
elif mode == "count_rejected":
    text = "entries:\n" + entry_a + entry_b
    try:
        kpi.validate_ledger_text(text, expected_entries=3)
    except ValueError as exc:
        assert "entries count" in str(exc), exc
        print("REJECTED")
    else:
        raise SystemExit("count mismatch accepted")
PY
}

@test "snapshots: {} の置換は次 entry の境界改行を残す" {
    run run_py empty_map
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "既存 snapshots ブロックへの追記も境界を壊さない" {
    run run_py existing_block
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "連結破損した台帳テキストは validate で拒否される(fail-close)" {
    run run_py glued_rejected
    [ "$status" -eq 0 ]
    [[ "$output" == *"REJECTED"* ]]
}

@test "entry 数が変わる書込は拒否される" {
    run run_py count_rejected
    [ "$status" -eq 0 ]
    [[ "$output" == *"REJECTED"* ]]
}

# test_necessity: the shared guard used by every ledger writer must add the missing
# trailing newline before an append (x_growth_tag path) and must not touch the file
# when validation fails (write_ledger_text is fail-close).
@test "共通 guard: 末尾改行なしの既存 text へ append しても連結せず、検証失敗時は file を書かない" {
    local dir; dir="$(mktemp -d)"
    run python3 - "$ROOT" "$dir" <<'PY'
import sys
root, d = sys.argv[1], sys.argv[2]
sys.path.insert(0, f"{root}/scripts/x_ops")
from x_ledger_guard import ensure_trailing_newline, validate_ledger_text, write_ledger_text
existing = "entries:\n- draft_id: A\n  snapshots: {}"          # no trailing newline
add = "- draft_id: B\n  snapshots: {}\n"
text = ensure_trailing_newline(existing) + add
doc = validate_ledger_text(text, expected_entries=2)
assert [e["draft_id"] for e in doc["entries"]] == ["A", "B"], doc
path = f"{d}/ledger.yaml"
open(path, "w").write("entries: []\n")
try:
    write_ledger_text(path, existing + add, expected_entries=2)   # glued -> must not write
except ValueError:
    pass
else:
    raise SystemExit("glued text was written")
assert open(path).read() == "entries: []\n", "file was modified on failed validation"
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    rm -rf "$dir"
}

# test_necessity: validate後のprocess停止でも正本をtruncateせず、並行writerの
# newer generationを古いread結果で上書きしない。
@test "共通 guard: atomic replace失敗とstale CASは既存ledgerを不変に保つ" {
    local dir; dir="$(mktemp -d)"
    run python3 - "$ROOT" "$dir" <<'PY'
import sys
from pathlib import Path
root, d = sys.argv[1], sys.argv[2]
sys.path.insert(0, f"{root}/scripts/x_ops")
import x_ledger_guard as guard
path = Path(d) / "ledger.yaml"
old = "entries:\n- draft_id: A\n  snapshots: {}\n"
new = "entries:\n- draft_id: A\n  snapshots: {t1h: {}}\n"
path.write_text(old)
real_replace = guard.os.replace
guard.os.replace = lambda *_: (_ for _ in ()).throw(OSError("fixture replace failure"))
try:
    guard.write_ledger_text(path, new, expected_entries=1, expected_current_text=old)
except OSError:
    pass
else:
    raise SystemExit("replace failure was accepted")
finally:
    guard.os.replace = real_replace
assert path.read_text() == old
newer = "entries:\n- draft_id: A\n  snapshots: {t7d: {}}\n"
path.write_text(newer)
try:
    guard.write_ledger_text(path, new, expected_entries=1, expected_current_text=old)
except ValueError as exc:
    assert "stale ledger generation" in str(exc)
else:
    raise SystemExit("stale writer was accepted")
assert path.read_text() == newer
print("OK atomic_fail_unchanged=1 stale_cas_block=1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"atomic_fail_unchanged=1 stale_cas_block=1"* ]]
}

@test "全writerがread世代CASを渡し stage2件数は変更前を正本にする" {
    run rg -n 'expected_current_text=' \
      "$ROOT/scripts/x_ops/x_growth_tag.py" \
      "$ROOT/scripts/x_ops/x_kpi_snapshot.py" \
      "$ROOT/scripts/x_ops/x_stage2_approve.py" \
      "$ROOT/scripts/x_ops/x_slot_post.sh"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 4 ]
    run rg -n 'expected_entries=original\.count' "$ROOT/scripts/x_ops/x_stage2_approve.py"
    [ "$status" -eq 0 ]
}
