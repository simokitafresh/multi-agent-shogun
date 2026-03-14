# gstack知識索引
<!-- last_updated: 2026-03-14 cmd_935 -->

## §1 概要

| 項目 | 結論 | 参照 |
|------|------|------|
| システム像 | gstack = 1人×6モード切替の個人生産性特化システム | `docs/research/gstack-analysis.md` §1 |
| 詳細層 | 初回12件 = `gstack-analysis.md` / 深掘り64件+逆差分 = `gstack-deep-analysis.md` | `docs/research/gstack-analysis.md`, `docs/research/gstack-deep-analysis.md` |
| 件数補正 | `gstack-deep-analysis.md` 本文は64件表記だが表は65行。`G10-9` はアーキテクチャ注記として索引件数から除外し 64 件に正規化 | `docs/research/gstack-deep-analysis.md` §1, §2 G10 |
| 現在地 | 初回12件は全件適用済。深掘り64件は 8件適用済 / 4件適用中 / 49件未適用 / 3件不採用 | `queue/archive/cmds/cmd_875_completed_20260313.yaml`, `queue/shogun_to_karo.yaml`, `queue/archive/cmds/cmd_933_completed_20260314.yaml` |

## §2 ロール対応

| gstackモード | 我が軍ロール | 主適用先 | 参照 |
|-------------|------------|---------|------|
| `/plan-ceo-review` | 将軍 | `instructions/shogun.md` | `docs/research/gstack-analysis.md` §1, `queue/archive/cmds/cmd_928_completed_20260314.yaml` |
| `/plan-eng-review` | 将軍+家老 | `instructions/shogun.md`, `instructions/karo.md` | `docs/research/gstack-analysis.md` §1, `queue/shogun_to_karo.yaml` |
| `/review` | 家老+忍者 | `context/karo-operations.md`, `instructions/ashigaru.md` | `docs/research/gstack-analysis.md` §1, `queue/shogun_to_karo.yaml` |
| `/ship` | 家老 | `scripts/gates/*`, `instructions/karo.md` | `docs/research/gstack-analysis.md` §1, `queue/shogun_to_karo.yaml` |
| `/browse` | 忍者(CDP) | `scripts/cdp/*` | `docs/research/gstack-analysis.md` §3, `context/infrastructure.md` |
| `/retro` | 家老 | `chronicle_metrics.sh` 系 / 将来候補 | `docs/research/gstack-analysis.md` §1, §4 |

## §3 テクニック索引（初回12）

| ID | テクニック | 状態 | 適用先 | 適用cmd / 参照 |
|----|-----------|------|--------|----------------|
| A2.1 | Suppressions | 適用済 | `instructions/ashigaru.md` | `cmd_925` / `docs/research/gstack-analysis.md` §2.1 |
| A2.2 | 停止条件の二分法 | 適用済 | task YAML (`stop_for` / `never_stop_for`) | `cmd_875` / `docs/research/gstack-analysis.md` §2.2 |
| A2.3 | 推薦先行+WHY | 適用済 | `instructions/ashigaru.md`, `instructions/shogun.md` | `cmd_925`, `cmd_928` / `docs/research/gstack-analysis.md` §2.3 |
| A2.4 | モードコミットメント | 適用済 | `instructions/shogun.md`, `queue/shogun_to_karo.yaml` | `cmd_928` / `docs/research/gstack-analysis.md` §2.4 |
| A2.5 | 反復STOP | 適用済 | `instructions/ashigaru.md`, `scripts/deploy_task.sh` | `cmd_929` / `docs/research/gstack-analysis.md` §2.5 |
| A2.6 | Priority Hierarchy | 適用済 | `instructions/karo.md`, `scripts/deploy_task.sh` | `cmd_926` / `docs/research/gstack-analysis.md` §2.6 |
| A2.7 | Engineering Preferences事前注入 | 適用済 | `projects/*.yaml` | `cmd_927` / `docs/research/gstack-analysis.md` §2.7 |
| A2.8 | 「名前をつけろ」パターン | 適用済 | `instructions/ashigaru.md` | `cmd_929` / `docs/research/gstack-analysis.md` §2.8 |
| A2.9 | 並列実行の明示指示 | 適用済 | `instructions/karo.md`, `scripts/deploy_task.sh` | `cmd_926` / `docs/research/gstack-analysis.md` §2.9 |
| A2.10 | Temporal Interrogation | 適用済 | `instructions/shogun.md` | `cmd_928` / `docs/research/gstack-analysis.md` §2.10 |
| A2.11 | Dream State Mapping | 適用済 | `instructions/shogun.md` | `cmd_928` / `docs/research/gstack-analysis.md` §2.11 |
| A2.12 | Two-pass Review | 適用済 | `context/karo-operations.md`, `docs/research/karo-operations-detail.md` | `cmd_876` / `docs/research/gstack-analysis.md` §2.12 |

