# CoDD (Coherence-Driven Development)

> おしお殿 (@shio_shoppaize / yohey-w) が開発したAI開発向け設計書パイプラインツール。Prompt → Context → Harness の3層を整合性(cohesion)で結びつけ、設計書が腐らないコードベースを実現する。SWE-bench 73問 100%達成。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | shio_shoppaize (GitHub: yohey-w) |
| Status | OSS 本番稼働中 (活発に進化中) |
| PyPI Package | `pip install codd-dev` |
| Stars | 49 (2026-04-19時点) |
| Version | v1.9.3 (公開 repo, 2026-04-18確認) / v1.8.0 (ローカルCLI実績値) |
| Last Commit | 2026-04-14 以降継続 |
| Repo | https://github.com/yohey-w/codd-dev |
| License | MIT |
| Language | Python |
| SWE-bench実績 | 73問 100%達成 (v1.8.0時点, 記事より) |

## Design Philosophy

- **Derive, Don't Configure**: 下流の設定を手で並べるな。上流の事実から下流を導出せよ。設定の増殖ではなく依存関係とハーネスで整合性を強制する
- **Wave順生成**: 依存チェーン順に設計書を生成することで、整合性を後付けレビューでなく生成順そのもので強制する
- **コンテキスト断捨離**: 情報を渡しすぎると退化する。`extract` のような構文解析ベースの粒度が最も安定する
- **Harness Engineering**: 事前説明より事後フィードバックが効く。失敗時はDIVERGENTで仮説転換を強制する
- **診断推論 (v1.8.0)**: 情報注入より思考構造の強制が効く。先に根本原因を書かせ、Session Stateで学習を持ち越す

## Architecture

### コマンド体系

| 系統 | コマンド列 | 役割 |
|------|------------|------|
| グリーンフィールド | `init → plan → generate → validate → implement → assemble` | 要件から設計書群を順生成し整合性を崩さず実装まで進める |
| ブラウンフィールド | `extract → require → plan → restore → scan → impact → audit → measure` | 既存コードから構造を抽出し差分影響と健全性を測りながら設計を復元する |
| 変更伝播 | `scan → impact → propagate --update` | 変更点から波及先を導出し更新対象を手で列挙せず伝播させる |
| 品質 | `validate`, `review --feedback`, `verify`, `policy`, `audit` | 設計整合性・レビュー・検証・方針遵守を段階別に確認する |
| 修正 | `fix` | Diagnose MANDATORY + Session State。retry前に根本原因を書かせ失敗履歴を引き継ぐ |
| 連携 | `mcp-server` | stdio JSON-RPCで外部エージェントや道具からCoDD機能を呼び出せる |
| 健全性 | `measure` | CoDD運用を0-100で採点し構造の劣化を数値で監視する |

### 3層モデル

| 層 | 役割 | 主要コマンド |
|----|------|------------|
| L1 事前設計書 | spec/design/plan を先に整合させる | `plan`, `generate`, `extract` |
| L2 事後フィードバック | テストFBとDIVERGENT強制でリトライを制御する | `fix`, `validate`, `review` |
| L3 診断推論 | Diagnose MANDATORY + Session State で学習を持ち越す | `fix` (v1.8.0以降) |

### OSS / Pro 分割 (v1.6.0以降)

| 区分 | 内容 |
|------|------|
| OSS (codd-dev) | init, plan, generate, validate, implement, assemble, extract, impact, fix, measure, mcp-server |
| Pro (非公開) | review, verify, audit, risk |

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|--------------|
| Diagnose MANDATORY | fix実行前に根本原因の言語化を強制するプロトコル | v1.8.0 |
| Session State | 失敗履歴をstateful管理し次回retry時に引き継ぐ | v1.8.0 |
| codd extract | 既存コードから設計書を抽出する構文解析ベースのコマンド | v1.8.0 |
| codd impact | 変更の波及先を導出する依存解析コマンド | v1.8.0 |
| codd measure | CoDD運用健全性を0-100で採点するメトリクス | 初期より |
| mcp-server | stdio JSON-RPC経由で外部エージェントと連携 | 初期より |
| DIVERGENT強制 | 同一原因での2回連続FAIL時に仮説転換を強制する | v1.8.0 |

