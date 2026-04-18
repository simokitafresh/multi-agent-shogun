# CoDD (Coherence-Driven Development) 索引

<!-- last_updated: 2026-04-18 -->
<!-- staleness_triggers: codd --version変更時, GP-199/201実装時, /codd-refactorスキル更新時 -->
<!-- verify: ローカル版数/公開repo観測版数/§4 GP-198/200/201記述が最新か -->

> 詳細原典: `memory/reference_codd_oshio_articles.md`
> 実戦教訓: `memory/tool_codd_lessons.md`
> 将軍システム適用分析: `context/gunshi-codd-analysis.md`

## §1 概要

| 項目 | 結論 |
|------|------|
| 作者 | おしお殿 (`@shio_shoppaize`) / Harness as Code |
| GitHub | `https://github.com/yohey-w/codd-dev` |
| ローカル実体 | `/home/simokitafresh/.codd-venv/bin/codd` |
| 版数 | ローカルCLI=`1.8.0`。公開repo観測=`1.9.3` (2026-04-18時点、`cmd_2067` 調査) |
| 位置づけ | CoDDは「設計書を先に整合させ、下流を導出する」ためのパイプライン。設定を増やすのでなく、依存関係とハーネスで整合性を強制する |

## §2 コマンド体系

| 系統 | コマンド列 | 結論 |
|------|------------|------|
| グリーンフィールド | `init -> plan -> generate -> validate -> implement -> assemble` | 要件から設計書群を順生成し、整合性を崩さず実装まで進める |
| ブラウンフィールド | `extract -> require -> plan -> restore -> scan -> impact -> audit -> measure` | 既存コードから構造を抽出し、差分影響と健全性を測りながら設計を復元する |
| 変更伝播 | `scan -> impact -> propagate --update` | 変更点から波及先を導出し、更新対象を手で列挙せず伝播させる |
| 品質 | `validate`, `review --feedback`, `verify`, `policy`, `audit` | 設計整合性・レビュー・検証・方針遵守を段階別に確認する |
| 修正 | `fix` | v1.8.0で Diagnose MANDATORY + Session State を導入。retry前に根本原因を書かせ、失敗履歴を引き継ぐ |
| 連携 | `mcp-server` | stdio JSON-RPCで外部エージェントや道具からCoDD機能を呼び出せる |
| 健全性 | `measure` | CoDD運用を0-100で採点し、構造の劣化を数値で監視する |

### 公開差分メモ (2026-04-18確認)

| 版/commit | 差分 | 我が軍への示唆 |
|-----------|------|----------------|
| v1.8.0 / `5b15da5` | `codd/fixer.py` に Diagnose MANDATORY + `_SessionState` を実装 | GP-198/200/201 の原典。retryを stateful にする発想の核 |
| v1.8.1 / `e56b026` | sprint 前提を撤去し、`implement` を flat task-based generation に簡素化 | prompt/parser の暗黙前提を減らす方向が正しい |
| v1.9.3 / `b27b6c4` | failed task summary を downstream prompt から除外 | failure-context contamination guard を我が軍の注入系へ横展開すべし |

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
| テストFB + DIVERGENT | gate BLOCK + gate_diagnose_check.sh(GP-200) | 失敗を次の行動に変換する事後ハーネス。同一理由2回連続→仮説転換強制 |
| 診断推論 | なぜなぜ7回 + gate_diagnose_check.sh(GP-198) | 将軍=deepdive、忍者=BLOCK時diagnose_reason必須。全層で根本原因を先に言語化 |
| Session State | `session_state` / `previous_failures` / `codd_failure_history` | GP-198/201で実装済み。FAIL時にtask YAMLへ記録し、再配備時に失敗履歴ヒントとして再注入する。ただし本家比で diagnosis/approach/result の粒度はまだ粗い |
| Harness as Code | 自動化×強制 | 人間依存の注意でなく、環境とフローに正しい動きを埋め込む思想が一致する |

