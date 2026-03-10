#!/usr/bin/env python3
"""
X Research Script — xAI Grok API経由でXリアルタイム検索しContext Packを生成。

Usage:
    python3 scripts/x_research.py --topic "AI agent" [--locale ja] [--audience engineer]

Output:
    data/x-research/{timestamp}_{topic_slug}.md
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests library required. Install: pip install requests", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / "config" / "xai_api.env"
OUTPUT_DIR = REPO_ROOT / "data" / "x-research"
API_URL = "https://api.x.ai/v1/responses"
MODEL = "grok-4-1-fast-reasoning"
TIMEOUT_SEC = 180


def load_api_key() -> str:
    """Load XAI_API_KEY from config/xai_api.env."""
    if not ENV_PATH.exists():
        print(f"ERROR: {ENV_PATH} not found.", file=sys.stderr)
        sys.exit(2)
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("XAI_API_KEY="):
            val = line.split("=", 1)[1].strip()
            if (val.startswith('"') and val.endswith('"')) or \
               (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            return val
    print("ERROR: XAI_API_KEY not found in config/xai_api.env", file=sys.stderr)
    sys.exit(2)


def build_system_prompt(locale: str, audience: str) -> str:
    """Build system prompt for Grok with x_search."""
    locale_line = (
        "検索・収集は日本語圏を優先（日本語で読める一次情報や日本語で拡散している情報）。"
        "必要なら英語一次情報も併用。"
        if locale == "ja"
        else "検索・収集はグローバル一次情報（英語中心）を優先。日本語圏の派生も拾ってよい。"
    )
    audience_map = {
        "engineer": "読者はエンジニア寄り。実装・運用・制約（レート/コスト/権限）を厚めに。",
        "investor": "読者は投資家寄り。評価軸（コスト/優位性/リスク/規約）を厚めに。ただし投資助言はしない。",
        "general": "読者は一般層。専門用語は平易に言い換え、背景から説明する。",
    }
    audience_line = audience_map.get(audience, audience_map["engineer"])

    return f"""あなたはリサーチアシスタントです。x_searchを活用してX(旧Twitter)の投稿をリアルタイム検索し、
構造化されたContext Pack（調査報告Markdown）を生成してください。

ルール:
- {locale_line}
- {audience_line}
- 数字/仕様/制限は捏造しない。不明は unknown と書く。
- 仕様/価格/レート等は変更され得るので「As of（参照日）」を付ける。
- 長文の直接引用はしない（要旨で）。
- 投資助言に見える表現は禁止（買い/売り推奨、価格目標、倍化など）。
- Primary Sourcesは公式ドキュメント/公式ブログ/仕様/規約/料金/公式GitHubなど、X投稿以外のURL。
  X投稿URLはSecondary Sourcesとしてのみ可。
- 出力に専用タグ（render_inline_citationなど）を入れない。URLは素のURLで書く。
- 日本語で回答すること。"""


def build_user_prompt(topic: str, locale: str, audience: str) -> str:
    """Build user prompt with the research request."""
    now_iso = datetime.now(timezone.utc).isoformat()
    return f"""トピック: {topic}
時点: {now_iso}
検索窓の目安: 直近30日（ただし仕様/規約/料金は最新を優先）

やること:
1) x_searchを使って一次情報（公式ドキュメント/仕様/規約/料金/公式ブログ/公式GitHub）を最優先で集める
2) X上の関連投稿を検索し、トレンドクラスター（空気を読む）を抽出する
3) 代表ポスト（バズ指標: likes/retweets/views付き）をピックアップする
4) 反論/注意点を最低1つ作る（例: レート制限、コスト爆発、偏り、ポリシー違反）
5) 記事が深くなる要素を最低2つ作る（用語定義、datedな数字、実装の最小構成など）

出力形式（Markdown、以下の見出しを必ず含める）:
## Meta
- Timestamp (UTC): {now_iso}
- Topic: {topic}
- Locale: {locale}
- Audience: {audience}

