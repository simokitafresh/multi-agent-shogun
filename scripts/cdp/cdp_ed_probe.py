#!/usr/bin/env python3
# cdp_ed_probe.py — 本番CDP getComputedStyleで表のE軸(table構造)/D軸(card枠)を実測する。
# cdp_font_probe.py の接続・ポーリング機構を流用し、測定JSのみE/D軸へ差し替えたもの。
# E軸: thead境界線/tbody境界線・行stripe(奇偶背景)・セルpadding。D軸: 表を包むcardのborder/shadow/radius。
# Usage: python3 scripts/cdp/cdp_ed_probe.py --base <url> --routes /a,/b [--port 9222] [--max-wait 20]
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def session_receipt(requested_port=9222, consumer="inspection"):
    """Issue the sole connection authority for one consumer invocation."""
    from cdp_session import establish
    return establish(consumer, ports=(requested_port,))


def receipt_endpoint(receipt):
    if receipt.get("issuer") != "cdp_session_foundation":
        raise RuntimeError("CDP connection requires a foundation receipt")
    endpoint = str(receipt.get("endpoint", "")).strip().rstrip("/")
    if not endpoint:
        raise RuntimeError("CDP foundation receipt has no endpoint")
    return endpoint


def receipt_port(receipt):
    return int(receipt_endpoint(receipt).rsplit(":", 1)[1])


def _get_page_ws(endpoint: str, url_substr: str):
    try:
        with urllib.request.urlopen(f"{endpoint}/json/list", timeout=10) as fh:
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


def _make_evaluator(ws_url: str):
    import websocket
    ws = websocket.create_connection(ws_url, timeout=40)
    counter = {"id": 0}

    def ev(expr: str, await_promise: bool = True):
        counter["id"] += 1
        mid = counter["id"]
        ws.send(json.dumps({
            "id": mid, "method": "Runtime.evaluate",
            "params": {"expression": expr, "returnByValue": True, "awaitPromise": await_promise},
        }))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == mid:
                return msg.get("result", {}).get("result", {}).get("value")
    return ws, ev


_ED_JS = r"""
JSON.stringify([...document.querySelectorAll("table")].map(function(t){
  function cs(el){return el?getComputedStyle(el):null;}
  var thead=t.querySelector("thead");
  var tbody=t.querySelector("tbody");
  var theadCell=thead?thead.querySelector("th,td"):null;
  var rows=tbody?[...tbody.querySelectorAll("tr")]:[];
  function rowCell(i){var r=rows[i];return r?r.querySelector("td,th"):null;}
  function rowBg(i){var c=rowCell(i);var r=rows[i];var g=cs(c||r);return g?g.backgroundColor:null;}
  var td0=rowCell(0);
  var card=t.parentElement, cardStyle=null, depth=0;
  while(card&&depth<6){
    var gc=cs(card);
    if(gc&&(((gc.borderTopWidth&&gc.borderTopWidth!=="0px"))||(gc.boxShadow&&gc.boxShadow!=="none")||(gc.borderTopLeftRadius&&gc.borderTopLeftRadius!=="0px"))){
      cardStyle={border:gc.borderTopWidth+" "+gc.borderTopStyle+" "+gc.borderTopColor,radius:gc.borderTopLeftRadius,shadow:gc.boxShadow};break;
    }
    card=card.parentElement;depth++;
  }
  var thg=cs(theadCell), tdg=cs(td0);
  function pad(g){return g?(g.paddingTop+" "+g.paddingRight+" "+g.paddingBottom+" "+g.paddingLeft):null;}
  function bb(g){return g?(g.borderBottomWidth+" "+g.borderBottomStyle+" "+g.borderBottomColor):null;}
  return {
    caption:(t.getAttribute("aria-label")||(t.querySelector("thead th")?t.querySelector("thead th").textContent.trim().slice(0,24):"")||"table"),
    rows: rows.length,
    thead_border_bottom: bb(thg), thead_pad: pad(thg),
    td_border_bottom: bb(tdg), td_pad: pad(tdg),
    row_bg_0: rowBg(0), row_bg_1: rowBg(1), row_bg_2: rowBg(2),
    card: cardStyle
  };
}));
"""

_COUNT_JS = 'JSON.stringify({t:document.querySelectorAll("table").length,c:document.querySelectorAll("table td,table th").length})'


def _poll_until_stable(endpoint, url_substr, max_wait, interval):
    prev = None; waited = 0.0
    while waited < max_wait:
        time.sleep(interval); waited += interval
        ws = _get_page_ws(endpoint, url_substr)
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
        if cur.get("t", 0) > 0 and cur == prev:
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
    receipt = session_receipt(args.port)
    endpoint = receipt_endpoint(receipt)
    args.port = receipt_port(receipt)

    try:
        import websocket  # noqa: F401
    except ImportError:
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "websocket-client"], check=False)

    base = args.base.rstrip("/")
    routes = [r for r in args.routes.split(",") if r]
    host = base.split("//", 1)[-1].split("/", 1)[0]
    out = {}
    for route in routes:
        ws = _get_page_ws(endpoint, host)
        if not ws:
            out[route] = {"error": "no page target"}; continue
        try:
            conn, ev = _make_evaluator(ws)
        except Exception as exc:
            out[route] = {"error": f"ws connect: {exc}"}; continue
        try:
            ev(f"location.href={json.dumps(base + route + '?_ed=' + str(int(time.time()*1000)))};0", await_promise=False)
        finally:
            conn.close()
        _poll_until_stable(endpoint, route.split("?", 1)[0], args.max_wait, args.interval)
        ws2 = _get_page_ws(endpoint, route.split("?", 1)[0])
        if not ws2:
            out[route] = {"error": "post-nav target"}; continue
        try:
            conn2, ev2 = _make_evaluator(ws2)
        except Exception as exc:
            out[route] = {"error": f"post-nav ws: {exc}"}; continue
        try:
            sig = ev2(_ED_JS)
        finally:
            conn2.close()
        try:
            out[route] = json.loads(sig) if sig else []
        except Exception:
            out[route] = []

    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if any(isinstance(v, list) and v for v in out.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
