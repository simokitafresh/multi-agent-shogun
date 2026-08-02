#!/usr/bin/env python3
# cdp_card_probe.py — 本番CDP getComputedStyleで各ページの「カード」要素をMECE列挙する。
# カード = border(可視) または boxShadow(none以外) を持ち、かつ borderRadius>0 の視覚コンテナ。
# 各カードの radius/border/shadow と、内側の短いテキストラベル・table内包有無を報告する。
# cdp_font_probe.py の接続・ポーリング機構を流用。
# Usage: python3 scripts/cdp/cdp_card_probe.py --base <url> --routes /a,/b [--port 9222] [--max-wait 20]
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def _get_page_ws(port, url_substr):
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/json/list", timeout=10) as fh:
            targets = json.load(fh)
    except Exception:
        return None
    for t in targets:
        if t.get("type") == "page" and url_substr in (t.get("url") or ""):
            return t.get("webSocketDebuggerUrl")
    for t in targets:
        if t.get("type") == "page":
            return t.get("webSocketDebuggerUrl")
    return None


def _make_evaluator(ws_url):
    import websocket
    ws = websocket.create_connection(ws_url, timeout=40)
    counter = {"id": 0}

    def ev(expr, await_promise=True):
        counter["id"] += 1
        mid = counter["id"]
        ws.send(json.dumps({"id": mid, "method": "Runtime.evaluate",
                            "params": {"expression": expr, "returnByValue": True, "awaitPromise": await_promise}}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == mid:
                return msg.get("result", {}).get("result", {}).get("value")
    return ws, ev


# カード = (可視border or shadow) かつ 角丸>0。ネストは最外側のみ(親がカードなら子は除外)。
_CARD_JS = r"""
(function(){
  function isCard(g){
    var hasBorder=(parseFloat(g.borderTopWidth)>0 && g.borderTopStyle!=="none");
    var hasShadow=(g.boxShadow && g.boxShadow!=="none");
    var hasRadius=(parseFloat(g.borderTopLeftRadius)>0);
    return hasRadius && (hasBorder||hasShadow);
  }
  var all=[...document.querySelectorAll("div,section,article,aside")];
  var cards=all.filter(function(el){return isCard(getComputedStyle(el));});
  // 最外側のみ(祖先にカードがあれば除外)
  var outer=cards.filter(function(el){
    var p=el.parentElement;
    while(p){ if(cards.indexOf(p)>=0) return false; p=p.parentElement; }
    return true;
  });
  return JSON.stringify(outer.map(function(el){
    var g=getComputedStyle(el);
    var label=(el.getAttribute("aria-label")||"");
    if(!label){var h=el.querySelector("h1,h2,h3,h4,th,legend");label=h?h.textContent.trim().slice(0,28):"";}
    if(!label){label=(el.textContent||"").trim().slice(0,24);}
    return {
      label: label||"(no-label)",
      radius: g.borderTopLeftRadius,
      border: parseFloat(g.borderTopWidth)>0?(g.borderTopWidth+" "+g.borderTopStyle+" "+g.borderTopColor):"none",
      shadow: g.boxShadow==="none"?"none":"yes",
      bg: g.backgroundColor,
      has_table: !!el.querySelector("table")
    };
  }));
})()
"""

_COUNT_JS = 'JSON.stringify({t:document.querySelectorAll("table").length,c:document.querySelectorAll("main *").length})'


def _poll_until_stable(port, url_substr, max_wait, interval):
    prev = None; waited = 0.0
    while waited < max_wait:
        time.sleep(interval); waited += interval
        ws = _get_page_ws(port, url_substr)
        if not ws:
            continue
        try:
            conn, ev = _make_evaluator(ws)
        except Exception:
            continue
        try:
            raw = ev(_COUNT_JS)
        finally:
            conn.close()
        cur = json.loads(raw) if raw else {"t": 0, "c": 0}
        if cur.get("c", 0) > 0 and cur == prev:
            return
        prev = cur


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--routes", required=True)
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--max-wait", type=float, default=20.0)
    ap.add_argument("--interval", type=float, default=1.0)
    args = ap.parse_args()
    from cdp_ed_probe import receipt_port, session_receipt
    args.port = receipt_port(session_receipt(args.port))
    try:
        import websocket  # noqa
    except ImportError:
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "websocket-client"], check=False)

    base = args.base.rstrip("/")
    host = base.split("//", 1)[-1].split("/", 1)[0]
    out = {}
    for route in [r for r in args.routes.split(",") if r]:
        ws = _get_page_ws(args.port, host)
        if not ws:
            out[route] = {"error": "no target"}; continue
        try:
            conn, ev = _make_evaluator(ws)
        except Exception as exc:
            out[route] = {"error": str(exc)}; continue
        try:
            ev(f"location.href={json.dumps(base + route + '?_c=' + str(int(time.time()*1000)))};0", await_promise=False)
        finally:
            conn.close()
        _poll_until_stable(args.port, route.split("?", 1)[0], args.max_wait, args.interval)
        ws2 = _get_page_ws(args.port, route.split("?", 1)[0])
        if not ws2:
            out[route] = {"error": "post-nav"}; continue
        try:
            conn2, ev2 = _make_evaluator(ws2)
        except Exception as exc:
            out[route] = {"error": str(exc)}; continue
        try:
            sig = ev2(_CARD_JS)
        finally:
            conn2.close()
        try:
            out[route] = json.loads(sig) if sig else []
        except Exception:
            out[route] = []
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
