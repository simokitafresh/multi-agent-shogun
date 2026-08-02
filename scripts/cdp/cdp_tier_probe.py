#!/usr/bin/env python3
# tier probe — cap(max-width祖先)/中央寄せ/sticky/可視性 を本番CDPで実測
import argparse, json, os, sys, time, importlib.util

_ROOT = os.environ.get("REPO_ROOT", os.getcwd())
spec = importlib.util.spec_from_file_location("edp", os.path.join(_ROOT, "scripts/cdp/cdp_ed_probe.py"))
edp = importlib.util.module_from_spec(spec); spec.loader.exec_module(edp)

JS = r"""
JSON.stringify([...document.querySelectorAll("table")].map(function(t){
  function cs(el){return el?getComputedStyle(el):null;}
  var visible = !!t.offsetParent;
  var cap=null, el=t.parentElement, d=0;
  while(el&&d<8){var g=cs(el); if(g&&g.maxWidth&&g.maxWidth!=="none"){cap={el:el.tagName+"."+(el.className||"").toString().slice(0,60),maxWidth:g.maxWidth,marginLeft:g.marginLeft,marginRight:g.marginRight};break;} el=el.parentElement;d++;}
  var r=t.getBoundingClientRect();
  var vw=document.documentElement.clientWidth;
  var th=t.querySelector("thead th");
  var thg=cs(th);
  var td0=t.querySelector("tbody tr td, tbody tr th");
  var col1=cs(td0);
  return {
    caption:(th?th.textContent.trim().slice(0,20):"table"),
    visible: visible,
    cap: cap,
    left: Math.round(r.left), right_gap: Math.round(vw-r.right), width: Math.round(r.width),
    thead_position: thg?thg.position:null, thead_top: thg?thg.top:null,
    col1_position: col1?col1.position:null, col1_left: col1?col1.left:null
  };
}));
"""

def measure(port, base, routes):
    host = base.split("//",1)[-1].split("/",1)[0]
    out={}
    for route in routes:
        ws = edp._get_page_ws(port, host)
        if not ws: out[route]={"error":"no target"}; continue
        conn, ev = edp._make_evaluator(ws)
        try: ev(f"location.href={json.dumps(base+route+'?_tp='+str(int(time.time()*1000)))};0", await_promise=False)
        finally: conn.close()
        edp._poll_until_stable(port, route.split("?",1)[0], 20.0, 1.0)
        ws2 = edp._get_page_ws(port, route.split("?",1)[0])
        conn2, ev2 = edp._make_evaluator(ws2)
        try: sig = ev2(JS)
        finally: conn2.close()
        out[route]=json.loads(sig) if sig else []
    return out

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--base",required=True); ap.add_argument("--routes",required=True); ap.add_argument("--port",type=int,default=9222)
    a=ap.parse_args(); a.port=edp.receipt_port(edp.session_receipt(a.port))
    print(json.dumps(measure(a.port,a.base.rstrip("/"),[r for r in a.routes.split(",") if r]),ensure_ascii=False,indent=1))