## Topic Summary（1-2文）
## Why Now（3 bullets）
## Trend Clusters（X上の空気。クラスター名+概要+代表ポスト）
## Key Posts（バズ指標付き: likes/retweets/views、投稿者名、URL）
## Primary Sources（公式URL）
## Secondary Sources（X投稿URL）
## Contrasts / Counterpoints（Evidence付き）
## Data Points（As of日付 + Source付き）
## What We Can Safely Say / What We Should Not Say
## Suggested Angles（3つ）
## Sources（URL一覧）
"""


def slugify(text: str, max_len: int = 40) -> str:
    """Convert topic text to a safe filename slug."""
    slug = re.sub(r'[^\w\s-]', '', text.lower())
    slug = re.sub(r'[\s_]+', '-', slug).strip('-')
    return slug[:max_len] if slug else "research"


def call_xai_api(api_key: str, topic: str, locale: str, audience: str) -> str:
    """Call xAI Responses API with x_search tool enabled."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    prompt = build_system_prompt(locale, audience) + "\n\n" + \
             build_user_prompt(topic, locale, audience)
    payload = {
        "model": MODEL,
        "input": prompt,
        "tools": [{"type": "x_search"}],
    }

    print(f"Calling xAI API (model={MODEL})...", file=sys.stderr)
    try:
        resp = requests.post(API_URL, headers=headers, json=payload, timeout=TIMEOUT_SEC)
        resp.raise_for_status()
    except requests.exceptions.Timeout:
        print(f"ERROR: API request timed out after {TIMEOUT_SEC}s", file=sys.stderr)
        sys.exit(1)
    except requests.exceptions.HTTPError:
        print(f"ERROR: API returned {resp.status_code}: {resp.text[:2000]}", file=sys.stderr)
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Request failed: {e}", file=sys.stderr)
        sys.exit(1)

    data = resp.json()

    # Extract content from Responses API format
    content = _extract_text(data)
    if not content:
        print(f"ERROR: No text in response: {json.dumps(data, indent=2)[:2000]}",
              file=sys.stderr)
        sys.exit(1)

    return content


def _extract_text(resp_data: dict) -> str:
    """Extract text from xAI Responses API output."""
    # Responses API: output is array of items with content arrays
    output = resp_data.get("output", [])
    if isinstance(output, list):
        parts = []
        for item in output:
            if not isinstance(item, dict):
                continue
            content = item.get("content", [])
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") in ("text", "output_text"):
                        text = c.get("text", "").strip()
                        if text:
                            parts.append(text)
            elif isinstance(content, str) and content.strip():
                parts.append(content.strip())
        if parts:
            return "\n".join(parts)

    # Fallback: check top-level text fields
    for key in ("output_text", "text", "content"):
        val = resp_data.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()

    return ""


def save_context_pack(content: str, topic: str, locale: str, audience: str) -> Path:
    """Save Context Pack markdown to data/x-research/."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y%m%d_%H%M%SZ")
    slug = slugify(topic)
    filename = f"{ts}_{slug}.md"

    header = f"""# Context Pack: {topic}

> Generated by x_research.py via xAI Grok API (x_search)
> Timestamp: {now.isoformat()}
> Locale: {locale} | Audience: {audience}

---

"""
    out_path = OUTPUT_DIR / filename
    out_path.write_text(header + content, encoding="utf-8")
    return out_path


def main():
    parser = argparse.ArgumentParser(
        description="X Research — xAI Grok API経由でXリアルタイム検索",
    )
    parser.add_argument("--topic", required=True, help="検索テーマ（必須）")
    parser.add_argument("--locale", default="ja", choices=["ja", "global"],
                        help="検索ロケール (default: ja)")
    parser.add_argument("--audience", default="engineer",
                        choices=["engineer", "investor", "general"],
                        help="ターゲット読者 (default: engineer)")
    parser.add_argument("--dry-run", action="store_true",
                        help="APIリクエストペイロードを表示して終了")
    args = parser.parse_args()

    api_key = load_api_key()

    if args.dry_run:
        prompt = build_system_prompt(args.locale, args.audience) + "\n\n" + \
                 build_user_prompt(args.topic, args.locale, args.audience)
        payload = {
            "model": MODEL,
            "input": prompt,
            "tools": [{"type": "x_search"}],
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return

    content = call_xai_api(api_key, args.topic, args.locale, args.audience)
    out_path = save_context_pack(content, args.topic, args.locale, args.audience)

    print(f"\nSaved: {out_path.relative_to(REPO_ROOT)}", file=sys.stderr)
    print(content)


if __name__ == "__main__":
    main()
