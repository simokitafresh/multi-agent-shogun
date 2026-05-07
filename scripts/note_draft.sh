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

readonly AUTO_OPS_DIR="/mnt/c/Python_app/auto-ops"
readonly CDP_PORT="${CDP_PORT:-9234}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "Usage: $0 <markdown_file>"
[[ -f "$1" ]] || die "File not found: $1"

MD_FILE="$(realpath "$1")"

echo "[note_draft] Markdown: ${MD_FILE}"
echo "[note_draft] CDP port: ${CDP_PORT}"

# ── Step 1-6: All in one Python script ──
python3 << PYEOF
import sys, os, time, json, base64, pathlib

sys.path.insert(0, "${AUTO_OPS_DIR}")
from cdp.cdp_helper import launch_browser, get_tab, js_eval, navigate, cdp_send, screenshot, _is_cdp_alive
from dotenv import load_dotenv

PORT = ${CDP_PORT}
MD_FILE = "${MD_FILE}"
ENV_FILE = pathlib.Path("${AUTO_OPS_DIR}") / ".env.note"
CAPTCHA_SCREENSHOT = pathlib.Path("/tmp/note_recaptcha_challenge.png")

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

def handle_recaptcha_if_present():
    if not maybe_click_recaptcha_checkbox():
        return
    state = wait_for_recaptcha_challenge_or_login()
    if state == "logged_in":
        return
    if state == "challenge":
        shot = screenshot(tab, str(CAPTCHA_SCREENSHOT), port=PORT)
        print(f"[note_draft] reCAPTCHA image challenge detected. Screenshot: {shot}")
        print("[note_draft] Solve the visible challenge in the browser or via agent vision; waiting up to 120s...")
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
      const email = document.querySelector('input[type="email"], input[name="email"], #email');
      const password = document.querySelector('input[type="password"], input[name="password"], #password');
      if (!email || !password) return {ok: false, reason: 'missing_form'};
      setValue(email, data.email);
      setValue(password, data.password);
      const buttons = Array.from(document.querySelectorAll('button, input[type="submit"]'));
      const login = buttons.find(b => /ログイン|login/i.test((b.innerText || b.value || '').trim())) || buttons[0];
      if (!login) return {ok: false, reason: 'missing_button'};
      login.click();
      return {ok: true};
    })()""")
    if not result or not result.get("ok"):
        raise RuntimeError(f"Login form automation failed: {result}")
    time.sleep(3)
    handle_recaptcha_if_present()
    final_url = wait_until_not_login(timeout=30)
    if not final_url:
        raise RuntimeError("Login did not complete. Check credentials or reCAPTCHA state.")
    print(f"[note_draft] Login successful: {final_url}")

# Step 1: Ensure Chrome is running
if not _is_cdp_alive(PORT):
    print(f"[note_draft] Launching Chrome on port {PORT}...")
    if not launch_browser(port=PORT):
        print("ERROR: Chrome launch failed", file=sys.stderr)
        sys.exit(1)
    time.sleep(3)
print(f"[note_draft] Chrome alive on port {PORT}")

# Step 2: Check login state
tab = get_tab(port=PORT)
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

# Step 3: Parse Markdown
with open(MD_FILE, encoding="utf-8") as f:
    lines = f.readlines()

title = ""
fallback_title = ""
sections = []
text_buf = []

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
    if line.startswith("## "):
        flush_text()
        heading = line[3:]
        if not fallback_title:
            fallback_title = heading
        sections.append({"type": "heading", "text": heading})
    elif line == "---":
        flush_text()
        sections.append({"type": "hr"})
    elif line.startswith("- "):
        flush_text()
        sections.append({"type": "bullet", "text": line[2:]})
    elif line.strip() == "":
        flush_text()
    elif line.startswith(chr(96) * 3):
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

# Step 5: Insert body
encoded = base64.b64encode(
    json.dumps(sections, ensure_ascii=False).encode("utf-8")
).decode("ascii")

# Focus body
js_eval(tab, "(function(){var b=document.querySelector('div[contenteditable]');if(b){b.focus();return 'ok';}return 'no';})()", port=PORT)

insert_js = """(function(){
  var body = document.querySelector('div[contenteditable]');
  body.focus();
  var raw = atob('""" + encoded + """');
  var decoded = decodeURIComponent(escape(raw));
  var sections = JSON.parse(decoded);
  var first = true;
  for(var i = 0; i < sections.length; i++){
    var s = sections[i];
    if(!first) document.execCommand('insertParagraph', false, null);
    if(s.type === 'heading'){
      document.execCommand('formatBlock', false, 'h3');
      document.execCommand('insertText', false, s.text);
    } else if(s.type === 'text' || s.type === 'bullet'){
      document.execCommand('formatBlock', false, 'p');
      document.execCommand('insertText', false, s.text);
    } else if(s.type === 'hr'){
      document.execCommand('insertHorizontalRule', false, null);
    }
    first = false;
  }
  return 'inserted ' + sections.length;
})()"""

result = js_eval(tab, insert_js, port=PORT)
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
