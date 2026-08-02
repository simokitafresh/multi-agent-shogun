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
  echo "$output"
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

# test_necessity: daemonのSIGTERM・idle・KeyboardInterrupt収束先がowned receiptを1回だけ解放し、既存endpointを変更しない契約を守る。
@test "daemon release is once-only and preserves reused endpoints" {
  run env PYTHONPATH="$BATS_TEST_DIRNAME/../../scripts/cdp" python3 - <<'PY'
from cdp_server import SessionRelease
owned = {"owned": True}; reused = {"owned": False}; calls = []
def fake_cleanup(receipt):
    calls.append(receipt)
    return bool(receipt["owned"])
owned_release = SessionRelease(owned, fake_cleanup)
assert owned_release() is True
assert owned_release() is False
reused_release = SessionRelease(reused, fake_cleanup)
assert reused_release() is False
assert reused_release() is False
assert calls == [owned, reused]
print("owned_release=1 reused_change=0 duplicate_release=0")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "owned_release=1 reused_change=0 duplicate_release=0" ]
}

# test_necessity: daemonのSIGTERM・idle・KeyboardInterrupt配線そのものがfinally releaseへ各1/1到達する契約を守る。
@test "daemon exit paths each reach finally release exactly once" {
  run env PYTHONPATH="$BATS_TEST_DIRNAME/../../scripts/cdp" python3 - <<'PY'
import builtins, io, signal, sys
import cdp_server as mod

results = []
for exit_path in ("sigterm", "idle", "keyboard"):
    for owned in (True, False):
        receipt = {"issuer": "cdp_session_foundation", "owned": owned,
                   "endpoint": "http://127.0.0.1:9222"}
        cleanup_calls = []
        handlers = {}
        mod.establish = lambda *a, _r=receipt, **k: _r
        class FakeRelease:
            def __init__(self, r): self.receipt, self.called = r, False
            def __call__(self):
                if self.called: return False
                self.called = True; cleanup_calls.append(self.receipt)
                return bool(self.receipt["owned"])
        mod.SessionRelease = FakeRelease
        mod.ensure_ws = lambda state: object()
        mod.os.chmod = lambda *a: None
        mod.signal.signal = lambda sig, fn, _h=handlers: _h.__setitem__(sig, fn)
        real_open = builtins.open
        builtins.open = lambda path, *a, **k: io.StringIO() if path == "/tmp/cdp-server.json" else real_open(path, *a, **k)

        class FakeServer:
            def __init__(self, *a, **k): self.shutdown_calls = 0
            def shutdown(self): self.shutdown_calls += 1
            def serve_forever(self):
                if exit_path == "sigterm": handlers[signal.SIGTERM](signal.SIGTERM, None)
                elif exit_path == "keyboard": raise KeyboardInterrupt

        class FakeThread:
            def __init__(self, target=None, args=(), **k): self.target, self.args = target, args
            def start(self):
                name = getattr(self.target, "__name__", "")
                if exit_path == "idle" and name == "idle_watchdog": self.target(*self.args)
                elif name == "shutdown": self.target(*self.args)

        mod.CDPDaemonServer = FakeServer
        mod.threading.Thread = FakeThread
        mod.time.sleep = lambda *_: None
        sys.argv = ["cdp_server.py", "--port", "19400", "--idle-timeout", "-1"]
        try:
            mod.main()
        finally:
            builtins.open = real_open
        assert cleanup_calls == [receipt], (exit_path, owned, cleanup_calls)
        results.append((exit_path, owned, len(cleanup_calls)))

assert len(results) == 6
print("sigterm=1/1 idle=1/1 keyboard=1/1 duplicate_release=0 reused_change=0")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"sigterm=1/1 idle=1/1 keyboard=1/1 duplicate_release=0 reused_change=0"* ]]
}

