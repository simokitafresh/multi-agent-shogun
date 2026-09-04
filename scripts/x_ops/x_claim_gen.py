#!/usr/bin/env python3
"""claim_bank(主張の銀行)から投資ネタ Short を生成する(殿 2026-09-04 18:29『俺が何もしなくても無限に生成し続けるから意味がある』)。
記事本文は渡さない。入力=claim 1 行(belief/claim/why/number)+殿版 few-shot+system_prompt v5.x。
出力: queue/x_drafts/<date>_R<round>-S-<n>.txt、gate(x_post_gate.sh)、数字 fail-close(verified_numbers 以外の数字は FAIL)。
Usage: SHOGUN_ROOT=... python3 scripts/x_ops/x_claim_gen.py --round 6 --claims C04,C07 [--approve] [--format short|long]
殿指示 2026-09-04 18:55: 必須 4 項(belief/claim/why/audience)が無い claim は SKIP(記事が余っているから生成、は無い)。Long も claim 起点(claim→疑い→検証→数字→結論)。外部バズの語尾・煽りは移植しない
"""
import os, re, subprocess, sys, datetime as dt
from pathlib import Path
import yaml

ROOT = Path(os.environ.get("SHOGUN_ROOT", Path(__file__).resolve().parents[2]))
SP = (ROOT / "skills/x-post-pipeline/system_prompt_v5_1.txt").read_text(encoding="utf-8")
BANK = yaml.safe_load((ROOT / "skills/x-post-pipeline/claim_bank.yaml").read_text(encoding="utf-8"))
DRAFTS = ROOT / "queue/x_drafts"
FEW = """=== 殿版(合格)の実例。この書き方に合わせる(相槌→核→口語の落ち。全部説明しない) ===
[D-5 合格] 分散は平時に効いて、危機に効かない。／普段は相関の低い資産同士が、暴落の日には一斉に売られて相関が1に寄る。いちばん守ってほしい日に守ってくれないのが分散。／だから僕は相関に頼らず、弱くなったものを降りる仕組みを別に持ってる。
[A-1 殿版] 「S&P500に毎月積立、淡々と続けるだけ」。まあ正しいよね。／ただ平均を狙っても、格差は縮まらない。1千万と1億の差は30年後は拡大する。勝ち組だけが勝つのが平均狙い。／追いつくなら市場平均を上回るしかない。そういうハナシ。
[C-1 殿版] 「年率90%のバックテストです」と言われたら？／驚いたり疑ったり喜んだりする前にやることがある。／β調整後リターンをWFで分析しろ。／それでもαが残るか。／これでふるい落とされるような投資戦略はもろい。
[B-4 合格] 相場観は当たることもある。問題は当たった経験が次の判断を歪めること。／デュアルモメンタムは相場観を使わない。使わないから外れた時の言い訳もいらない。／月に一度ルールに従うだけ。再現できる方を選んだ。それだけの話なんだけど、これが一番難しい。
(／=空行)
"""


def llm(user):
    r = subprocess.run(["claude", "--print", "--setting-sources", "user", "--system-prompt", SP, user],
                       cwd=os.environ.get("SCRATCH", "/tmp"), capture_output=True, text=True, timeout=240)
    out = r.stdout.strip()
    return re.sub(r"^\s*(---|#+).*$", "", out, flags=re.M).strip()


def numbers_ok(text, allowed):
    body = text.replace(",", "").replace("％", "%")
    nums = set(re.findall(r"\d+(?:\.\d+)?", body))
    corpus = " ".join(allowed).replace(",", "")
    bad = [n for n in nums if n not in corpus and n not in ("1", "2", "3", "10", "100", "500")]
    return bad


def recheck(rnd, keys, approve):
    """生成済み draft を再判定(再生成しない)"""
    today = dt.date.today().isoformat(); vn = BANK["meta"]["verified_numbers"]; claims = {c["key"]: c for c in BANK["claims"]}
    for i, k in enumerate(keys, 1):
        c = claims[k]; did = f"R{rnd}-S-{i}"; f = DRAFTS / f"{today}_{did}.txt"
        if not f.exists(): continue
        body = f.read_text(encoding="utf-8"); bad = numbers_ok(body, [vn[c["number"]]] if c.get("number") else [])
        gate = subprocess.run(["bash", "scripts/x_ops/x_post_gate.sh", str(f.relative_to(ROOT)), "A"], capture_output=True, text=True, cwd=ROOT)
        illustrative = (not c.get("number")) and all(float(x) <= 100 for x in bad)
        status = "FAIL_num" if (bad and not illustrative) else ("FAIL_gate" if gate.returncode else "PASS")
        if status == "PASS" and approve:
            (DRAFTS / f"{today}_{did}.approved").write_text(f"auto claim_bank {k} {dt.datetime.now().isoformat(timespec='seconds')}\n")
        print(f"{did}\t{k}\t{status}\t{len(body.strip())}字\t{bad if bad else ''}")