### 3層モデル対応(§3補足)

| 層 | CoDD | 我が軍 | 有効率/GAP |
|----|------|--------|-----------|
| L1 事前 | codd extract設計書 | related_lessons + context_files | 有用率26%→3件絞込み実装済み(GP-199 CLEAR) |
| L2 事後 | テストFB + DIVERGENT | gate BLOCK + FIX hints + DIVERGENT(GP-200 CLEAR) | workaround率0%(直近10件) |
| L3 診断 | Diagnose MANDATORY + Session State | diagnose_reason必須(GP-198 CLEAR) + Session State(GP-201 CLEAR) + deepdive | 全層実装完了。初回実証済み(疾風cmd_1936) |

## §4.5 CoDD改善cmdのAC設計ルール（cmd_1953事故→殿裁定2026-04-16）

**ACは4段階に分解せよ。** command欄に「/codd-refactorの手順で」と書いてもACに分解しなければ忍者は実行しない。

| AC | 内容 |
|----|------|
| AC-spec | CoDD spec作成(`docs/research/`に保存)。Phase 1実測値+ボトルネック+リファクタ対象 |
| AC-design | coddコマンドで設計書生成。設計書パスを報告に記載 |
| AC-impl | 設計書に基づき実装+before/after計測 |
| AC-test | 既存テスト全PASS+`codd_refactor_registry.md`に追記 |

**適用判断(LS036):** 各ステップの目的と作業の性質を照合せよ。選択肢が複数→spec先行(選択過程の記録)。選択肢が自明(サブシェル→awk等)→after設計書に理由を含めれば十分。全ステップの機械的適用は怠慢。

**防御層:** cmd_save.sh Check 22(ステップ数 vs AC数の粗い網) + 軍師レビュー(事後) + Session State(診断)。事前100%は不可能かつ怠慢(LS035)。

## §5 我が軍での使い方

| 使い方 | 結論 | 参照 |
|--------|------|------|
| `/codd` | 設計書パイプライン専用。specからWave設計書群を起こす | `~/.claude/skills/codd/SKILL.md` |
| `/codd-refactor` | 計測 -> spec -> CoDD -> 実装 -> 再計測の一連を回す | `~/.claude/skills/codd-refactor/SKILL.md` |
| `codd fix` | CI RED修正向け。診断推論+Session State。家老CI RED検知→`codd fix`でパッチ生成→忍者配備。スキル非対応のため直接CLI実行 | `docs/research/gunshi_codd_swebench_application_20260416.md` §2, §4-§5 |
| `propagate` | `scan/impact` と組み合わせ、変更波及先の更新漏れを潰す | `memory/reference_codd_oshio_articles.md` |
| `review` / `verify` / `policy` / `audit` | 品質確認を単発でなく層として回す。レビュー、整合性、方針、監査を分離する | `memory/reference_codd_oshio_articles.md` |
| `measure` | 健全性を数値で監視し、リファクタや運用劣化を感覚でなくスコアで検知する | `memory/reference_codd_oshio_articles.md` |
| `ai_command` | `codd.yaml` で generate=Opus, implement=Codex など役割別に使い分け可能 | `~/.claude/skills/codd/SKILL.md` |

## §6 参照

- 記事#0-#5: `memory/reference_codd_oshio_articles.md`
- `cmd_2067` 深掘り: `docs/research/cmd_2067_codd5_deep_analysis.md`
- 実戦教訓: `memory/tool_codd_lessons.md`
- 軍師分析(索引): `context/gunshi-codd-analysis.md`
- 軍師分析(全文): `docs/research/gunshi_codd_swebench_application_20260416.md`
- リファクタ台帳: `docs/research/codd_refactor_registry.md`
- 既存設計書群: `docs/test/*.md` `docs/governance/*.md` `docs/design/*.md` `docs/detailed_design/*.md` `docs/plan/*.md` `docs/operations/*.md`
