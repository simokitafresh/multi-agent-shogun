#!/usr/bin/env python3
"""投稿済み X post を削除する(殿裁定 2026-09-04 10:38: 免責付き第 1 弾を免責なしで再投稿するため)。
Usage: python3 scripts/x_ops/x_post_delete.py <post_id> [env_path]。secret は出力しない。"""
import sys
from pathlib import Path
post_id = sys.argv[1]
env = Path(sys.argv[2] if len(sys.argv) > 2 else "config/x_api.env")
v = {}
for l in env.read_text(encoding="utf-8").splitlines():
    if "=" in l and not l.lstrip().startswith("#"):
        k, x = l.split("=", 1); v[k.strip()] = x.strip().strip('"').strip("'")
from xdk import Client
c = Client(token={"access_token": v["X_ACCESS_TOKEN"], "refresh_token": v.get("X_REFRESH_TOKEN")},
           client_id=v.get("X_CLIENT_ID"), client_secret=v.get("X_CLIENT_SECRET"))
r = c.posts.delete(post_id)
print("deleted", post_id, getattr(r, "data", r))
