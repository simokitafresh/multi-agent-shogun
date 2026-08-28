---
name: x-research
quality_metric: "将軍系: X調査cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  xAI Grok APIのx_search機能でXリアルタイム検索し、トレンドクラスター・代表ポスト・
  一次情報URLを含むContext Pack Markdownを生成。将軍がトピック調査時に使用。
  TRIGGER: /x-research、X検索、Xリサーチ、トピック調査、トレンド調査
  DO NOT TRIGGER: 週報生成（→weekly-report、x_searchは週報の一部として内包）、
  note記事執筆（→note-article / sengoku-writer）、Web検索全般（本スキルはX特化）
argument-hint: "topic [--locale ja|global] [--audience engineer|investor|general]"
allowed-tools:
  - Bash
  - Read
  - Write
---

# X Research Skill

xAI Grok APIのx_search機能を使い、X(旧Twitter)のリアルタイム検索結果からContext Pack（構造化調査Markdown）を生成する。

## 使い方

```
/x-research "AI agent"
/x-research "Claude Code マルチエージェント" --locale ja --audience engineer
/x-research "OpenAI GPT-5" --locale global --audience investor
```

## 実行手順

1. 引数を解析する（第1引数=topic、オプション: --locale, --audience）
2. 以下のコマンドでスクリプトを実行:

```bash
python3 "$SHOGUN_ROOT/scripts/x_research.py" \
  --topic "<topic>" \
  --locale <ja|global> \
  --audience <engineer|investor|general>
```

3. 結果は `data/x-research/{timestamp}_{topic}.md` に保存される
4. 保存されたContext Packの内容を読み、ユーザーに主要な発見を要約して報告する

## オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| --topic | (必須) | 検索テーマ |
| --locale | ja | ja=日本語圏優先 / global=英語圏優先 |
| --audience | engineer | engineer/investor/general |
| --dry-run | - | APIペイロード表示のみ（APIコール無し） |

## 出力構造

Context Packは以下のセクションを含む:
- Topic Summary / Why Now
- Trend Clusters（X上の空気）
- Key Posts（バズ指標付き）
- Primary Sources（公式URL）/ Secondary Sources（X投稿URL）
- Contrasts / Counterpoints
- Data Points / Suggested Angles

## 制約

- APIキーは `config/xai_api.env` から読み込み（ハードコード禁止）
- 投資助言表現は出力に含めない
- 一次情報URLを優先する
