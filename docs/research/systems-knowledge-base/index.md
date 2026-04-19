# AI開発知識辞書 — 総索引

> 外部 AI 開発システムと参考情報源を、一次知識層と解釈層に分けて辿れるようにした索引。`systems/` と `sources/` は原典ベース、`our-army/` は取込履歴を保持する。

## 構造

```text
systems-knowledge-base/
├── index.md              ← 本ファイル
├── guide.md              ← 拡充ガイドライン
├── systems/              ← 一次知識層: 外部システム + 我が軍エントリ
├── sources/              ← 一次知識層: 記事・知見源
└── our-army/             ← 解釈層: 我が軍への取込履歴
```

## 2層構造

- 一次知識層: `systems/` と `sources/`。原典由来の事実のみを置く
- 解釈層: `our-army/`。我が軍への取込履歴や読み替えを分離する

## Systems (8 entries)

| ID | システム名 | 1行概要 | ファイル |
|----|-----------|---------|---------|
| S01 | ACE Framework | 6層認知アーキテクチャと Northbound/Southbound bus を持つ概念フレームワーク | [`systems/ace.md`](systems/ace.md) |
| S02 | Claude Code / Agent SDK / Agent Teams | Anthropic 公式の CLI / SDK / マルチエージェント基盤 | [`systems/claude-code.md`](systems/claude-code.md) |
| S03 | GSD (Get Shit Done) | Context Rot を主問題と捉え、spec-first と verify を統合するエージェントシステム | [`systems/gsd.md`](systems/gsd.md) |
| S04 | gstack | 認知モード切替とスキル群でソフトウェアファクトリー化する OSS | [`systems/gstack.md`](systems/gstack.md) |
| S05 | Karpathy LLMコーディング4原則 | Think Before Coding など 4原則を整理したガイドライン | [`systems/karpathy-principles.md`](systems/karpathy-principles.md) |
| S06 | おしお殿 (multi-agent-shogun) | OSS 公開された将軍型マルチエージェントシステム | [`systems/oshio.md`](systems/oshio.md) |
| S07 | Vercel Context Engineering | 受動的知識配置と agent-friendly docs を中核にした運用基盤 | [`systems/vercel.md`](systems/vercel.md) |
| S08 | 我が軍 (current fork) | YAML 一次データ、学習ループ、GATE、復帰手順を統合した現行運用系 | [`systems/our-army.md`](systems/our-army.md) |

## Sources (1 entry)

| ID | 情報源 | 1行概要 | ファイル |
|----|--------|---------|---------|
| SRC01 | 逆瀬川ちゃん (@gyakuse) | Coding Agent のワークフロー、Harness Engineering、Skill 設計を扱う日本語一次資料群 | [`sources/gyakusegawa.md`](sources/gyakusegawa.md) |

## Interpretation Layer

| ID | 内容 | ファイル |
|----|------|---------|
| I01 | 我が軍が外部知見をいつ・どこから・何として取り込んだかの時系列ログ | [`our-army/adoption-log.md`](our-army/adoption-log.md) |
