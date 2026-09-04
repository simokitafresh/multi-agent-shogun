#!/usr/bin/env python3
"""Round5 生成(将軍 D0 2026-09-04 16:45、SHOGUN_ROOT/SCRATCH env 必須。再現用に保存): lane 別 Short 10 + Long 3 + Thread 2(親+3) + Series 8。system_prompt_v5_1 + 殿版 few-shot + 本人 note 実例(第 3 マガジン)。
出力: docs/research/x_post_drafts_round5_20260904.md(殿添削用)+ queue/x_drafts/2026-09-04_R5-*.txt(未承認)。
"""
import os, re, subprocess, sys, json, time
from pathlib import Path
ROOT = Path(os.environ["SHOGUN_ROOT"])
SP = (ROOT / "skills/x-post-pipeline/system_prompt_v5_1.txt").read_text(encoding="utf-8")
N3 = ROOT / "docs/research/x_corpus/note/m8357970d6430"
OUT_MD = ROOT / "docs/research/x_post_drafts_round5_20260904.md"
DRAFTS = ROOT / "queue/x_drafts"
FEW = """=== 殿版(合格)の実例。この書き方に合わせる ===
[A-1] 「S&P500に毎月積立、淡々と続けるだけ」。まあ正しいよね。／ただ平均を狙っても、格差は縮まらない。1千万と1億の差は30年後は拡大する。勝ち組だけが勝つのが平均狙い。／追いつくなら市場平均を上回るしかない。そういうハナシ。
[C-1] 「年率90%のバックテストです」と言われたら？／驚いたり疑ったり喜んだりする前にやることがある。／β調整後リターンをWFで分析しろ。／それでもαが残るか。／これでふるい落とされるような投資戦略はもろい。
[B-3] 1974〜2023年、GEM（本家デュアルモメンタム）の年率14.5%、S&P500は10.8%。差は3.7ポイント。／MaxDDはGEM -22.7%、S&P500 -50.9%。／デュアルモメンタムの本質は大勝ちじゃない。ディフェンス重視。だから長期投資でデュアルモメンタムは輝くんよ
[A-4] 「複利で増える」。まあ半分は正しい。／資産に同じ比率のリスクを取り続けるってことは、額で見たリスクも同じ倍率で増えてるってこと。資産10倍の年は、同じ下落率でも下落額が10倍。／率は変わらないけど、額は変わる。ここを飛ばして複利を語る人が多いんよ。
(／=空行)
"""

def note(key, n=1400):
    t = (N3 / f"{key}.md").read_text(encoding="utf-8").split("-->", 1)[-1].strip()
    return t[:n]

FORMAT_RULES = {
    "short": "format=Short。全角 140 字以内。違和感・数字・主張を 1 つだけ。全部説明しない。conversation gap を残す。数字は記事にある 1〜2 組のみ。",
    "long": "format=Long。全角 300〜600 字。X 内で『疑い→検証(何を固定し何を変えたか)→数字→短い解釈→次の疑い』を体験させる。note より浅く Short より深い。段落は空行。締めは口語で軽く。数字は記事にあるものだけ。",
    "thread_parent": "format=Thread の親。全角 100 字以内。核の主張か疑問だけ置く(『僕ならまず疑う』型)。続きは自己リプで掘る前提なので条件を書かない。",
    "thread_reply": "format=Thread の自己リプ {k}/3。全角 120 字以内。前の段と別の新しい疑問・数字・検証を 1 つ置く。単独でも意味が通る。①②③の番号で開いてよい。",
    "series": "format=Series Entry。全角 140 字以内。シリーズ『僕が投資システムを信用するまで』の {k}/9。冒頭に『僕が投資システムを信用するまで {k}/9』の 1 行。今回のテーマだけを単独で完結させ、過去回の前提を要求しない。締めは口語。",
}

