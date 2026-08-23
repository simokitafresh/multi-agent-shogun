#!/usr/bin/env bash
# note_draft.sh — Markdown記事をnote.comに下書き保存する
# Usage: bash scripts/note_draft.sh <markdown_file>
#
# 前提:
#   - auto-ops/cdp/cdp_helper.py が使える ($AUTO_OPS_DIR)
#   - .env.note にNOTE_EMAIL/NOTE_PASSWORD がある
#   - Chrome on port $CDP_PORT が起動可能
#   - 未ログインなら .env.note の NOTE_EMAIL/NOTE_PASSWORD で自動ログインする
#
# 手順:
#   1. Chrome接続確認 (launch_browser if needed)
#   2. ログイン状態チェック (未ログインならログイン+reCAPTCHA処理)
#   3. Markdown → sections JSON変換
#   4. タイトル設定 (最初の # h1 を使用)
#   5. 本文挿入 (ProseMirror execCommand)
#   6. 下書き保存
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "Usage: $0 <markdown_file>"
[[ -f "$1" ]] || die "File not found: $1"

readonly CDP_PORT="${CDP_PORT:-9234}"

# Source repo_root helper (no hardcoded path)
_ND_ROOT="${BASH_SOURCE[0]%/scripts/*}"
# shellcheck source=scripts/lib/repo_root.sh
source "${_ND_ROOT}/scripts/lib/repo_root.sh"
# shellcheck source=scripts/lib/project_path.sh
source "${_ND_ROOT}/scripts/lib/project_path.sh"
AUTO_OPS_DIR="$(get_project_path 'auto-ops')"
readonly AUTO_OPS_DIR

# WSL2でWindows実行ファイル(powershell.exe等)がPATHにない場合の補完。
# auto-ops cdp_helper.pyがpowershell.exe依存のため必須(殿裁定2026-07-16)。
export PATH="${PATH}:/mnt/c/Windows/System32/WindowsPowerShell/v1.0:/mnt/c/Windows/System32"
_REPO_ROOT="$(get_repo_root)"
_NOTE_RECEIPT="$(mktemp /tmp/cdp-note-receipt.XXXXXX)"
if [[ -n "${CDP_SESSION_ESTABLISHER:-}" ]]; then
  "$CDP_SESSION_ESTABLISHER" --consumer note --ports "$CDP_PORT" --receipt "$_NOTE_RECEIPT" >/dev/null
else
  python3 "${_REPO_ROOT}/scripts/cdp/cdp_session.py" establish --consumer note --ports "$CDP_PORT" --receipt "$_NOTE_RECEIPT" >/dev/null
fi
trap 'python3 "${_REPO_ROOT}/scripts/cdp/cdp_session.py" cleanup --receipt "$_NOTE_RECEIPT" >/dev/null 2>&1 || true; rm -f "$_NOTE_RECEIPT"' EXIT
if [[ "${CDP_CONSUMER_FIXTURE_ONLY:-0}" == "1" ]]; then
  echo "consumer=note receipt=$_NOTE_RECEIPT port=$CDP_PORT markdown=$1"
  trap - EXIT
  rm -f "$_NOTE_RECEIPT"
  exit 0
fi

MD_FILE="$(realpath "$1")"

echo "[note_draft] Markdown: ${MD_FILE}"
echo "[note_draft] CDP port: ${CDP_PORT}"

# ── Step 0: shared session receipt established above ──

# ── Step 1-6: All in one Python script ──
PY_EXIT=0
_PY_STDERR_FILE="/tmp/note_draft_stderr_$$.txt"
python3 << PYEOF 2>"$_PY_STDERR_FILE" || PY_EXIT=$?
import sys, os, time, json, base64, pathlib

sys.path.insert(0, "${AUTO_OPS_DIR}")
from cdp.cdp_helper import get_tab, create_tab, js_eval, navigate, cdp_send, screenshot
from dotenv import load_dotenv

PORT = ${CDP_PORT}
MD_FILE = "${MD_FILE}"
ENV_FILE = pathlib.Path("${AUTO_OPS_DIR}") / ".env.note"
CAPTCHA_SCREENSHOT = pathlib.Path("/tmp/note_recaptcha_challenge.png")
RECAPTCHA_BLOCK_HINT = (
    "External reCAPTCHA image challenge blocked by LS029 Level4 guard; "
    f"screenshot={CAPTCHA_SCREENSHOT}; "
    "complete login in the visible browser once and reuse the saved cookie/profile"
)

