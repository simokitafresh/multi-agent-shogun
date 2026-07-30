#!/usr/bin/env python3
"""X Thread Fetch — X投稿URLからツリー全文+画像を1つの知識として取得する。

Usage:
    python3 scripts/x_thread_fetch.py --url "https://x.com/i/status/<ID>" [--no-grok]

Pipeline:
    1. URLからstatus IDを抽出
    2. 公開syndication APIで起点postの全文+author+画像を取得(認証不要)
    3. xAI Grok x_search(config/xai_api.env)でスレッド全postのIDを列挙
       (--no-grokまたはキー不在時は起点postのみ)
    4. 各post IDをsyndication APIで取得し、正確な全文+画像を回収(画像は?name=largeで原寸)
    5. data/x-research/thread_<ID>/ に thread.md / thread.json / images/ を保存

Notes:
    - 公開postのみ(鍵アカ・削除済みは不可)。
    - Grok列挙は取りこぼしうるため、番号prefix(1/,2/..)があれば連番検査をmdに記す。
    - WebFetchは使わない(haiku要約で原文が失われるため。全文記録→自分で読むが正)。
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_ROOT = REPO_ROOT / "data" / "x-research"
SYNDICATION = "https://cdn.syndication.twimg.com/tweet-result?id={tid}&token=x"
XAI_URL = "https://api.x.ai/v1/responses"
XAI_MODEL = "grok-4-1-fast-reasoning"
UA = {"User-Agent": "Mozilla/5.0"}


def http_json(url: str, timeout: int = 30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def extract_id(url: str) -> str:
    m = re.search(r"status/(\d+)", url)
    if not m:
        print(f"ERROR: status IDをURLから抽出できない: {url}", file=sys.stderr)
        sys.exit(1)
    return m.group(1)


def load_xai_key() -> str:
    env = REPO_ROOT / "config" / "xai_api.env"
    if os.environ.get("XAI_API_KEY"):
        return os.environ["XAI_API_KEY"]
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("XAI_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"')
    return ""


def grok_enumerate(root_id: str, screen_name: str, created_at: str, head: str, key: str):
    """Grok x_searchでスレッド全postのIDを列挙する。失敗時は空リスト。"""
    prompt = (
        "x_searchを使って、X上のこのスレッド(conversation)の全ポストを列挙せよ: "
        f"https://x.com/{screen_name}/status/{root_id} "
        f"(@{screen_name}の{created_at[:10]}のスレッド。冒頭: {head[:60]!r})。"
        "出力は各ポストにつき1行で『post_id | 冒頭30字』のみ。"
        "スレッド主の連続ポストを番号順に全て。見つかった分だけでよい。"
    )
    payload = json.dumps({
        "model": XAI_MODEL,
        "input": prompt,
        "tools": [{"type": "x_search"}],
    }).encode()
    req = urllib.request.Request(
        XAI_URL, data=payload,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            data = json.load(r)
    except Exception as e:
        print(f"WARN: Grok列挙失敗({e})。起点postのみ取得する", file=sys.stderr)
        return []
    text = ""
    for item in data.get("output", []):
        if isinstance(item, dict):
            for c in item.get("content", []):
                if c.get("type") == "output_text":
                    text += c.get("text", "")
    ids = re.findall(r"\b(\d{15,20})\b", text)
    seen, ordered = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i)
            ordered.append(i)
    return ordered


def fetch_post(tid: str):
    return http_json(SYNDICATION.format(tid=tid))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--no-grok", action="store_true", help="Grok列挙を使わず起点postのみ")
    args = ap.parse_args()

    root_id = extract_id(args.url)
    out_dir = OUT_ROOT / f"thread_{root_id}"
    (out_dir / "images").mkdir(parents=True, exist_ok=True)

    root = fetch_post(root_id)
    screen = root.get("user", {}).get("screen_name", "i")
    created = root.get("created_at", "")

    ids = [root_id]
    key = "" if args.no_grok else load_xai_key()
    if key:
        enum = grok_enumerate(root_id, screen, created, root.get("text", ""), key)
        if enum:
            if root_id not in enum:
                enum.insert(0, root_id)
            ids = enum
    elif not args.no_grok:
        print("WARN: XAI_API_KEY不在。起点postのみ取得する", file=sys.stderr)

    posts, img_count = [], 0
    for n, tid in enumerate(ids, 1):
        try:
            d = root if tid == root_id else fetch_post(tid)
        except Exception as e:
            posts.append({"n": n, "id": tid, "error": str(e)})
            continue
        photos = [p.get("url") for p in d.get("photos", [])]
        local_imgs = []
        for j, pu in enumerate(photos):
            dst = out_dir / "images" / f"{n:02d}_{j}.jpg"
            try:
                urllib.request.urlretrieve(pu + "?name=large", dst)
                img_count += 1
                local_imgs.append(str(dst.relative_to(out_dir)))
            except Exception:
                pass
        posts.append({
            "n": n, "id": tid, "text": d.get("text", ""),
            "user": d.get("user", {}).get("screen_name"),
            "created_at": d.get("created_at"),
            "photos": photos, "local_images": local_imgs,
        })
        time.sleep(0.5)

    json.dump(posts, open(out_dir / "thread.json", "w"), ensure_ascii=False, indent=1)

    ok = [p for p in posts if "text" in p]
    md = [f"# @{screen} thread (root {root_id}, {created[:10]})\n",
          f"source: {args.url}\n取得: syndication API + Grok x_search列挙 / posts {len(ok)}/{len(ids)} / images {img_count}\n"]
    nums = []
    for p in ok:
        m = re.match(r"(\d+)/", p["text"])
        if m:
            nums.append(int(m.group(1)))
        md.append(f"## {p['n']}/ (id {p['id']})\n\n{p['text']}\n")
        for li in p.get("local_images", []):
            md.append(f"- 画像: {li}\n")
    if nums:
        expected = list(range(min(nums), max(nums) + 1))
        gap = sorted(set(expected) - set(nums))
        md.append(f"\n---\n番号prefix検査: {min(nums)}..{max(nums)} 欠番={gap if gap else 'なし'}\n")
    (out_dir / "thread.md").write_text("\n".join(md))

    print(f"OK posts={len(ok)}/{len(ids)} images={img_count} out={out_dir}")
    if len(ok) < len(ids):
        print(f"WARN: {len(ids)-len(ok)}件取得失敗(非公開/削除の可能性)", file=sys.stderr)


if __name__ == "__main__":
    main()