## §3.1 テクニック索引（深掘り64）

| ID | テクニック | 状態 | 適用先 | 適用cmd / 参照 |
|----|-----------|------|--------|----------------|
| G1-1 | 事前システム監査 | 未適用(低) | 偵察/レビュー開始手順 | `—` / `docs/research/gstack-deep-analysis.md` §2 G1-1 |
| G1-2 | 再発領域増幅レビュー | 未適用(中) | 家老配備時の履歴確認 | `—` / `docs/research/gstack-deep-analysis.md` §2 G1-2 |
| G1-3 | Taste Calibration | 未適用(低) | 大型設計レビュー | `—` / `docs/research/gstack-deep-analysis.md` §2 G1-3 |
| G2-1 | Shadow Paths 4分岐 | 適用中 | `instructions/ashigaru.md` | `cmd_934` / `docs/research/gstack-deep-analysis.md` §2 G2-1 |
| G2-2 | Interaction Edge Matrix + Hostile QA | 未適用(中) | 偵察テンプレート | `—` / `docs/research/gstack-deep-analysis.md` §2 G2-2 |
| G2-3 | Error & Rescue Registry | 未適用(高) | 高リスク偵察テンプレート | `—` / `docs/research/gstack-deep-analysis.md` §2 G2-3 |
| G2-4 | レビュー観点の章分離 | 未適用(中) | 家老レビューcmd設計 | `—` / `docs/research/gstack-deep-analysis.md` §2 G2-4 |
| G2-5 | 追加レビュー観点4種 | 未適用(中) | 偵察/レビュー観点ライブラリ | `—` / `docs/research/gstack-deep-analysis.md` §2 G2-5 |
| G2-6 | CEO vs Eng多段階レビュー | 未適用(低) | 将軍→家老分解規律 | `—` / `docs/research/gstack-deep-analysis.md` §2 G2-6 |
| G3-1 | Checklist外部ファイル分離 | 未適用(低) | 品質4要件の外部化 | `—` / `docs/research/gstack-deep-analysis.md` §2 G3-1 |
| G3-2 | Read-only Default | 適用中 | `instructions/ashigaru.md` | `cmd_934` / `docs/research/gstack-deep-analysis.md` §2 G3-2 |
| G3-3 | A/B/C Triage | 適用済 | `instructions/karo.md`, `docs/research/karo-operations-detail.md` | `cmd_933` / `docs/research/gstack-deep-analysis.md` §2 G3-3 |
| G3-4 | 1 issue = 2 lines | 未適用(低) | レビュー出力契約 | `—` / `docs/research/gstack-deep-analysis.md` §2 G3-4 |
| G3-5 | FP/FN対策（Suppressions外） | 未適用(低) | 家老レビュー規律 | `—` / `docs/research/gstack-deep-analysis.md` §2 G3-5 |
| G4-1 | Deferred Work Discipline | 適用済 | `instructions/shogun.md`, `CLAUDE.md`, `AGENTS.md` | `cmd_932` / `docs/research/gstack-deep-analysis.md` §2 G4-1 |
| G4-2 | BIG/SMALL CHANGE圧縮モード | 未適用(低) | review/recon cmd設計 | `—` / `docs/research/gstack-deep-analysis.md` §2 G4-2 |
| G4-3 | Completion Summary | 適用済 | `instructions/karo.md` | `cmd_932` / `docs/research/gstack-deep-analysis.md` §2 G4-3 |
| G4-4 | Stale Diagram Audit | 未適用(低) | 図を含む変更時の監査 | `—` / `docs/research/gstack-deep-analysis.md` §2 G4-4 |
| G5-1 | Named Invariants | 適用中 | `instructions/ashigaru.md` | `cmd_934` / `docs/research/gstack-deep-analysis.md` §2 G5-1 |
| G5-2 | Section Gate付き単一意思決定 | 未適用(中) | 殿判断事項の節単位制御 | `—` / `docs/research/gstack-deep-analysis.md` §2 G5-2 |
| G5-3 | Incremental Evidence Capture | 適用中 | `instructions/ashigaru.md`, 報告YAML規律 | `cmd_934` / `docs/research/gstack-deep-analysis.md` §2 G5-3 |
| G5-4 | LLM Prompt Eval Scope接続 | 未適用(中) | LLM変更時のeval列挙 | `—` / `docs/research/gstack-deep-analysis.md` §2 G5-4 |
| G6-1 | Merge origin/main before test | 未適用(中) | push前review task | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-1 |
| G6-2 | Diff-based Conditional Eval | 未適用(高) | deploy/gate自動注入 | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-2 |
| G6-3 | Re-review Loop | 適用済 | `instructions/karo.md`, `docs/research/karo-operations-detail.md` | `cmd_933` / `docs/research/gstack-deep-analysis.md` §2 G6-3 |
| G6-4 | Version Auto-decide | 未適用(中) | release判断 | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-4 |
| G6-5 | CHANGELOG Full-commit Reconstruction | 未適用(中) | dashboard/chronicle統合 | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-5 |
| G6-6 | Bisectable Commit Grouping | 未適用(中) | impl taskのcommit規律 | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-6 |
| G6-7 | PR Body Mandatory Sections | 未適用(低) | 報告YAML / PR本文 | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-7 |
| G6-8 | Ship内蔵8ゲート+Eval 3段Tier | 未適用(高) | 家老shipフロー | `—` / `docs/research/gstack-deep-analysis.md` §2 G6-8 |
| G7-1 | wrapError (AI行動指示変換) | 適用済 | `scripts/gates/gate_*.sh` | `cmd_933` / `docs/research/gstack-deep-analysis.md` §2 G7-1 |
| G7-2 | CLI自動復旧3段階リトライ | 未適用(中) | CLI復旧補助 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-2 |
| G7-3 | Token Mismatch Recovery | 未適用(中) | daemon/CLI整合復旧 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-3 |
| G7-4 | Crash→Exit→Auto-restart哲学 | 未適用(中) | 補助サーバー復旧方針 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-4 |
| G7-5 | Context Recreation 3段フォールバック | 未適用(中) | 復旧フロー | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-5 |
| G7-6 | SQLite Copy-on-Lock | 未適用(中) | SQLite lock回避 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-6 |
| G7-7 | Chain Error封じ込め | 未適用(中) | バッチ実行失敗分離 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-7 |
| G7-8 | Health Check = evaluate + race timeout | 未適用(低) | zombie/stall検知 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-8 |
| G7-9 | Graceful Shutdown冪等性 | 未適用(中) | 補助サーバー終了処理 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-9 |
| G7-10 | Buffer Flush非致命哲学 | 未適用(低) | 補助サーバー終了処理 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-10 |
| G7-11 | サーバー起動失敗時stderr読取 | 未適用(低) | 補助サーバー起動診断 | `—` / `docs/research/gstack-deep-analysis.md` §2 G7-11 |
| G8-1 | State File方式ディスカバリ | 適用済 | `scripts/cdp/*` | `cmd_877` / `docs/research/gstack-deep-analysis.md` §2 G8-1 |
| G8-2 | Auth Token (randomUUID) | 未適用(低) | CDP daemon認証 | `—` / `docs/research/gstack-deep-analysis.md` §2 G8-2 |
| G8-3 | CircularBuffer O(1)リングバッファ | 未適用(中) | CDP buffer | `—` / `docs/research/gstack-deep-analysis.md` §2 G8-3 |
| G8-4 | Multi-instance (PORT計算) | 未適用(低) | 忍者別CDPポート割当 | `—` / `docs/research/gstack-deep-analysis.md` §2 G8-4 |
| G8-5 | Idle Timer自動シャットダウン | 適用済 | `scripts/ninja_monitor.sh` | `既存infra` / `docs/research/gstack-deep-analysis.md` §2 G8-5 |
| G9-1 | Network Response後方マッチング | 未適用(中) | CDP Network処理 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-1 |
| G9-2 | Cursor-Interactive Scan -C | 未適用(中) | CDP補完検出 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-2 |
| G9-3 | Cookie Import (Chromium暗号化復号) | 未適用(高) | auto-ops認証補助 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-3 |
| G9-4 | Cookie Picker Web UI | 未適用(高) | 認証デバッグUI | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-4 |
| G9-5 | Sensitive Value Redaction | 未適用(低) | CDPログ/入出力保護 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-5 |
| G9-6 | Path Traversal防止 | 適用済 | `AGENTS.md` D002 / realpath運用 | `既存infra` / `docs/research/gstack-deep-analysis.md` §2 G9-6 |
| G9-7 | Dialog Auto-Accept | 未適用(低) | CDP dialog処理 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-7 |
| G9-8 | Ref-Baseline寿命分離 | 未適用(中) | CDP ref管理 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-8 |
| G9-9 | Cross-session Baseline Artifacts | 未適用(低) | baseline差分運用 | `—` / `docs/research/gstack-deep-analysis.md` §2 G9-9 |
| G10-1 | スキル間依存関係マップ | 未適用(低) | skill相互参照索引 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-1 |
| G10-2 | 2段バイナリ発見 | 未適用(低) | skill/binary探索 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-2 |
| G10-3 | CLAUDE.md極薄設計 | 不採用: 自動ロード索引に恒久ルールを載せる設計を維持 | `AGENTS.md`, `instructions/*` | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-3 |
| G10-4 | Allowed-tools最小権限宣言 | 未適用(低) | task YAML制約 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-4 |
| G10-5 | Setupスマートリビルド | 未適用(中) | skill/build再生成 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-5 |
| G10-6 | Dual SKILL.md | 未適用(低) | skill配布形式 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-6 |
| G10-7 | 共有データ構造は1つだけ | 不採用: queue/gate/inbox運用で複数共有構造が必要 | infra共通設計 | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-7 |
| G10-8 | 設定ファイルなし | 不採用: 多PJ/多CLI/多ロール運用で `config/*.yaml` が必須 | `config/*.yaml` | `—` / `docs/research/gstack-deep-analysis.md` §2 G10-8 |
| G11-1 | BrowserManager直接呼出しテスト | 未適用(中) | CDPユニットテスト | `—` / `docs/research/gstack-deep-analysis.md` §2 G11-1 |

