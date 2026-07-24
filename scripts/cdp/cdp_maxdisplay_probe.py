#!/usr/bin/env python3
# cdp_maxdisplay_probe.py — 表示最大化(スクロール最小化)の観点で各表の余白・幅・スクロールを実測。
# 統一主題=「テーブルの表示を最大化しスクロールを減らす」(殿裁定2026-07-23)のための計測。
# 各表について: 横スクロール有無(container scrollW>clientW)、card/wrapperの水平padding(奪われる幅)、
# 表幅 vs viewport幅の利用率、行高(縦密度=スクロール量)、列数・行数。
from __future__ import annotations
import argparse, json, sys, time, urllib.request


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
    c = {"id": 0}

    def ev(expr, await_promise=True):
        c["id"] += 1; mid = c["id"]
        ws.send(json.dumps({"id": mid, "method": "Runtime.evaluate",
                            "params": {"expression": expr, "returnByValue": True, "awaitPromise": await_promise}}))
        while True:
            m = json.loads(ws.recv())
            if m.get("id") == mid:
                return m.get("result", {}).get("result", {}).get("value")
    return ws, ev


_MAX_JS = r"""
JSON.stringify((function(){
  var vw=window.innerWidth;
  return [...document.querySelectorAll("table")].map(function(t){
    var g=getComputedStyle(t);
    // 横スクロールする祖先(overflow-x auto/scroll)を探す
    var sc=t.parentElement, scInfo=null, depth=0;
    while(sc&&depth<8){
      var sg=getComputedStyle(sc);
      if(/(auto|scroll)/.test(sg.overflowX)){
        scInfo={overflowX:sc.scrollWidth>sc.clientWidth+1, scrollW:sc.scrollWidth, clientW:sc.clientWidth};break;
      }
      sc=sc.parentElement;depth++;
    }
    // 表を囲むcard(border/shadow+radius)の水平padding=奪われる幅
    var card=t.parentElement, cardPadX=null, cardW=null, cdepth=0;
    while(card&&cdepth<6){
      var cg=getComputedStyle(card);
      if(parseFloat(cg.borderTopLeftRadius)>0&&((parseFloat(cg.borderTopWidth)>0)||cg.boxShadow!=="none")){
        cardPadX=parseFloat(cg.paddingLeft)+parseFloat(cg.paddingRight);
        cardW=card.clientWidth;break;
      }
      card=card.parentElement;cdepth++;
    }
    var firstRow=t.querySelector("tbody tr");
    var rowH=firstRow?Math.round(firstRow.getBoundingClientRect().height):null;
    var cols=firstRow?firstRow.children.length:(t.querySelector("thead tr")?t.querySelector("thead tr").children.length:null);
    var rows=t.querySelectorAll("tbody tr").length;
    return {
      caption:(t.querySelector("thead th")?t.querySelector("thead th").textContent.trim().slice(0,20):"table"),
      rows: rows, cols: cols, row_height: rowH,
      table_w: Math.round(t.getBoundingClientRect().width),
      viewport_w: vw,
      width_use_pct: Math.round(t.getBoundingClientRect().width/vw*100),
      h_scroll: scInfo?scInfo.overflowX:false,
      scroll_overflow_px: scInfo?(scInfo.scrollW-scInfo.clientW):0,
      card_pad_x: cardPadX,
      td_pad: (function(){var td=t.querySelector("tbody td");if(!td)return null;var tg=getComputedStyle(td);return tg.paddingTop+"/"+tg.paddingRight;})()
    };
  });
})())
"""

_COUNT_JS = 'JSON.stringify({t:document.querySelectorAll("table").length,c:document.querySelectorAll("main *").length})'


def _poll(port, sub, mw, iv):
    prev = None; w = 0.0
    while w < mw:
        time.sleep(iv); w += iv
        ws = _get_page_ws(port, sub)
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--routes", required=True)
    ap.add_argument("--port", type=int, default=9222); ap.add_argument("--max-wait", type=float, default=20.0)
    ap.add_argument("--interval", type=float, default=1.0)
    a = ap.parse_args()
    try:
        import websocket  # noqa
    except ImportError:
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "websocket-client"], check=False)
    base = a.base.rstrip("/"); host = base.split("//", 1)[-1].split("/", 1)[0]; out = {}
    for route in [r for r in a.routes.split(",") if r]:
        ws = _get_page_ws(a.port, host)
        if not ws:
            out[route] = {"error": "no target"}; continue
        try:
            conn, ev = _make_evaluator(ws)
        except Exception as e:
            out[route] = {"error": str(e)}; continue
        try:
            ev(f"location.href={json.dumps(base+route+'?_m='+str(int(time.time()*1000)))};0", await_promise=False)
        finally:
            conn.close()
        _poll(a.port, route.split("?", 1)[0], a.max_wait, a.interval)
        ws2 = _get_page_ws(a.port, route.split("?", 1)[0])
        if not ws2:
            out[route] = {"error": "post-nav"}; continue
        try:
            conn2, ev2 = _make_evaluator(ws2)
        except Exception as e:
            out[route] = {"error": str(e)}; continue
        try:
            sig = ev2(_MAX_JS)
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
