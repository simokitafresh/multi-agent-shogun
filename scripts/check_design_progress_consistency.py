#!/usr/bin/env python3
"""設計書(dm-monthly-trade-bug)の§0現在地・§0.1トラッカー・§2.5 WBS Status列の整合を機械照合する。

版発行前に実行し、出力の検証値を§7履歴へ記す(家老v4.24 REVISE防御)。
検査: (1)WBSのGATE CLEAR/進行中集合を抽出 (2)トラッカーの件数・%を再計算して照合
      (3)§0現在地に旧版タイムスタンプ(現在地行が最新版時刻か)は人間確認用に表示のみ。
exit 0=一致 / exit 1=不一致(差分表示)。
"""
import re, sys

P = 'docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md'
s = open(P).read()

# WBS抽出(レーン節〜Phase5節)
wbs = s.split('### レーンA0')[1].split('### Phase 5')[0]
rows = re.findall(r'^\| ([^|]+?) \| ([^|]+?) \|', wbs, re.M)
rows = [(i.strip(), st.strip()) for i, st in rows if i.strip() not in ('ID', '---', ':---')]
rows = [(i, st) for i, st in rows if not set(i) <= set('-:')]
clear = sorted(i for i, st in rows if st.startswith('GATE CLEAR'))
prog = sorted(i for i, st in rows if st.startswith('進行中'))
total = len(rows)
score = len(clear) + 0.5 * len(prog)
pct = round(score / total * 100)

m = re.search(r'全体進捗: [█░]+\s+(\d+)% \(GATE CLEAR (\d+) \+ 進行中 (\d+)×0\.5', s)
ok = True
if not m:
    print('FAIL: トラッカー全体行が見つからない'); ok = False
else:
    tp, tc, tg = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if (tc, tg) != (len(clear), len(prog)):
        print(f'FAIL: トラッカー件数 CLEAR={tc}/進行中={tg} vs WBS実測 CLEAR={len(clear)}/進行中={len(prog)}'); ok = False
    if tp != pct:
        print(f'FAIL: トラッカー%={tp} vs 再計算={pct}'); ok = False

# レーン行の「XX待ち」理由がCLEAR済み工程を指していないか(家老v4.26防御)
for lane_m in re.finditer(r'^レーン[^:]+:.*?\(([^)]*)\)', s, re.M):
    for wid in re.findall(r'([A-Z]\d[\w.\-]*(?:残件)?)待ち', lane_m.group(1)):
        if wid in clear:
            print(f'FAIL: レーン注記「{wid}待ち」だが{wid}はCLEAR済み(stale待ち理由)'); ok = False

# §0.1見込みブロック内の「XXX(進行中)」参照がWBS進行中集合と一致するか(家老v4.25防御)
mikomi = s.split('見込み時間(根拠', 1)
if len(mikomi) > 1:
    mikomi_txt = mikomi[1].split('- 進捗の定義', 1)[0]
    refs = re.findall(r'([A-Z]\d[\w.\-]*(?:残件)?)(?:オラクル)?\((進行中|未配備|CLEAR済み)\)', mikomi_txt)
    for rid, tag in refs:
        if tag == '進行中' and rid not in prog:
            print(f'FAIL: 見込み内「{rid}(進行中)」がWBS進行中集合{prog}に不在(stale依存)'); ok = False

genzaichi = re.search(r'- \*\*現在地\(([^)]+)\)\*\*', s)
header_ver = re.search(r'設計書 (v[\d.]+)', s)
print(f'VERIFY: 版={header_ver.group(1) if header_ver else "?"} 母数={total} CLEAR={len(clear)}件{clear} 進行中={len(prog)}件{prog} score={score} pct={pct}% 現在地時刻={genzaichi.group(1) if genzaichi else "?"}')
sys.exit(0 if ok else 1)