## §4 逆差分サマリ

### §4.1 我が軍にあり gstack にないもの

| 項目 | 結論 | 参照 |
|------|------|------|
| マルチエージェント並列 | 8忍者同時並列が前提 | `docs/research/gstack-deep-analysis.md` §4 |
| 永続状態管理 | YAML + dashboard + snapshot を正本にする | `docs/research/gstack-deep-analysis.md` §4 |
| 教訓の組織蓄積 | `lessons.yaml` + Memory MCP を分離運用 | `docs/research/gstack-deep-analysis.md` §4 |
| gate自動化 | `gate_*.sh` + `cmd_complete_gate.sh` が品質を強制 | `docs/research/gstack-deep-analysis.md` §4 |
| inbox通知 | `inbox_write.sh` + watcher でイベント駆動 | `docs/research/gstack-deep-analysis.md` §4 |
| 破壊操作安全装置 | D001-D008 と Tier 2/3 安全規則 | `AGENTS.md`, `docs/research/gstack-deep-analysis.md` §4 |
| 偵察編成 | 水平+垂直の分担偵察が可能 | `docs/research/gstack-deep-analysis.md` §4 |
| CTX自動管理 | `ninja_monitor` が `/new` / `/clear` を自動送信 | `context/infrastructure.md`, `docs/research/gstack-deep-analysis.md` §4 |
| GUI直接制御 | WSL2→PowerShell→Chrome CDP が可能 | `context/infrastructure.md`, `docs/research/gstack-deep-analysis.md` §4 |
| PJ横断管理 | `projects/*.yaml` + `config/projects.yaml` で複数PJ管理 | `docs/research/gstack-deep-analysis.md` §4 |

