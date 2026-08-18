#!/usr/bin/env python3
"""note_image_insert.py — note.com下書きへ画像を挿入しキャプション(=ALT相当)を記入する(CDP)。

Usage:
  python3 scripts/note_image_insert.py <editor_url> <spec.json> [--port 9234]
spec.json = [{"marker": "本文中の一意な文字列(この直前に挿入)", "file": "C:\\\\path\\\\to\\\\img.png", "caption": "図の説明"}, ...]

契約:
  - 事前に note_draft.sh でテキスト下書きを保存し、editor_url(https://editor.note.com/notes/<id>/edit/)を得ていること
  - file はWindows形式の絶対パス(DOM.setFileInputFiles はChrome側パス)
  - marker は段落先頭の文(例: 「上図は〜」「〜を図にしました」)。ProseMirrorはカーソル位置でfigureを挿入し段落を分割する
  - Page.setInterceptFileChooserDialog で OSダイアログを抑止し、fileChooserOpened の backendNodeId へ setFileInputFiles(fallback: input[type=file])
  - 挿入後、figcaption へ Input.insertText でキャプションを記入 → 下書き保存 → 別タブで再読込し imgs 数と各figの前後文を検証して stdout へ JSON 出力
教訓(2026-08-18): 「画像」ボタンclickはWindowsのファイル選択ダイアログを開きrendererを固める。抑止しない場合は閉じるまでタブが応答しない。
"""
import sys, json, time, urllib.request, argparse
try:
    import websocket  # websocket-client
