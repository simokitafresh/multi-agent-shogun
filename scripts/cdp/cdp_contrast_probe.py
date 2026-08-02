#!/usr/bin/env python3
# cdp_contrast_probe.py — 本番CDPでlight/dark両モードのWCAGコントラスト全数監査を行う恒久probe。
# 対象: (1)テキスト要素のcolor vs 実効背景(祖先の不透明backgroundを合成) → 4.5:1(大文字3:1)未満を違反として列挙
#       (2)チャート要素の色収集: SVG(path stroke/rect fill) + HTML div棒(子なし・棒状サイズのbackgroundColor)
#          → SVGしか見ないとdiv実装ヒストグラムを見落とす(2026-07-23 rolling-returns cyan-500事故の再発防止)
# 除外: 透明/アルファ0の色、offsetParentなし(非表示)要素。
# Usage: python3 scripts/cdp/cdp_contrast_probe.py --base <url> --routes /a,/b [--port 9222] [--modes light,dark]
# 出力: JSON {"violations":{(mode:route): [...]}, "chart_colors":{(mode:route): {...}}, "summary":[ユニーク違反ペア]}
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import importlib.util

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("edp", os.path.join(_HERE, "cdp_ed_probe.py"))
edp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(edp)

AUDIT_JS = r"""
JSON.stringify((function(){
  function lum(c){var m=c.match(/\d+(\.\d+)?/g); if(!m)return null; if(m.length>3&&parseFloat(m[3])===0)return null;
    var v=[0,1,2].map(i=>{var x=parseInt(m[i])/255; return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4);});
    return 0.2126*v[0]+0.7152*v[1]+0.0722*v[2];}
  function effBg(el){var e=el; while(e){var b=getComputedStyle(e).backgroundColor; var mm=b.match(/\d+(\.\d+)?/g);
    if(mm && (mm.length<4 || parseFloat(mm[3])>0.9)) return b; e=e.parentElement;} return getComputedStyle(document.body).backgroundColor;}
  var seen={}, viol=[];
  [...document.querySelectorAll('body *')].forEach(function(e){
    if(!e.offsetParent) return;
    if(![...e.childNodes].some(n=>n.nodeType===3&&n.textContent.trim().length>1)) return;
    var g=getComputedStyle(e); var fg=g.color; var bg=effBg(e);
    var key=fg+'|'+bg; if(seen[key])return; seen[key]=1;
    var l1=lum(fg), l2=lum(bg); if(l1===null||l2===null)return;
    var ratio=(Math.max(l1,l2)+0.05)/(Math.min(l1,l2)+0.05);
    var fs=parseFloat(g.fontSize); var bold=parseInt(g.fontWeight)>=700;
    var req=((fs>=24)||(fs>=18.66&&bold))?3:4.5;
    if(ratio<req) viol.push({fg:fg,bg:bg,ratio:Math.round(ratio*100)/100,fs:fs,txt:e.textContent.trim().slice(0,24),cls:String(e.className).slice(0,50)});
  });
  var chart={svg_strokes:{},svg_fills:{},div_bars:{}};
  [...document.querySelectorAll('svg')].forEach(function(svg){
    [...svg.querySelectorAll('path')].forEach(p=>{var s=p.getAttribute('stroke');if(s&&s!=='none')chart.svg_strokes[getComputedStyle(p).stroke]=(chart.svg_strokes[getComputedStyle(p).stroke]||0)+1;});
    [...svg.querySelectorAll('rect,path')].forEach(p=>{var f=p.getAttribute('fill');if(f&&f!=='none'&&f!=='transparent'){var rr=p.getBoundingClientRect();if(rr.height>3&&rr.width>2)chart.svg_fills[getComputedStyle(p).fill]=(chart.svg_fills[getComputedStyle(p).fill]||0)+1;}});
  });
  [...document.querySelectorAll('div,span')].forEach(function(e){
    if(e.children.length) return;
    var g=getComputedStyle(e); var b=g.backgroundColor; var r=e.getBoundingClientRect();
    if(b&&b!=='rgba(0, 0, 0, 0)'&&r.width>2&&r.width<80&&r.height>8&&r.height<400){chart.div_bars[b]=(chart.div_bars[b]||0)+1;}
  });
  for(var k in chart.div_bars){ if(chart.div_bars[k]<5) delete chart.div_bars[k]; }
  return {violations:viol, chart:chart};
})());
"""


def run(port, base, routes, modes):
    import websocket
    host = base.split("//", 1)[-1].split("/", 1)[0]

    def send(ws, mid, method, params):
        ws.send(json.dumps({"id": mid, "method": method, "params": params}))
        while True:
            m = json.loads(ws.recv())
            if m.get("id") == mid:
                return m

    out = {"violations": {}, "chart_colors": {}}
    for mode in modes:
        for route in routes:
            wsu = edp._get_page_ws(port, host)
            ws = websocket.create_connection(wsu, timeout=40)
            send(ws, 1, "Runtime.evaluate", {"expression": f"location.href={json.dumps(base + route + '?_cp=' + str(int(time.time()*1000)))};0"})
            ws.close()
            time.sleep(3.5)
            edp._poll_until_stable(port, route, 15, 1)
            wsu = edp._get_page_ws(port, route)
            ws = websocket.create_connection(wsu, timeout=40)
            op = "add" if mode == "dark" else "remove"
            send(ws, 2, "Runtime.evaluate", {"expression": f"document.documentElement.classList.{op}('dark');0"})
            for y in (800, 2000, 3600):
                send(ws, 3, "Runtime.evaluate", {"expression": f"window.scrollTo(0,{y});0"})
                time.sleep(0.5)
            r = send(ws, 4, "Runtime.evaluate", {"expression": AUDIT_JS, "returnByValue": True})
            ws.close()
            data = json.loads(r["result"]["result"]["value"])
            key = f"{mode}:{route}"
            if data["violations"]:
                out["violations"][key] = data["violations"]
            out["chart_colors"][key] = data["chart"]
    agg = {}
    for k, vs in out["violations"].items():
        for v in vs:
            pk = (v["fg"], v["bg"])
            e = agg.setdefault(pk, {"ratio": v["ratio"], "pages": [], "example": v["txt"], "cls": v["cls"]})
            e["pages"].append(k)
    out["summary"] = [{"fg": fg, "bg": bg, **info} for (fg, bg), info in sorted(agg.items(), key=lambda x: x[1]["ratio"])]
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--routes", required=True)
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--modes", default="light,dark")
    a = ap.parse_args(); a.port = edp.receipt_port(edp.session_receipt(a.port))
    result = run(a.port, a.base.rstrip("/"), [r for r in a.routes.split(",") if r], [m for m in a.modes.split(",") if m])
    print(json.dumps(result, ensure_ascii=False, indent=1))
    sys.exit(0 if not result["summary"] else 1)