ITEMS = []
# Short 10(lane 別 Reach)。source は第 3 マガジン
short_specs = [
    ("R5-S-1", "A", "real_estate_mortgage", "n6ae69b4a1947", "世帯年収2000万で1.4億タワマン。金利0.8%→上がると返済額はどうなるか。年収ではなくキャッシュフローで見る", "money"),
    ("R5-S-2", "A", "real_estate_mortgage", "n9ab9e12adee4", "表面利回り8%。表面の数字と手残りは別。バックテストの年率も同じ", "contradiction"),
    ("R5-S-3", "A", "real_estate_mortgage", "n48651b71f146", "相続税対策のアパート。金利は返済額だけでなく次の買い手が出せる値段まで下げる", "story"),
    ("R5-S-4", "D", "medical_economics", "n938cc77f66bb", "医者の給料は名目固定。インフレ3%が10年続くと現金の価値は74%。平均への収束はゆっくり貧乏", "money"),
    ("R5-S-5", "A", "medical_economics", "n1d77aaf8e3ef", "大学病院の給与は安いのか。均衡点は年収800万。肩書きではなく構造", "irony"),
    ("R5-S-6", "A", "medical_economics", "n6ae69b4a1947", "高年収でも資産が増えない。フローとストックは別。年収≠資産", "money"),
    ("R5-S-7", "D", "business_cash", "na68b0cd82b9c", "黒字なのに金がない。元本返済は経費にならない。税引後利益2000万で元本返済1500万なら手元500万", "math"),
    ("R5-S-8", "D", "business_cash", "na68b0cd82b9c", "売上より利益、利益よりキャッシュ。真水のキャッシュを直視しろ", "contradiction"),
    ("R5-S-9", "A", "money_inequality", "n10271fbb6967", "総資産10億の大家。内訳は物件10億・借金9億・自己資本1億。金利2.5%の世界で何が起きるか", "scenario"),
    ("R5-S-10", "A", "money_inequality", "n1d77aaf8e3ef", "『勝率90%なら良い戦略』ではない。1回の負けの大きさで決まる。期待値=勝率×平均利益−敗率×平均損失", "math"),
]
for did, cat, lane, key, shift, hook in short_specs:
    ITEMS.append(dict(draft_id=did, cat=cat, lane=lane, fmt="short", key=key, shift=shift, hook=hook, stage="reach"))
# Long 3(trust)
long_specs = [
    ("R5-L-1", "C", "investing", "n9ab9e12adee4", "表面利回り8%の手残り計算と、バックテスト年率のβ調整後・OOS・MaxDD を同じ構造で疑う。数字は記事の 5000万/400万/4.0%/表面8% と、GEM 1974-2023 CAGR14.5%/MaxDD-22.7%、S&P500 10.8%/-50.9% のみ"),
    ("R5-L-2", "E", "investing", "n48651b71f146", "相続アパートの NOI 864→780→700万と金利 1.5→2.5→3.5→4.5→5% の再計算を、投資システムの『前提が変わったら降りるルール(絶対モメンタム)』へ橋渡し。数字は記事のものだけ"),
    ("R5-L-3", "D", "business_cash", "na68b0cd82b9c", "粗利→営業利益→税引後利益→元本返済→設備投資→真水のキャッシュ。平均値ではなく経路を見る=幾何平均とドローダウンと同じ構造。数字は記事の 2000万/1500万/500万 のみ"),
]
for did, cat, lane, key, shift in long_specs:
    ITEMS.append(dict(draft_id=did, cat=cat, lane=lane, fmt="long", key=key, shift=shift, hook="story", stage="trust"))
# Thread 2(親+3)
thread_specs = [
    ("R5-T-1", "C", "investing", None, "年率100%のバックテスト。僕ならまず疑う。①βを引く ②OOSを見る ③パラメータを全部振る"),
    ("R5-T-2", "A", "real_estate_mortgage", "n10271fbb6967", "政策金利2.5%の世界。フルレバ大家に何が起きるか。①返済額 ②物件価格(買い手の利回り要求) ③銀行の態度。数字は記事の 10億/9億/1億 のみ"),
]
for did, cat, lane, key, shift in thread_specs:
    ITEMS.append(dict(draft_id=did, cat=cat, lane=lane, fmt="thread", key=key, shift=shift, hook="question", stage="trust"))