### §4.2 gstack にあり 我が軍にないもの

| 項目 | 状態 | 参照 |
|------|------|------|
| `/qa` 体系的QA | 未導入。仙人構想候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Cookie Import | 未導入。auto-ops参考止まり | `docs/research/gstack-deep-analysis.md` §4 |
| data-driven `/retro` | 未導入。chronicle→メトリクス化候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Chain バッチ実行 | 未導入。CDP daemon側の候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Annotated Screenshots | 未導入。CDP拡張候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Element State Checks | 未導入。CDP拡張候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Snapshot Diff | 未導入。baseline比較候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Error & Rescue Map | 未導入。高リスクcmd向け候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Interaction Edge Matrix | 未導入。偵察テンプレート候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Prime Directives 9原則 | 一部導入中。cmd_934 | `docs/research/gstack-deep-analysis.md` §4, `queue/shogun_to_karo.yaml` |
| NOT in scope | 適用済。cmd_932 | `docs/research/gstack-deep-analysis.md` §4, `queue/shogun_to_karo.yaml` |
| Failure Modes Registry | 未導入。高リスク偵察候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Stale Diagram Audit | 未導入。図更新監査候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Completion Summary | 適用済。cmd_932 | `docs/research/gstack-deep-analysis.md` §4, `queue/shogun_to_karo.yaml` |
| Security/Threat Model章 | 未導入。家老レビュー候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Observability Review章 | 未導入。家老レビュー候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Deployment Review章 | 未導入。家老レビュー候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Path Validation | 既存運用で代替済み | `AGENTS.md`, `docs/research/gstack-deep-analysis.md` §4 |
| Dialog Auto-handling | 未導入。CDP拡張候補 | `docs/research/gstack-deep-analysis.md` §4 |
| Cookie Picker UI | 未導入。デバッグUI候補 | `docs/research/gstack-deep-analysis.md` §4 |

## §5 参照先

| 用途 | パス | 参照範囲 |
|------|------|----------|
| 初回12件の詳細 | `docs/research/gstack-analysis.md` | §1, §2, §4 |
| 深掘り64件+逆差分 | `docs/research/gstack-deep-analysis.md` | §1-§4 |
| 初回適用cmd群 | `queue/archive/cmds/cmd_875_completed_20260313.yaml` | cmd_875 |
| 初回適用cmd群 | `queue/archive/cmds/cmd_925_completed_20260314.yaml` | cmd_925 |
| 初回適用cmd群 | `queue/archive/cmds/cmd_926_completed_20260314.yaml` | cmd_926 |
| 初回適用cmd群 | `queue/archive/cmds/cmd_928_completed_20260314.yaml` | cmd_928 |
| 初回適用cmd群 | `queue/archive/cmds/cmd_929_completed_20260314.yaml` | cmd_929 |
| 深掘り適用cmd群 | `queue/shogun_to_karo.yaml` | `cmd_932`, `cmd_933`, `cmd_934`, `cmd_935` |
