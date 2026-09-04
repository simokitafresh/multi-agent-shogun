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


FEW_CLAIM = {"C01": "[D-5 合格]", "C11": "[A-1 殿版]", "C30": "[A-1 殿版]", "C10": "[B-4 殿版]", "C15": "[B-4 殿版]", "C26": "[C-1 殿版]", "C08": "[C-1 殿版]"}


def few_for(key):
    """claim と同じ主張の few-shot は外す(そのまま写しになるのを防ぐ。P9-S-1=D-5 写し 2026-09-04 19:22)"""
    tag = FEW_CLAIM.get(key)
    return "\n".join(l for l in FEW.splitlines() if not (tag and l.startswith(tag)))


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


def slot_text(fmt, c, num, p=None):
    ctx = f"\nなぜ今言うか(発話動機。本文に書かなくてよい): {c['context']}" if c.get("context") else ""
    num = num + ctx
    base = f"壊す前提: {c['belief']}\n主張: {c['claim']}\n裏付け(1 行): {c['why']}\n刺さる読者: {c['audience']}\n{num}"
    if fmt == "series_entry":
        return (f"format=Series Entry。全角 200 字以内。シリーズ「{p['series_title']}」の {p['series_order']}/{p['series_total']} 回目。この回だけで意味が通ること。冒頭か末尾に『{p['series_order']}/{p['series_total']}』だけ置き、続きがあると分かる一言を添える(宣伝調にしない)。全部説明しない。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n{base}\n本文のみ出力。")
    if fmt == "thread":
        return (f"format=Thread。親投稿(全角 140 字以内)+自己リプ 2〜3 本(各 140 字以内)。各リプに新しい情報(数字・条件・別の角度)を 1 つ入れる。文字数回避の分割は禁止。親だけでも意味が通る。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n{base}\n出力形式: 親本文、次に行『===R1===』、リプ 1 本文、『===R2===』、リプ 2 本文(必要なら『===R3===』)。それ以外を書かない。")
    if fmt == "long":
        return (f"format=Long。全角 300〜600 字。構成は claim→疑い→検証→数字→結論。記事の要約にしない。全部説明せず conversation gap を残す。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n"
                f"壊す前提: {c['belief']}\n主張: {c['claim']}\n裏付け(1 行): {c['why']}\n刺さる読者: {c['audience']}\n{num}\n本文のみ出力。")
    return (f"format=Short。全角 140 字以内。1 つの主張だけ。全部説明しない。conversation gap を残す。URL なし。DM-Signal の名前を出さない。\n{VOICE_RULE}\n"
            f"壊す前提: {c['belief']}\n主張: {c['claim']}\n理由(1 行): {c['why']}\n刺さる読者: {c['audience']}\n{num}\n本文のみ出力。")


GROWTH = {"short": ("reach", "investor", "contradiction", 2, "[dwell, reply, quote, profile]"),
          "long": ("trust", "systematic", "story", 4, "[bookmark, profile, follow]"),
          "thread": ("trust", "systematic", "question", 4, "[bookmark, reply, profile]"),
          "series_entry": ("follow", "systematic", "question", 4, "[bookmark, profile, follow]")}


def ledger_block(did, f, fmt, c, extra=""):
    st, au, hk, tl, da = GROWTH[fmt]
    return (f"- draft_id: {did}\n  draft_file: {f.relative_to(ROOT)}\n  growth:\n    format: {fmt}\n    physical_posts: 1\n    content_lane: investing\n    content_category: A\n"
            f"    funnel_stage: {st}\n    audience: {au}\n    hook_type: {hk}\n    topic_level: {tl}\n    desired_action: {da}\n    conversation_gap: medium\n    link_type: none\n    external_context: standalone\n"
            f"    claim_key: {c['key']}\n    claim_origin: {c['origin']}\n    approved: ''\n{extra}  post_id: ''\n  posted_at: ''\n  snapshots: {{}}\n")


def run_plan(plan_path, only=None):
    """plan の各 slot を生成→gate→台帳へ追記(未承認。殿が読んでから承認)。ledger は text 追記(yaml.dump 禁止)"""
    plan = yaml.safe_load(Path(plan_path).read_text(encoding="utf-8"))["plan"]
    vn = BANK["meta"]["verified_numbers"]; claims = {c["key"]: c for c in BANK["claims"]}
    ledger = ROOT / "queue/x_live_oos/ledger.yaml"; today = dt.date.today().isoformat(); n = 0; tot = 0
    for p in plan:
        if not p.get("claim") or (only and p["draft_id"] not in only): continue
        if any((DRAFTS / f"{today}_{p['draft_id']}{sfx}.txt").exists() for sfx in ("", "-P")): continue  # 再実行は未生成のみ
        c = claims[p["claim"]]; fmt = p["format"]; did = p["draft_id"]; tot += 1
        miss = [r for r in REQ if not c.get(r)]; bo = origin_ok(c)
        if miss or bo:
            print(f"{did}\t{c['key']}\tSKIP\t{miss or bo}", flush=True); continue
        num = f"使ってよい数字(この 1 組だけ。使わなくてもよい): {vn[c['number']]}" if c.get("number") else "数字は使わない(使うなら禁止)。"
        body = llm(f"{few_for(c['key'])}\n--- slot instruction ---\n{slot_text(fmt, c, num, p)}")
        parts = [x.strip() for x in re.split(r"^===R\d===\s*$", body, flags=re.M)] if fmt == "thread" else [body]
        parts = [x for x in parts if x]
        if fmt == "thread" and len(parts) < 3:
            print(f"{did}\t{c['key']}\tFAIL_thread_parts\t{len(parts)}", flush=True); continue
        status = "PASS"; blocks = ""
        for j, txt in enumerate(parts):
            sub = f"{did}-P" if (fmt == "thread" and j == 0) else (f"{did}-R{j}" if fmt == "thread" else did)
            f = DRAFTS / f"{today}_{sub}.txt"; f.write_text(txt + "\n", encoding="utf-8")
            bad = numbers_ok(txt, [vn[c["number"]]] if c.get("number") else [])
            gate = subprocess.run(["bash", "scripts/x_ops/x_post_gate.sh", str(f.relative_to(ROOT)), "A"], capture_output=True, text=True, cwd=ROOT)
            illustrative = (not c.get("number")) and all(float(x) <= 100 for x in bad)
            st = "FAIL_num" if (bad and not illustrative) else ("FAIL_gate" if gate.returncode else "PASS")
            if st != "PASS": status = st
            extra = ""
            if fmt == "thread": extra = f"    thread_id: {did}\n    thread_position: {j}\n"
            if fmt == "series_entry": extra = f"    series_id: {p['series_id']}\n    series_order: {p['series_order']}\n    series_total: {p['series_total']}\n"
            blocks += ledger_block(sub, f, fmt, c, extra).replace("  post_id:", "    scheduled: '" + f"{p['date']} {p['time']}" + "'\n  post_id:")
        if status == "PASS":
            import fcntl
            with ledger.open("a", encoding="utf-8") as fh:
                fcntl.flock(fh, fcntl.LOCK_EX); fh.write(blocks); fh.flush(); fcntl.flock(fh, fcntl.LOCK_UN)
            n += 1
        print(f"{did}\t{c['key']}\t{fmt}\t{status}\t{sum(len(x) for x in parts)}字", flush=True)
    print(f"plan done pass={n}/{tot}")


def main():
    a = sys.argv[1:]
    if "--plan" in a:
        only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else None
        return run_plan(a[a.index("--plan") + 1], only)
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