def runtime_eval(expression, timeout=30):
    response = cdp_send(
        tab,
        "Runtime.evaluate",
        {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        },
        port=PORT,
        timeout=timeout,
    )
    if response.get("exceptionDetails"):
        raise RuntimeError(response["exceptionDetails"].get("text", "JavaScript failed"))
    return response.get("result", {}).get("result", {}).get("value")

def dispatch_click(x, y):
    params = {"x": x, "y": y, "button": "left", "clickCount": 1}
    cdp_send(tab, "Input.dispatchMouseEvent", {**params, "type": "mousePressed"}, port=PORT)
    cdp_send(tab, "Input.dispatchMouseEvent", {**params, "type": "mouseReleased"}, port=PORT)

def wait_until_not_login(timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        url = js_eval(tab, "document.URL", port=PORT) or ""
        if "/login" not in url and "note.com" in url:
            return url
        time.sleep(1)
    return ""

def maybe_click_recaptcha_checkbox():
    frame = runtime_eval("""(() => {
      const frames = Array.from(document.querySelectorAll('iframe'));
      const anchor = frames.find(f => (f.src || '').includes('recaptcha/api2/anchor')
        || /reCAPTCHA|recaptcha/i.test(f.title || ''));
      if (!anchor) return null;
      const r = anchor.getBoundingClientRect();
      return {x: r.left + Math.min(35, r.width / 2), y: r.top + Math.min(35, r.height / 2)};
    })()""")
    if not frame:
        return False
    print("[note_draft] reCAPTCHA checkbox detected. Clicking iframe center...")
    dispatch_click(float(frame["x"]), float(frame["y"]))
    time.sleep(3)
    return True

def wait_for_recaptcha_challenge_or_login():
    deadline = time.time() + 10
    while time.time() < deadline:
        url = js_eval(tab, "document.URL", port=PORT) or ""
        if "/login" not in url and "note.com" in url:
            return "logged_in"
        has_challenge = runtime_eval("""(() => Array.from(document.querySelectorAll('iframe'))
          .some(f => (f.src || '').includes('recaptcha/api2/bframe')))()""")
        if has_challenge:
            return "challenge"
        time.sleep(1)
    return "unknown"

def wait_for_prosemirror(max_reloads=2, wait_per_attempt=15):
    """ProseMirrorエディタの出現を待つ。スピナーで停止している場合はPage.reloadしてリトライ。"""
    for attempt in range(max_reloads + 1):
        deadline = time.time() + wait_per_attempt
        while time.time() < deadline:
            found = runtime_eval("""(() => {
              var el = document.querySelector('.ProseMirror.note-common-styles__textnote-body')
                    || document.querySelector('div.ProseMirror')
                    || document.querySelector('div[contenteditable]');
              return el ? 'found' : null;
            })()""")
            if found == "found":
                print(f"[note_draft] ProseMirror ready (attempt {attempt})")
                return True
            time.sleep(1)
        if attempt < max_reloads:
            print(f"[note_draft] ProseMirror not rendered after {wait_per_attempt}s. Reloading page (attempt {attempt + 1}/{max_reloads})...")
            cdp_send(tab, "Page.reload", {}, port=PORT)
            time.sleep(3)
    return False

def handle_recaptcha_if_present():
    if not maybe_click_recaptcha_checkbox():
        return
    state = wait_for_recaptcha_challenge_or_login()
    if state == "logged_in":
        return
    if state == "challenge":
        shot = screenshot(tab, str(CAPTCHA_SCREENSHOT), port=PORT)
        print(f"[note_draft] reCAPTCHA image challenge detected. Screenshot: {shot}")
        print("[note_draft] LS029 guard: automated image-tile solving is blocked; use browser login cookie reuse.")
        raise RuntimeError(RECAPTCHA_BLOCK_HINT)
    else:
        print("[note_draft] reCAPTCHA state unclear; waiting for login completion up to 120s...")
    if not wait_until_not_login(timeout=120):
        raise RuntimeError("reCAPTCHA challenge was not solved within 120 seconds")

def login_if_needed():
    url = js_eval(tab, "document.URL", port=PORT) or ""
    if "/login" not in url:
        return
    load_dotenv(ENV_FILE)
    email = os.environ.get("NOTE_EMAIL", "").strip()
    password = os.environ.get("NOTE_PASSWORD", "").strip()
    if not email or not password:
        raise RuntimeError(f"Missing NOTE_EMAIL/NOTE_PASSWORD in {ENV_FILE}")
    print("[note_draft] Not logged in. Filling note.com login form...")
    payload = json.dumps({"email": email, "password": password})
    result = runtime_eval("""(async () => {
      const data = """ + payload + """;
      const setValue = (el, value) => {
        const proto = el instanceof HTMLTextAreaElement
          ? window.HTMLTextAreaElement.prototype
          : window.HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        setter.call(el, value);
        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
      };
      const email = document.querySelector('input[type="email"], input[name="email"], input[name="login"], #email');
      const password = document.querySelector('input[type="password"], input[name="password"], #password');
      if (!email || !password) return {ok: false, reason: 'missing_form'};
      setValue(email, data.email);
      setValue(password, data.password);
      const buttons = Array.from(document.querySelectorAll('button, input[type="submit"]'));
      const login = buttons.find(b => /ログイン|login/i.test((b.innerText || b.value || '').trim())) || buttons[0];
      if (!login) return {ok: false, reason: 'missing_button'};
      const rect = login.getBoundingClientRect();
      return {ok: true, x: rect.x + rect.width / 2, y: rect.y + rect.height / 2};
    })()""")
    if not result or not result.get("ok"):
        raise RuntimeError(f"Login form automation failed: {result}")
    # invisible reCAPTCHAはJS click()を阻止するが、座標ベースのマウスクリックは通る
    dispatch_click(float(result["x"]), float(result["y"]))
    time.sleep(3)
    # invisible reCAPTCHAはログインボタンクリック時にバックグラウンド検証される。
    # まず短いタイムアウトでログイン完了を待つ。通らなければreCAPTCHA処理へ。
    quick_url = wait_until_not_login(timeout=8)
    if quick_url:
        print(f"[note_draft] Login succeeded without reCAPTCHA interaction: {quick_url}")
        return
    handle_recaptcha_if_present()
    final_url = wait_until_not_login(timeout=30)
    if not final_url:
        raise RuntimeError("Login did not complete. Check credentials or reCAPTCHA state.")
    print(f"[note_draft] Login successful: {final_url}")

# Step 1: receipt establishment already guaranteed a qualified endpoint.
print(f"[note_draft] Chrome alive on port {PORT}")

# Step 2: Check login state
tab = get_tab(port=PORT)
if not tab:
    print("[note_draft] No page tab found. Creating new tab...")
    tab = create_tab(url="about:blank", port=PORT)
    time.sleep(1)
if not tab:
    print("[note_draft] ERROR: No page tab available on CDP port", file=sys.stderr)
    sys.exit(1)
navigate(tab, "https://note.com/notes/new", port=PORT)
time.sleep(4)
url = js_eval(tab, "document.URL", port=PORT)

if "/login" in url:
    login_if_needed()
    navigate(tab, "https://note.com/notes/new", port=PORT)
    time.sleep(4)
    url = js_eval(tab, "document.URL", port=PORT)
    if "/login" in url:
        print("[note_draft] ERROR: Login completed but editor still redirects to login", file=sys.stderr)
        sys.exit(2)

print(f"[note_draft] Logged in. Editor: {url}")

# Step 2.5: Wait for ProseMirror editor to render (may be stuck on spinner)
if not wait_for_prosemirror():
    print("[note_draft] ERROR: ProseMirror editor did not render after reloads", file=sys.stderr)
    sys.exit(3)

# Step 3: Parse Markdown
with open(MD_FILE, encoding="utf-8") as f:
    lines = f.readlines()

title = ""
fallback_title = ""
sections = []
text_buf = []
CODE_FENCE = chr(96) * 3

def flush_text():
    global text_buf
    if text_buf:
        sections.append({"type": "text", "text": "".join(text_buf).strip()})
        text_buf = []

for line in lines:
    line = line.rstrip("\\n")
    if line.startswith("# "):
        if not title:
            title = line[2:].strip()
        continue
    if line.startswith("### "):
        flush_text()
        sections.append({"type": "subheading", "text": line[4:]})
    elif line.startswith("## "):
        flush_text()
        heading = line[3:]
        if not fallback_title:
            fallback_title = heading
        sections.append({"type": "heading", "text": heading})
    elif line.strip().startswith("https://"):
        flush_text()
        sections.append({"type": "link", "text": line.strip()})
    elif line == "---":
        flush_text()
        sections.append({"type": "hr"})
    elif line.startswith("- "):
        flush_text()
        sections.append({"type": "bullet", "text": line[2:]})
    elif line.startswith("\u25a0"):
        flush_text()
        sections.append({"type": "bullet", "text": line})
    elif line.strip() == "":
        flush_text()
    elif line.startswith(CODE_FENCE):
        continue
    else:
        text_buf.append(line + " ")

flush_text()
if not title:
    title = fallback_title
print(f"[note_draft] Title: {title}")
print(f"[note_draft] Sections: {len(sections)}")

# Step 4: Set title
js_eval(tab, """(function(){
  var ta = document.querySelector('textarea');
  if(!ta) return 'no_textarea';
  var ns = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, 'value').set;
  ns.call(ta, """ + json.dumps(title) + """);
  ta.dispatchEvent(new Event('input', {bubbles:true}));
  return 'ok';
})()""", port=PORT)
print("[note_draft] Title set")

# Step 5: Insert body via innerHTML (ProseMirror execCommand非対応のため)
# 連続するtext/bullet行は1つの<p>にまとめ、<br>で改行する（noteのp間マージン対策）
html_parts = []
text_acc = []

def flush_acc():
    global text_acc
    if text_acc:
        html_parts.append("<p>" + "<br>".join(text_acc) + "</p>")
        text_acc = []

for s in sections:
    if s["type"] == "heading":
        flush_acc()
        html_parts.append(f"<h2>{s['text']}</h2>")
    elif s["type"] == "subheading":
        flush_acc()
        html_parts.append(f"<h3>{s['text']}</h3>")
    elif s["type"] == "link":
        flush_acc()
        html_parts.append(f'<p><a href="{s["text"]}">{s["text"]}</a></p>')
    elif s["type"] in ("text", "bullet"):
        text_acc.append(s["text"])
    elif s["type"] == "hr":
        flush_acc()
        html_parts.append("<hr>")

flush_acc()

body_html = "\n".join(html_parts)
# Markdown bold **text** → <strong>text</strong>
import re
body_html = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', body_html)
encoded_html = base64.b64encode(body_html.encode("utf-8")).decode("ascii")

result = js_eval(tab, """(function(){
  var body = document.querySelector('.ProseMirror.note-common-styles__textnote-body')
          || document.querySelector('div.ProseMirror')
          || document.querySelector('div[contenteditable]');
  if(!body) return 'no_prosemirror';
  body.focus();
  var raw = atob('""" + encoded_html + """');
  var html = decodeURIComponent(escape(raw));
  body.innerHTML = html;
  body.dispatchEvent(new Event('input', {bubbles:true}));
  body.dispatchEvent(new Event('change', {bubbles:true}));
  return 'inserted ' + body.children.length;
})()""", port=PORT)
print(f"[note_draft] Body: {result}")

# Step 6: Save draft
time.sleep(1)
result = js_eval(tab, """(function(){
  var b = document.querySelectorAll('button');
  for(var i=0; i<b.length; i++){
    if(b[i].textContent.indexOf('下書き保存') >= 0){
      b[i].click();
      return 'saved';
    }
  }
  return 'no_save_btn';
})()""", port=PORT)
print(f"[note_draft] Draft: {result}")

time.sleep(2)
final_url = js_eval(tab, "document.URL", port=PORT)
print(f"[note_draft] Done: {final_url}")
PYEOF

# ── Step 7: Record to skill_execution_log ──
SKILL_LOG="${_REPO_ROOT}/logs/skill_execution_log.yaml"
AGENT_ID="${AGENT_ID:-$(tmux display-message -t "${TMUX_PANE}" -p '#{@agent_id}' 2>/dev/null || echo unknown)}"
TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
if [[ $PY_EXIT -eq 0 ]]; then
  RESULT="PASS"; STUMBLING=""; EXIT_CODE=0
else
  RESULT="FAIL"
  if [[ -s "$_PY_STDERR_FILE" ]]; then
    PY_ERR_DETAIL="$(tail -3 "$_PY_STDERR_FILE" | tr '\n' ' ' | cut -c1-150)"
    STUMBLING="Python exit ${PY_EXIT}: ${PY_ERR_DETAIL}"
  else
    STUMBLING="Python script exited with code ${PY_EXIT}"
  fi
  EXIT_CODE="$PY_EXIT"
  if [[ -s "$_PY_STDERR_FILE" ]] && grep -qiE 'reCAPTCHA challenge was not solved|Login did not complete.*reCAPTCHA|reCAPTCHA image challenge blocked|LS029 Level4 guard' "$_PY_STDERR_FILE"; then
    RESULT="SKIP"
    STUMBLING="External reCAPTCHA image challenge blocked by LS029 Level4 guard; draft creation skipped"
    EXIT_CODE=0
  fi
fi
rm -f "$_PY_STDERR_FILE"
cat >> "$SKILL_LOG" << LOGEOF
- ts: "${TS}"
  skill: "note-draft"
  executor: "${AGENT_ID}"
  result: "${RESULT}"
  used: "true"
  stumbling_points: "${STUMBLING}"
  gate: "none"
  source: "note_draft.sh"
  skill_path: "${BASH_SOURCE[0]}"
LOGEOF
echo "[note_draft] Logged to skill_execution_log: ${RESULT}"
exit "$EXIT_CODE"
# --- 自動防止ステップ (shellcheck対策: bashコメント化) ---
# ### 自動防止ステップ
# - <!-- skill-auto-improve:577c9ae42f3b --> 自動防止: gate=none のTop FAIL理由「Python exit 1: + CategoryInfo : OperationStopped: (WebSocket conne...th CDP on port?:String) [], RuntimeException + FullyQualifiedErrorId : WebSock」(count=2, last=2026-08-06T16:48:25+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
# - <!-- skill-auto-improve:f20f8777e67b --> 自動防止: gate=none のTop FAIL理由「Python exit 3: [note_draft] ERROR: ProseMirror editor did not render after reloads」(count=1, last=2026-06-18T22:12:34+0900)を避ける。確認: bash scripts/gates/gate_report_format.sh <report> を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い report_field_set.sh で修正後、gateを再実行する。
# <!-- skill-auto-improve:f39a5e08cea6 --> 自動防止: gate=none のTop FAIL理由「Python script exited with code 1」(count=3, last=2026-06-09T12:18:28+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
# <!-- skill-auto-improve:5fbd3c084bc2 --> 自動防止: gate=none のTop FAIL理由「Python exit 1: File "<stdin>", line 143, in login_if_needed File "<stdin>", line 105, in handle_recaptcha_if_present RuntimeError: reCAPTCHA challenge was not so」(count=1, last=2026-06-11T21:47:20+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
# skill-auto-improve:f39a5e08cea6 自動防止: gate=none Top FAIL「Python script exited with code 1」count=3 last=2026-06-09. gate_report_format.sh事前実行+FIXヒント修正
# skill-auto-improve:5fbd3c084bc2 自動防止: gate=none Top FAIL「Python exit 1 login_if_needed handle_recaptcha_if_present RuntimeError」count=1 last=2026-06-11. gate_report_format.sh事前実行+FIXヒント修正
# ### 自動防止ステップ
# - <!-- skill-auto-improve:267c35ffe8cc --> 自動防止: gate=none のTop FAIL理由「Python exit 1: File "/usr/lib/python3.12/subprocess.py", line 1253, in _check_timeout raise TimeoutExpired( subprocess.TimeoutExpired: Command '['powershell.ex」(count=1, last=2026-06-25T12:39:47+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
# ### 自動防止ステップ
# - <!-- skill-auto-improve:6a5c49b00216 --> 自動防止: gate=none のTop FAIL理由「Python exit 1: File "/usr/lib/python3.12/subprocess.py", line 1955, in _execute_child raise child_exception_type(errno_num, err_msg, err_filename) FileNotFound」(count=4, last=2026-07-16T18:32:59+0900)を避ける。確認: `bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する。修正: gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する。