# Series 2..9
series_titles = {2: "OOS を見る", 3: "Walk Forward", 4: "パラメータを全部振る", 5: "計算日をずらす", 6: "執行日をずらす", 7: "二次元でずらす(計算日×執行日)", 8: "論文を自分のデータで再検証する", 9: "不採用結果を見る"}
for k, t in series_titles.items():
    ITEMS.append(dict(draft_id=f"R5-SE-{k}", cat="C", lane="investing", fmt="series", key=None, shift=t, hook="question", stage="follow", k=k))


def llm(system, user):
    env = dict(os.environ)
    r = subprocess.run(["claude", "--print", "--setting-sources", "user", "--system-prompt", system, user],
                       cwd=os.environ.get("SCRATCH", "/tmp"), capture_output=True, text=True, timeout=240, env=env)
    return r.stdout.strip()


def gen(item, k=None, prev=None):
    fr = FORMAT_RULES[item["fmt"] if item["fmt"] != "thread" else ("thread_parent" if k is None else "thread_reply")]
    if item["fmt"] == "series":
        fr = FORMAT_RULES["series"].format(k=item["k"])
    fr = fr.format(k=k) if "{k}" in fr else fr
    src = f"=== 本人 note 実例(第 3 マガジン。Voice と数字の出典。要約するな。型だけ取れ) ===\n{note(item['key'])}\n" if item.get("key") else ""
    prev_txt = f"=== 同じ Thread の前の段 ===\n{prev}\n" if prev else ""
    user = f"{FEW}\n{src}{prev_txt}--- slot instruction ---\nslot: {item['cat']}\ncontent_lane: {item['lane']}\nfunnel_stage: {item['stage']}\nhook_type: {item['hook']}\n{fr}\nshift: {item['shift']}\n数字は上の実例にある値だけ。URL を書かない。DM-Signal の名前を出さない(slot C/E/D/A)。本文のみ出力。"
    out = llm(SP, user)
    out = re.sub(r"^\s*(---|#+).*$", "", out, flags=re.M).strip()
    return out


def main():
    DRAFTS.mkdir(exist_ok=True)
    md = ["<!-- Round5 2026-09-04 16:45 将軍生成。lane 別 Short 10 / Long 3 / Thread 2(親+3) / Series 8。殿の添削待ち -->",
          "# X 投稿 下書き 第 5 稿(Growth v1.4: lane 別 Reach Short・Long・Thread・Series)— 殿の直し待ち", "",
          "作成: 2026-09-04 16:45。system_prompt v5.1+v5.2、few-shot=殿版 4 本、source=第 3 マガジン本文。数字は記事の値のみ。★は殿の直し用の印。", "", "---", ""]
    for item in ITEMS:
        did = item["draft_id"]
        if item["fmt"] == "thread":
            parent = gen(item)
            replies = []
            prev = parent
            for r in (1, 2, 3):
                rep = gen(item, k=r, prev=prev)
                replies.append(rep); prev = prev + "\n\n" + rep
            (DRAFTS / f"2026-09-04_{did}-P.txt").write_text(parent + "\n", encoding="utf-8")
            for r, rep in enumerate(replies, 1):
                (DRAFTS / f"2026-09-04_{did}-R{r}.txt").write_text(rep + "\n", encoding="utf-8")
            md += [f"## {did} Thread({item['cat']}/{item['lane']}) — {item['shift'][:40]}", "", f"★{did}-P(親)", parent, ""]
            for r, rep in enumerate(replies, 1):
                md += [f"★{did}-R{r}", rep, ""]
        else:
            body = gen(item)
            (DRAFTS / f"2026-09-04_{did}.txt").write_text(body + "\n", encoding="utf-8")
            label = {"short": "Short", "long": "Long", "series": "Series"}[item["fmt"]]
            md += [f"## {did} {label}({item['cat']}/{item['lane']}/{item['stage']}) — {item['shift'][:50]}", "", f"★{did}", body, "",
                   f"source_note: {item.get('key') or 'なし(検証テーマ)'}", ""]
        print(did, "ok", flush=True)
        time.sleep(1)
    OUT_MD.write_text("\n".join(md) + "\n", encoding="utf-8")
    print("done", len(ITEMS))


if __name__ == "__main__":
    main()
