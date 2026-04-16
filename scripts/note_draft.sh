#!/usr/bin/env bash
# note_draft.sh — Markdown記事をnote.comに下書き保存する
# Usage: bash scripts/note_draft.sh <markdown_file>
#
# 前提:
#   - auto-ops/cdp/cdp_helper.py が使える ($AUTO_OPS_DIR)
#   - .env.note にNOTE_EMAIL/NOTE_PASSWORD がある
#   - Chrome on port $CDP_PORT がログイン済み
#     (未ログインなら「ログインしてください」と表示して終了)
#
# 手順:
#   1. Chrome接続確認 (launch_browser if needed)
#   2. ログイン状態チェック (note.com/notes/new → /login ならエラー)
#   3. Markdown → sections JSON変換
#   4. タイトル設定 (1行目の ## を使用)
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
import sys, os, time, json, base64

sys.path.insert(0, "${AUTO_OPS_DIR}")
from cdp.cdp_helper import launch_browser, get_tab, js_eval, navigate, cdp_send, _is_cdp_alive
from dotenv import load_dotenv

PORT = ${CDP_PORT}
MD_FILE = "${MD_FILE}"

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
    print("[note_draft] ERROR: Not logged in to note.com")
    print("[note_draft] Please login in the Chrome window (port ${CDP_PORT}), then re-run this script.")
    sys.exit(2)

print(f"[note_draft] Logged in. Editor: {url}")

# Step 3: Parse Markdown
with open(MD_FILE, encoding="utf-8") as f:
    lines = f.readlines()

title = ""
sections = []
text_buf = []

def flush_text():
    global text_buf
    if text_buf:
        sections.append({"type": "text", "text": "".join(text_buf).strip()})
        text_buf = []

for line in lines:
    line = line.rstrip("\\n")
    if line.startswith("## "):
        flush_text()
        heading = line[3:]
        if "戦国AI列伝" in heading or not title:
            title = heading  # First ## = title
            continue
        sections.append({"type": "heading", "text": heading})
    elif line == "---":
        flush_text()
        sections.append({"type": "hr"})
    elif line.startswith("- "):
        flush_text()
        sections.append({"type": "bullet", "text": line[2:]})
    elif line.strip() == "":
        flush_text()
    elif line.startswith("\`\`\`"):
        continue
    else:
        text_buf.append(line + " ")

flush_text()
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