REQ = ("belief", "claim", "why", "audience", "origin")
ORIGINS = ("human_seed", "existing_user_thesis", "dm_signal_result", "external_topic")


def origin_ok(c):
    """殿指示 2026-09-04 19:14: origin 必須。external_topic は ext_gate(A-E の記録)+context が無ければ SKIP。claim_bank を切り抜き工場にしない"""
    if c.get("origin") not in ORIGINS: return f"origin invalid={c.get('origin')}"
    if c["origin"] == "external_topic" and not (c.get("ext_gate") and c.get("context")): return "external_topic needs ext_gate+context"
    return ""
VOICE_RULE = "文体は本人(殿版 few-shot)からのみ。外部バズ投稿の語尾・煽り口調・キャラ・スラング・www・過激表現は使わない。借りてよいのは構造(対比・引用反証・VS・数字の置き方)だけ。"


def slot_text(fmt, c, num):
    ctx = f"\nなぜ今言うか(発話動機。本文に書かなくてよい): {c['context']}" if c.get("context") else ""
    num = num + ctx
    if fmt == "long":
        return (f"format=Long。全角 300〜600 字。構成は claim→疑い→検証→数字→結論。記事の要約にしない。全部説明せず conversation gap を残す。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n"
                f"壊す前提: {c['belief']}\n主張: {c['claim']}\n裏付け(1 行): {c['why']}\n刺さる読者: {c['audience']}\n{num}\n本文のみ出力。")
    return (f"format=Short。全角 140 字以内。1 つの主張だけ。全部説明しない。conversation gap を残す。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n"
            f"壊す前提: {c['belief']}\n主張: {c['claim']}\n理由(1 行): {c['why']}\n刺さる読者: {c['audience']}\n{num}\n本文のみ出力。")


def main():
    a = sys.argv[1:]
    if "--recheck" in a:
        rnd = a[a.index("--round") + 1]; keys = a[a.index("--claims") + 1].split(","); return recheck(rnd, keys, "--approve" in a)
    rnd = a[a.index("--round") + 1] if "--round" in a else "6"
    keys = a[a.index("--claims") + 1].split(",") if "--claims" in a else [c["key"] for c in BANK["claims"]]
    approve = "--approve" in a
    fmt = a[a.index("--format") + 1] if "--format" in a else "short"
    if fmt not in ("short", "long"):
        print("--format must be short|long", file=sys.stderr); sys.exit(2)
    tag = "S" if fmt == "short" else "L"
    today = dt.date.today().isoformat()
    vn = BANK["meta"]["verified_numbers"]
    claims = {c["key"]: c for c in BANK["claims"]}
    n = 0
    for i, k in enumerate(keys, 1):
        c = claims[k]
        missing = [r for r in REQ if not c.get(r)]
        if missing:
            print(f"R{rnd}-{tag}-{i}\t{k}\tSKIP_incomplete\tmissing={missing}", flush=True); continue
        bad_origin = origin_ok(c)
        if bad_origin:
            print(f"R{rnd}-{tag}-{i}\t{k}\tSKIP_origin\t{bad_origin}", flush=True); continue
        num = f"使ってよい数字(この 1 組だけ。使わなくてもよい): {vn[c['number']]}" if c.get("number") else "数字は使わない(使うなら禁止)。"
        user = f"{FEW}\n--- slot instruction ---\n{slot_text(fmt, c, num)}"
        body = llm(user)
        bad = numbers_ok(body, [vn[c["number"]]] if c.get("number") else [])
        did = f"R{rnd}-{tag}-{i}"
        f = DRAFTS / f"{today}_{did}.txt"
        f.write_text(body + "\n", encoding="utf-8")
        gate = subprocess.run(["bash", "scripts/x_ops/x_post_gate.sh", str(f.relative_to(ROOT)), "A"], capture_output=True, text=True, cwd=ROOT)
        fail = gate.returncode != 0
        # 数字: verified_numbers 以外は原則 FAIL。ただし claim に data number が無く、本文の数字が全て 100 以下の算数の例示(9 勝 1 敗=90% 等)は許容
        illustrative = (not c.get("number")) and all(float(x) <= 100 for x in bad)
        status = "FAIL_num" if (bad and not illustrative) else ("FAIL_gate" if fail else "PASS")
        if status == "PASS" and approve:
            (DRAFTS / f"{today}_{did}.approved").write_text(f"auto claim_bank {k} {dt.datetime.now().isoformat(timespec='seconds')}\n")
        print(f"{did}\t{k}\t{status}\t{len(body)}字\t{'unverified='+str(bad) if bad else ''}", flush=True)
        n += status == "PASS"
    print(f"done pass={n}/{len(keys)}")


if __name__ == "__main__":
    main()
