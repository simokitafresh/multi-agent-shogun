#!/usr/bin/env python3
# cdp_font_probe.py — 本番CDP getComputedStyleで表フォントを役割別に実測する再利用ツール。
#
# 目的: UIスタイル統一(MECE設計書 §6.1)の偵察入口・検証出口。ソースgrepは描画を見ない
#       (CSS継承/上書き/グループセレクタ/条件分岐class/semantic token)ため、計算済みスタイルを実測する。
#
# なぜこのツールが要るか(2026-07-23 将軍が固定sleepの浪費を実測):
#   従来の場当たり実測は各ページで固定 sleep 15s していたが、本番の表+セルは約2sで完全充填し
#   2〜10sで安定する(将軍実測: 2s時点でcells=184、以降不変)。固定15sは1ページあたり約13sの純浪費で、
#   1セッションで20ページ超を測ると4〜5分を無駄にした。本ツールはセル数が安定するまでポーリングし、
#   安定を検知した瞬間に測定へ進む(通常2〜4s)。固定sleepを廃止し実測を約5倍速化する。
#
# Usage:
#   python3 scripts/cdp/cdp_font_probe.py --base https://dm-signal-frontend.onrender.com \
#       --routes /summary,/metrics,/rolling-returns [--port 9222] [--max-wait 20] [--role]
#   認証が要るページは、事前にCDPセッションのlocalStorageへviewer tokenを注入しておくこと
#   (§6.1手順: Render API env-varsのVIEWER_PASS→/api/auth/verify-viewer→localStorage dm_viewer_token)。
#
# Output: routeごとに、role別(header/body-number/body-text)のfont-size|family|weightの計算済み値の集計をJSONで出力。
#
# Exit: 0=全route測定成功、1=接続失敗/対象0。

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def _get_page_ws(port: int, url_substr: str) -> str | None:
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/json/list", timeout=10) as fh:
            targets = json.load(fh)
    except Exception:
        return None
    for t in targets:
        if t.get("type") == "page" and url_substr in (t.get("url") or ""):
            return t.get("webSocketDebuggerUrl")
    # url_substr未一致なら最初のpageを返す(navigate前でも掴めるように)
    for t in targets:
        if t.get("type") == "page":
            return t.get("webSocketDebuggerUrl")
    return None


def _make_evaluator(ws_url: str):
    import websocket  # lazy import; caller ensures availability

    ws = websocket.create_connection(ws_url, timeout=40)
    counter = {"id": 0}

    def ev(expr: str, await_promise: bool = True):
        counter["id"] += 1
        mid = counter["id"]
        ws.send(json.dumps({
            "id": mid,
            "method": "Runtime.evaluate",
            "params": {"expression": expr, "returnByValue": True, "awaitPromise": await_promise},
        }))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == mid:
                return msg.get("result", {}).get("result", {}).get("value")

    return ws, ev


# セルを役割別に分類してfont計算済み値を集計するJS。
# role: header / body-number(mono相当の数値内容) / body-text
_ROLE_JS = r"""
JSON.stringify([...document.querySelectorAll("table")].map(function(t){
  function bucket(cells){
    var m={};
    cells.forEach(function(c){
      var g=getComputedStyle(c);
      var txt=(c.textContent||"").trim();
      var isMono=/mono/.test(g.fontFamily);
      var numeric=/^[\s$€%+\-.,0-9]+$/.test(txt)&&txt.length>0;
      var role=isMono?"body-number":(numeric?"body-number(prop!)":"body-text");
      var k=role+" "+g.fontSize+"|"+g.fontFamily.split(",")[0].replace(/["]/g,"").trim()+"|w"+g.fontWeight;
      m[k]=(m[k]||0)+1;
    });
    return m;
  }
  var th=[...t.querySelectorAll("thead th, thead td")];
  var td=[...t.querySelectorAll("tbody td, tbody th")];
  var bare=[...t.querySelectorAll("td,th")].filter(function(x){return !x.closest("thead")&&!x.closest("tbody");});
  return {header:bucket(th), body:bucket(td.concat(bare))};
}));
"""

_COUNT_JS = 'JSON.stringify({t:document.querySelectorAll("table").length,c:document.querySelectorAll("table td,table th").length})'


def _poll_until_stable(port: int, url_substr: str, max_wait: float, interval: float) -> None:
    """table+cell数が2回連続で同値かつ>0になるまでポーリング。固定sleepの代替。"""
    prev = None
    stable = 0
    waited = 0.0
    while waited < max_wait:
        time.sleep(interval)
        waited += interval
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
        if cur.get("t", 0) > 0 and cur == prev:
            stable += 1
            if stable >= 1:  # 2回連続同値(prev==cur)で安定とみなす
                return
        else:
            stable = 0
        prev = cur
    # max_wait到達: そのまま測定へ(タイムアウトは呼び出し側が結果0で判断)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="e.g. https://dm-signal-frontend.onrender.com")
    ap.add_argument("--routes", required=True, help="comma-separated, e.g. /summary,/metrics")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--max-wait", type=float, default=20.0, help="cold backend上限秒")
    ap.add_argument("--interval", type=float, default=1.0, help="ポーリング間隔秒")
    args = ap.parse_args()
    from cdp_ed_probe import receipt_port, session_receipt
    args.port = receipt_port(session_receipt(args.port))

    try:
        import websocket  # noqa: F401
    except ImportError:
        import subprocess
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "websocket-client"], check=False)

    base = args.base.rstrip("/")
    routes = [r for r in args.routes.split(",") if r]
    out: dict[str, object] = {}

    for route in routes:
        ws = _get_page_ws(args.port, base.split("//", 1)[-1].split("/", 1)[0])
        if not ws:
            out[route] = {"error": "no page target (Chrome CDP未接続?)"}
            continue
        # navigate(cache-bypassの一意クエリ付き)
        try:
            conn, ev = _make_evaluator(ws)
        except Exception as exc:
            out[route] = {"error": f"ws connect failed: {exc}"}
            continue
        try:
            ev(f"location.href={json.dumps(base + route + '?_cfp=' + str(int(time.time()*1000)))};0", await_promise=False)
        finally:
            conn.close()
        # 固定sleepでなくポーリングで安定待ち
        _poll_until_stable(args.port, route.split("?", 1)[0], args.max_wait, args.interval)
        # 測定(navigate後は新規WSで測る=実行コンテキスト喪失回避)
        ws2 = _get_page_ws(args.port, route.split("?", 1)[0])
        if not ws2:
            out[route] = {"error": "post-nav page target not found"}
            continue
        try:
            conn2, ev2 = _make_evaluator(ws2)
        except Exception as exc:
            out[route] = {"error": f"post-nav ws failed: {exc}"}
            continue
        try:
            sig = ev2(_ROLE_JS)
        finally:
            conn2.close()
        try:
            out[route] = json.loads(sig) if sig else []
        except Exception:
            out[route] = []

    print(json.dumps(out, ensure_ascii=False))
    # 全routeがerror/空なら1
    ok = any(isinstance(v, list) and v for v in out.values())
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
