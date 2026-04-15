# CoDD (Coherence-Driven Development) 索引

> 詳細原典: `memory/reference_codd_oshio_articles.md`
> 実戦教訓: `memory/tool_codd_lessons.md`
> 将軍システム適用分析: `context/gunshi-codd-analysis.md`

## §1 概要

| 項目 | 結論 |
|------|------|
| 作者 | おしお殿 (`@shio_shoppaize`) / Harness as Code |
| GitHub | `https://github.com/yohey-w/codd-dev` |
| ローカル実体 | `/home/simokitafresh/.codd-venv/bin/codd` |
| 版数 | `codd --version` = `1.8.0` |
| 位置づけ | CoDDは「設計書を先に整合させ、下流を導出する」ためのパイプライン。設定を増やすのでなく、依存関係とハーネスで整合性を強制する |

## §2 コマンド体系 (v1.8.0)

| 系統 | コマンド列 | 結論 |
|------|------------|------|
| グリーンフィールド | `init -> plan -> generate -> validate -> implement -> assemble` | 要件から設計書群を順生成し、整合性を崩さず実装まで進める |
| ブラウンフィールド | `extract -> require -> plan -> restore -> scan -> impact -> audit -> measure` | 既存コードから構造を抽出し、差分影響と健全性を測りながら設計を復元する |
| 変更伝播 | `scan -> impact -> propagate --update` | 変更点から波及先を導出し、更新対象を手で列挙せず伝播させる |
| 品質 | `validate`, `review --feedback`, `verify`, `policy`, `audit` | 設計整合性・レビュー・検証・方針遵守を段階別に確認する |
| 修正 | `fix` | v1.8.0の核。診断推論で失敗理由を言語化し、Session Stateで再試行履歴を引き継ぐ |
| 連携 | `mcp-server` | stdio JSON-RPCで外部エージェントや道具からCoDD機能を呼び出せる |
| 健全性 | `measure` | CoDD運用を0-100で採点し、構造の劣化を数値で監視する |

## §3 核心原理 (記事#1-#5)

| 原理 | 結論 | 参照 |
|------|------|------|
| Derive, Don't Configure | 下流設定を手で並べるな。上流の事実から下流を導出せよ | `memory/reference_codd_oshio_articles.md` |
| Wave順生成 | 依存チェーン順に生成することで、設計整合性を後付けレビューでなく生成順そのもので強制する | `memory/reference_codd_oshio_articles.md` |
| コンテキスト断捨離 (#3) | 情報を渡しすぎると退化する。`extract` のような構文解析ベースの粒度が最も安定 | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| Harness Engineering (#4) | 事前説明より事後フィードバックが効く。失敗時はDIVERGENTで仮説転換を強制する | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| 診断推論 (#5) | 情報注入より思考構造の強制が効く。先に根本原因を書かせ、Session Stateで学習を持ち越す | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| 3層モデル | L1=事前設計書、L2=事後フィードバック+リトライ、L3=診断推論+記憶。3層が揃って初めて退化しにくい | `docs/research/gunshi_codd_swebench_application_20260416.md` |

## §4 将軍システムとの対応

| CoDD | 我が軍 | 結論 |
|------|--------|------|
| `extract` | `context/*.md` | どちらも現物から索引層を起こし、必要な文脈だけを読むための圧縮レイヤ |
| テストFB + DIVERGENT | gate BLOCK -> 教訓 -> 再挑戦 | 失敗を次の行動に変換する事後ハーネスという点で同型 |
| 診断推論 | なぜなぜ7回 / deepdive | 直す前に原因を言語化して前提を疑う構造が対応する |
| Session State | lessons / deepdive / task履歴 | `/clear` や再配備を跨いで学びを保持する受動的記憶として機能する |
| Harness as Code | 自動化×強制 | 人間依存の注意でなく、環境とフローに正しい動きを埋め込む思想が一致する |

## §5 我が軍での使い方

| 使い方 | 結論 | 参照 |
|--------|------|------|
| `/codd` | 設計書パイプライン専用。specからWave設計書群を起こす | `~/.claude/skills/codd/SKILL.md` |
| `/codd-refactor` | 計測 -> spec -> CoDD -> 実装 -> 再計測の一連を回す | `~/.claude/skills/codd-refactor/SKILL.md` |
| `codd fix` | CI REDや設計破綻の修正向け。診断推論+Session Stateがv1.8.0の差分 | `docs/research/gunshi_codd_swebench_application_20260416.md` §2, §4-§5 |
| `propagate` | `scan/impact` と組み合わせ、変更波及先の更新漏れを潰す | `memory/reference_codd_oshio_articles.md` |
| `review` / `verify` / `policy` / `audit` | 品質確認を単発でなく層として回す。レビュー、整合性、方針、監査を分離する | `memory/reference_codd_oshio_articles.md` |
| `measure` | 健全性を数値で監視し、リファクタや運用劣化を感覚でなくスコアで検知する | `memory/reference_codd_oshio_articles.md` |
| `ai_command` | `codd.yaml` で generate=Opus, implement=Codex など役割別に使い分け可能 | `~/.claude/skills/codd/SKILL.md` |

## §6 参照

- 記事#0-#5: `memory/reference_codd_oshio_articles.md`
- 実戦教訓: `memory/tool_codd_lessons.md`
- 軍師分析(索引): `context/gunshi-codd-analysis.md`
- 軍師分析(全文): `docs/research/gunshi_codd_swebench_application_20260416.md`
- リファクタ台帳: `docs/research/codd_refactor_registry.md`
- 既存設計書群: `docs/test/*.md` `docs/governance/*.md` `docs/design/*.md` `docs/detailed_design/*.md` `docs/plan/*.md` `docs/operations/*.md`