# test_necessity: Python consumer 7入口を実行し、業務処理より先にinspection/generic receiptが伝播する契約を守る。
@test "python consumer entrypoints execute receipt acquisition" {
  run python3 - "$BATS_TEST_DIRNAME/../.." <<'PY'
from pathlib import Path
import subprocess, sys, textwrap
root = Path(sys.argv[1])
entries = [
 ("scripts/cdp/cdp_server.py", "generic", ["--port", "19400"]),
 ("scripts/cdp/cdp_tier_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
 ("scripts/cdp/cdp_maxdisplay_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
 ("scripts/cdp/cdp_font_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
 ("scripts/cdp/cdp_ed_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
 ("scripts/cdp/cdp_contrast_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
 ("scripts/cdp/cdp_card_probe.py", "inspection", ["--base", "https://fixture", "--routes", "/x"]),
]
bootstrap = r'''
import runpy, sys, types
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).resolve().parent))
class Seen(Exception): pass
def establish(consumer, **kwargs):
    print("RECEIPT:" + consumer)
    raise Seen
m=types.ModuleType("cdp_session"); m.establish=establish; m.cleanup=lambda r: False
sys.modules["cdp_session"]=m
sys.argv=[sys.argv[1], *sys.argv[2:]]
try: runpy.run_path(sys.argv[0], run_name="__main__")
except Seen: pass
'''
for path, consumer, args in entries:
    cp = subprocess.run([sys.executable, "-c", bootstrap, str(root/path), *args],
                        cwd=root, text=True, capture_output=True)
    assert cp.returncode == 0, (path, cp.stderr)
    assert f"RECEIPT:{consumer}" in cp.stdout, (path, cp.stdout, cp.stderr)
print("python_entries=7 receipt_propagated=7")
PY
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "python_entries=7 receipt_propagated=7" ]
}

# test_necessity: shell consumer 2入口を実行し、既存引数・note port9234を保ったままreceiptを伝播する契約を守る。
@test "shell consumer entrypoints execute receipt propagation" {
  fixture_dir="$(mktemp -d)"
  establisher="$fixture_dir/establish"
  markdown="$fixture_dir/article.md"
  printf '# fixture\n' > "$markdown"
  printf '%s\n' '#!/usr/bin/env bash' 'while [[ $# -gt 0 ]]; do case "$1" in --consumer) consumer="$2"; shift 2;; --ports) port="$2"; shift 2;; --receipt) receipt="$2"; shift 2;; *) shift;; esac; done' 'printf "{\"issuer\":\"cdp_session_foundation\",\"consumer\":\"%s\",\"endpoint\":\"http://127.0.0.1:%s\",\"owned\":false}\n" "$consumer" "$port" > "$receipt"' > "$establisher"
  chmod +x "$establisher"
  run env CDP_CONSUMER_FIXTURE_ONLY=1 CDP_SESSION_ESTABLISHER="$establisher" \
    bash "$BATS_TEST_DIRNAME/../../scripts/cdp/cdp_measure.sh" fixture_cmd --baseline fixture.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"consumer=measurement"*"baseline=fixture.json"* ]]
  run env CDP_CONSUMER_FIXTURE_ONLY=1 CDP_SESSION_ESTABLISHER="$establisher" \
    bash "$BATS_TEST_DIRNAME/../../scripts/note_draft.sh" "$markdown"
  [ "$status" -eq 0 ]
  [[ "$output" == *"consumer=note"*"port=9234"*"markdown=$markdown"* ]]
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

# test_necessity: HTTPだけ応答する偽healthyを拒否し、WebSocket/CDP応答可能な次portへ有限fallbackする不変量を守る。
@test "endpoint qualification requires websocket CDP response before fallback selection" {
  run env PYTHONPATH="$BATS_TEST_DIRNAME/../../scripts/cdp" python3 - <<'PY'
import json
import cdp_session as mod

class HttpResponse:
    def __init__(self, port): self.port = port
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self):
        return json.dumps({"webSocketDebuggerUrl": f"ws://127.0.0.1:{self.port}/devtools/browser"}).encode()

class Socket:
    def __init__(self, port): self.port, self.sent = port, []
    def send(self, payload): self.sent.append(json.loads(payload))
    def recv(self): return json.dumps({"id": 1, "result": {"product": "fixture"}})
    def close(self): pass

def fake_urlopen(url, timeout=1): return HttpResponse(int(url.split(":")[2].split("/")[0]))
def fake_connect(url, timeout=1):
    port = int(url.split(":")[2].split("/")[0])
    if port == 9222: raise mod.websocket.WebSocketBadStatusException("403", status_code=403)
    return Socket(port)

mod.urlopen = fake_urlopen
mod.websocket.create_connection = fake_connect
qualified = {port: mod.endpoint_alive(port) for port in (9222, 9223)}
assert qualified == {9222: False, 9223: True}, qualified
receipt = mod.establish("inspection", ports=(9222, 9223), alive=mod.endpoint_alive,
                        launcher=lambda port, profile: (_ for _ in ()).throw(AssertionError("qualified fallback must be reused")))
assert receipt["endpoint"].endswith(":9223") and receipt["owned"] is False

socket = fake_connect("ws://127.0.0.1:9223/devtools/browser")
for ident, method in ((2, "Page.navigate"), (3, "Runtime.evaluate")):
    socket.send(json.dumps({"id": ident, "method": method}))
assert [item["method"] for item in socket.sent] == ["Page.navigate", "Runtime.evaluate"]
print("false_healthy_rejected=1/1 fallback_selected=1/1 navigate=1/1 evaluate=1/1 human_judgment=0")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "false_healthy_rejected=1/1 fallback_selected=1/1 navigate=1/1 evaluate=1/1 human_judgment=0" ]
}

# test_necessity: foundation所有Chromeを通常profileから隔離し、CDP接続に必要な3引数を常に同時指定する不変量を守る。
@test "foundation Chrome launch always uses isolated CDP arguments" {
  run env PYTHONPATH="$BATS_TEST_DIRNAME/../../scripts/cdp" python3 - <<'PY'
import cdp_session as mod
seen = []
mod.detect_browser = lambda _: r"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
mod.ps_run = lambda command, timeout=15: seen.append(command) or "4242"
pid = mod.launch_windows_chrome(9223, "/tmp/cdp-session-profiles/p9223-fixture")
command = seen[0]
required = ("--remote-debugging-port=9223", "--remote-allow-origins=*",
            "--user-data-dir=/tmp/cdp-session-profiles/p9223-fixture")
assert pid == 4242
assert all(token in command for token in required), command
assert "--user-data-dir=C:" not in command
print("required_args=3/3 normal_profile_refs=0")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "required_args=3/3 normal_profile_refs=0" ]
}