except ImportError:
    print("FAIL: pip install websocket-client", file=sys.stderr); sys.exit(1)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('url'); ap.add_argument('spec'); ap.add_argument('--port',type=int,default=9234)
    a=ap.parse_args(); P=a.port; spec=json.load(open(a.spec,encoding='utf-8'))
    tabs=json.loads(urllib.request.urlopen(f"http://127.0.0.1:{P}/json").read())
    tab=next((t for t in tabs if t['type']=='page' and a.url.split('/edit')[0] in t['url']),None)
    if not tab:
        tab=json.loads(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{P}/json/new?{a.url}",method="PUT")).read()); time.sleep(8)
    ws=websocket.create_connection(tab['webSocketDebuggerUrl'],timeout=30); mid=[0]
    def send(m,p=None):
        mid[0]+=1; ws.send(json.dumps({"id":mid[0],"method":m,"params":p or {}}))
        while True:
            r=json.loads(ws.recv())
            if r.get('id')==mid[0]: return r
    def ev(js): return send("Runtime.evaluate",{"expression":js,"returnByValue":True})['result']['result'].get('value')
    send("Page.enable"); send("DOM.enable"); send("Runtime.enable"); send("Page.setInterceptFileChooserDialog",{"enabled":True})
    for _ in range(10):
        n=ev("(function(){var e=document.querySelector('.ProseMirror');return e?e.innerText.length:-1})()")
        if n and n>0: break
        time.sleep(3)
    if not n or n<=0: print("FAIL: editor not ready"); sys.exit(1)
    for it in spec:
        js="""(function(){var editor=document.querySelector('.ProseMirror');var w=document.createTreeWalker(editor,NodeFilter.SHOW_TEXT);var n;while((n=w.nextNode())){var i=n.textContent.indexOf(%s);if(i>=0){n.parentNode.scrollIntoView({block:'center'});var r=document.createRange();r.setStart(n,i);r.collapse(true);var s=window.getSelection();s.removeAllRanges();s.addRange(r);editor.focus();return 'ok';}}return null;})()"""%json.dumps(it['marker'])
        if ev(js)!='ok': print(f"FAIL: marker not found: {it['marker']}"); sys.exit(1)
        time.sleep(0.5)
        jsb="""(function(){var all=document.querySelectorAll('button');for(var i=0;i<all.length;i++){var r=all[i].getBoundingClientRect();if(all[i].textContent.trim()==='画像'&&r.x>100&&r.y>50&&r.width>0){all[i].click();return 'clicked';}}for(var i=0;i<all.length;i++){var r=all[i].getBoundingClientRect();if(r.x<200&&r.y>100&&r.width>0&&all[i].querySelector('svg')&&all[i].textContent.trim()===''){all[i].click();return 'plus';}}return 'none';})()"""
        r=ev(jsb); time.sleep(0.8)
        if r=='plus': r=ev(jsb); time.sleep(0.8)
        if r!='clicked': print("FAIL: 画像 button not found"); sys.exit(1)
        bid=None; t0=time.time(); ws.settimeout(1)
        while time.time()-t0<5:
            try: m=json.loads(ws.recv())
            except Exception: continue
            if m.get('method')=='Page.fileChooserOpened': bid=m['params'].get('backendNodeId'); break
        ws.settimeout(30)
        if bid: send("DOM.setFileInputFiles",{"backendNodeId":bid,"files":[it['file']]})
        else:
            root=send("DOM.getDocument",{"depth":-1})['result']['root']['nodeId']
            nids=send("DOM.querySelectorAll",{"nodeId":root,"selector":"input[type=file]"})['result'].get('nodeIds',[])
            if not nids: print("FAIL: file input not found"); sys.exit(1)
            send("DOM.setFileInputFiles",{"nodeId":nids[-1],"files":[it['file']]})
        time.sleep(6)
        before=ev("document.querySelectorAll('.ProseMirror figure').length")
        cap=it.get('caption','')
        if cap:
            # 直近挿入 = markerを含む段落の直前のfigure
            js2="""(function(){var editor=document.querySelector('.ProseMirror');var kids=[...editor.children];var w=document.createTreeWalker(editor,NodeFilter.SHOW_TEXT);var n;while((n=w.nextNode())){if(n.textContent.indexOf(%s)>=0)break;}var p=n;while(p&&p.parentNode!==editor)p=p.parentNode;var i=kids.indexOf(p);for(var j=i-1;j>=0;j--){if(kids[j].tagName==='FIGURE'){var fc=kids[j].querySelector('figcaption');var rng=document.createRange();rng.selectNodeContents(fc);rng.collapse(true);var s=window.getSelection();s.removeAllRanges();s.addRange(rng);editor.focus();return 'ok';}}return null;})()"""%json.dumps(it['marker'])
            # 既存キャプション(殿が手で記入済み等)は上書きしない
            js_has="""(function(){var editor=document.querySelector('.ProseMirror');var s=window.getSelection();var n=s.anchorNode;while(n&&n.nodeName!=='FIGCAPTION')n=n.parentNode;return n?n.textContent.trim().length:-1;})()"""
            if ev(js2)=='ok' and (ev(js_has) or 0)<=0:
                time.sleep(0.4); send("Input.insertText",{"text":cap}); time.sleep(0.5)
        print(f"inserted {it['file'].split(chr(92))[-1]} figures={before}")
    ev("(function(){var b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='下書き保存');if(b)b.click();})()"); time.sleep(5); ws.close()
    # verify in fresh tab
    new=json.loads(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{P}/json/new?{a.url}",method="PUT")).read()); time.sleep(10)
    ws=websocket.create_connection(new['webSocketDebuggerUrl'],timeout=30)
    def ev2(js):
        ws.send(json.dumps({"id":1,"method":"Runtime.evaluate","params":{"expression":js,"returnByValue":True}}))
        while True:
            r=json.loads(ws.recv())
            if r.get('id')==1: return r['result']['result'].get('value')
    for _ in range(10):
        n=ev2("(function(){var e=document.querySelector('.ProseMirror');return e?e.innerText.length:-1})()")
        if n and n>0: break
        time.sleep(3)
    res=ev2("""(function(){var e=document.querySelector('.ProseMirror');var kids=[...e.children];var out=[];kids.forEach(function(k,i){if(k.tagName==='FIGURE'||k.querySelector('img')){var m=i+1;while(m<kids.length&&!kids[m].textContent.trim())m++;out.push({caption:(k.querySelector('figcaption')||{}).textContent||'',next:kids[m]?kids[m].textContent.slice(0,25):null});}});return {imgs:e.querySelectorAll('img').length,figs:out};})()""")
    ws.close()
    for t in json.loads(urllib.request.urlopen(f"http://127.0.0.1:{P}/json").read()):
        if t['type']=='page' and t['id']!=new['id']:
            try: urllib.request.urlopen(f"http://127.0.0.1:{P}/json/close/{t['id']}").read()
            except Exception: pass
    ok = res and res.get('imgs')==len(spec)
    print(json.dumps({"status":"PASS" if ok else "FAIL","expected":len(spec),"result":res},ensure_ascii=False))
    sys.exit(0 if ok else 1)
if __name__=='__main__': main()