## Changelog since 2026-03-29

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-03-29 | v0.2.0a2 | α版公開。propagation方向修正・日本語README追加 | 初回OSS公開 |
| 2026-04-01 | v1.2.1 | `codd hooks install` FileNotFoundError修正 | インストール安定化 |
| 2026-04-06 | v1.5.1 | `codd measure`クラッシュ修正・`codd validate`誤検出修正 | 品質コマンド安定化 |
| 2026-04-06 | v1.6.0 | OSS/Pro分割: review/verify/audit/riskをcodd-pro(非公開)に移管 | OSSの範囲が明確化 |
| 〜2026-04-14 | v1.8.0 | codd extract・codd impact・codd fix追加。SWE-bench 73問 100%達成 | 実装・修正支援コマンドの完成 |
| 2026-04-15以降 | v1.8.1〜v1.9.3 | sprint前提撤去・flat task-based generate。失敗コンテキスト汚染ガード | 実装品質の向上と余分な暗黙前提の削減 |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| Derive, Don't Configure | 設定を手書きせず上流事実から下流を導出する設計原則 | 固有 |
| Wave順設計書生成 | 依存チェーン順に生成し整合性を生成プロセスに内蔵する | 固有 |
| Diagnose MANDATORY | retry前に根本原因の言語化を強制し表面的修正を防ぐ | 固有 |
| Session State (CoDD) | 失敗履歴をstateful管理し次セッションに引き継ぐ | 固有 |
| コンテキスト断捨離 | extractのような構文解析で必要な情報のみを粒度よく提供する | 固有 |
| DIVERGENT強制 | 同一仮説での連続FAILを検知し仮説転換を強制する | 固有 |

## Ecosystem

| カテゴリ | 内容 |
|---------|------|
| PyPI | https://pypi.org/project/codd-dev/ |
| 開発者システム | yohey-w/multi-agent-shogun (おしお殿の将軍システム本体) |
| GitHub Sponsors | https://github.com/sponsors/yohey-w |
| 解説記事 (Zenn) | 「Prompt→Context→Harness、全部やった。整合性駆動開発CoDD爆誕」 https://zenn.dev/shio_shoppaize/articles/shogun-codd-coherence |
| 解説記事 (Zenn) | 「Harness as Code — CoDD活用ガイド #4」 https://zenn.dev/shio_shoppaize/articles/codd-swebench-loop |
| 解説記事 (Zenn) | 「CoDD — コード0行・スマホだけで、設計書が腐らないOSSを作った話」 https://zenn.dev/shio_shoppaize/articles/codd-skeleton-complete |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| bash実装非対応 | codd implement/generateはPythonプロジェクト向けで、bashスクリプト生成には対応していない。bash中心のインフラ改善では設計書生成まで(spec/plan)は使えるが実装フェーズで止まる | bash中心のインフラ改善cmd、CI/CD設定ファイル生成 |
| OSS/Pro分割によるフルフロー非実現 | review/verify/audit/riskはcodd-pro(非公開)に移管済みのため、OSSのcodd-devだけでは設計書生成→品質保証フローが完結しない | SWE-benchフロー再現、本格的な品質保証パイプライン構築時 |
| Session State累積によるコンテキスト膨張 | FAIL時にtask YAMLへ記録する失敗履歴は再注入時のコンテキスト消費を増大させるため、多数FAIL後のリトライでは注入コストが上がりむしろ品質低下する | 多数失敗後のリトライ、長期継続セッション、複雑な設計修正 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [oshio](oshio.md) | CoDDはおしお殿のmulti-agent-shogunと同一作者によるツール。shogunシステムのSpec→Harness整合性検証をCoDDが担保する位置づけ |
| 競合 | [gsd](gsd.md) | CoDDは設計書の整合性を自動検証することでコード品質を保証するのに対し、GSDはロール分担と人間レビューを中心に置く。品質保証の自動化vs人間主導の軸で対比される |
| 前提 | [our-army](our-army.md) | CoDDをマルチエージェント環境で活用するには、our-armyのようなYAML配備・gate・教訓還流フロー・忍者ハーネスが前提となる |

## Sources

| 種別 | URL |
|------|-----|
| Repository | https://github.com/yohey-w/codd-dev |
| PyPI | https://pypi.org/project/codd-dev/ |
| 解説記事 #1 | https://zenn.dev/shio_shoppaize/articles/shogun-codd-coherence |
| 解説記事 #4 (SWE-bench) | https://zenn.dev/shio_shoppaize/articles/codd-swebench-loop |
| 解説記事 #5 | https://zenn.dev/shio_shoppaize/articles/codd-skeleton-complete |
| GitHub Sponsors | https://github.com/sponsors/yohey-w |

## Verification

| 項目 | 値 |
|------|-----|
| verified_at | 2026-04-19 |
| method | ローカルCLI実行確認 (`codd --version`) + context/codd.md精読 + oshio.md CoDD Changelogセクション参照 |
| source | context/codd.md (ローカル一次資料) / github.com/yohey-w/codd-dev (repo確認) / zenn.dev/shio_shoppaize (記事群) |
| notes | v1.9.3はcontext/codd.mdの2026-04-18時点cmd_2067調査より。bash非対応はmemory/tool_codd_lessons.mdで実証済み |
