# CoDD (Coherence-Driven Development) 索引

<!-- last_updated: 2026-08-10 cmd_karo_hotfix_ga452_context_boundaries_202608100949 content-reflection -->
<!-- source_commit:1dae80c86 reason:cmd_karo_hotfix_ga452_context_boundaries_202608100949 content-reflection evidence:source diff reviewed: skills/codd-refactor/SKILL.md external backend contract pytest/PYTHONPATH boundary -->
<!-- source_commit:35d4b10fc reason:cmd_karo_hotfix_codd_refactor_skill_ref_sync_20260729 reviewed source boundary evidence:cmd_complete_gate project=infra context=context/codd.md commit=35d4b10fc -->
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
| 版数 | ローカルCLI=`2.19.0` (`/home/simokitafresh/.codd-venv/bin/codd --version`, 2026-06-06確認)。PATH未設定の非対話shellでは`codd`不可のためフルパスかPATH exportを使う |
| 位置づけ | CoDDは「要件/制約 -> 設計 -> 実装 -> テスト」をDAGとして維持し、設計書腐敗を`elicit`/`dag verify`/`fix [PHENOMENON]`/auto-repairで抑えるHarness Engineering実装 |

## §2 コマンド体系

| 系統 | コマンド列 | 結論 |
|------|------------|------|
| グリーンフィールド | `init -> elicit -> generate --wave N -> implement run -> dag verify -> deploy` | 要件の穴を`elicit`で発見し、設計書から実装とテストを生成してDAG検証する。v2.18.0では`implement run --language`と`--enable-typecheck-loop`を確認済み |
| ブラウンフィールド | `brownfield TARGET` / `extract -> diff -> elicit` | 既存コードから設計情報を抽出し、実装_only/要求_only/driftを見つけ、要件穴や制約不足を統合レポート化する |
| 変更伝播 | `scan -> impact -> propagate --update` | 変更点から波及先を導出し、更新対象を手で列挙せず伝播させる |
| DAG整合性 | `dag build`, `dag verify`, `dag verify --auto-repair --apply`, `dag run-journey`, `dag visualize` | 要件・設計・実装・テスト・デプロイ・journeyの家系図を検査し、違反時は提案または機械修復する |
| 制約/辞書 | `lexicon list/install/diff`, `coverage report`, `elicit apply` | 業界標準やプロジェクト制約をlexiconとして管理し、要件穴・coverage軸・spec holeを承認制で反映する |
| 品質 | `validate`, `review --feedback`, `verify`, `policy`, `audit`, `measure` | 設計整合性・レビュー・検証・方針遵守・健全性スコアを段階別に確認する |
| 修正 | `fix` / `fix [PHENOMENON]` | 旧来のCI/test修正に加え、自然言語の事象から関連設計書を探し、設計書 -> 実装 -> テストを更新して検証する |
| 連携 | `mcp-server` | stdio JSON-RPCで外部エージェントや道具からCoDD機能を呼び出せる |

### 公開差分メモ (2026-04-18確認)

| 版/commit | 差分 | 我が軍への示唆 |
|-----------|------|----------------|
| v1.8.0 / `5b15da5` | `codd/fixer.py` に Diagnose MANDATORY + `_SessionState` を実装 | GP-198/200/201 の原典。retryを stateful にする発想の核 |
| v1.8.1 / `e56b026` | sprint 前提を撤去し、`implement` を flat task-based generation に簡素化 | prompt/parser の暗黙前提を減らす方向が正しい |
| v1.9.2 / `55f3884` | failed task summary を downstream prompt から除外 | failure-context contamination guard を我が軍の注入系へ横展開すべし |
| v1.10.0 / `474d306` | `implement`, `assemble`, `hooks`, `repair-slice`, `risk`を含む22コマンド構成を確認 | 設計書グラフ+伝播を中心に使い、bash実装は手動実装+検証に留める |
| v1.35.0-v2.0.0 | `elicit`, `diff`, `brownfield`, `lexicon list/install/diff`, `coverage report`, `dag verify --auto-repair`が追加され、制約側がplug-in化 | 要件本文だけでなく「制約/coverage軸」をlexiconとして正本化する |
| v2.17.x | `fix [PHENOMENON]`で「触った後の感想」から設計書・実装・テストを一括更新する北極星に到達 | 改善要求はコード変更指示ではなく、観測した事象として渡す方がCoDDの流儀に合う |
| v2.18.0 | ローカルCLIで`implement run --language`, `dag verify --auto-repair --apply`, `brownfield TARGET`, `lexicon list/install/diff`を確認 | bashでも実装生成を試行可能。ただし失敗時は従来どおり設計書・DAG・伝播までをCoDDに任せ、実装は手動で行う |
| v2.19.0 | ローカルCLIで`drift`, `fixup-drift`, `propagate-from`, `qc`, `require`, `restore`, `watch`を含む現行コマンド一覧を確認 | 既存の`fix [PHENOMENON]`/`implement run --language`/`dag verify --auto-repair --apply`は継続。新系統は利用前に対象PJの`codd.yaml`とdry-runで確認する |

### bash implement試行結果 (cmd_2485 / 2026-05-02)

| 試行 | 結果 | 判断 |
|------|------|------|
| `codd --version` | `codd, version 1.10.0` | AC1確認済み |
| `codd implement --language bash` | `Error: No such option: --language` / RC=2 | v1.10.0でもbash言語指定implementは非対応 |
| `codd implement --help` | `--path`, `--task`, `--clean`, `--ai-cmd`のみ | 実装生成はImplementation Plan前提。bashプロジェクトでは設計生成・伝播・手動実装を標準とする |

### v2.19.0 ローカル実測 (cmd_karo_hotfix_context_freshness_ga007_20260606 / 2026-06-06)

| 試行 | 結果 | 判断 |
|------|------|------|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | `codd, version 2.19.0` | ローカル導入済み |
| `codd` (PATH未設定shell) | `command not found` | 忍者/家老の非対話Bashではフルパスか`export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"`必須 |
| `codd --help` | `drift`, `fixup-drift`, `propagate-from`, `qc`, `require`, `restore`, `watch`を含む | §2の中核系統は維持。新コマンドは現物helpを一次確認してから使う |
| `codd implement run --help` | `--language`, `--enable-typecheck-loop`, `--chunk-size`, `--timeout-per-chunk`, `--use-derived-steps`あり | v1.10の「bash implement非対応」は履歴扱い。v2.19では試行して、失敗時のみ手動へfallback |
| `codd dag verify --help` | `--auto-repair` + `--apply`あり | dry-run提案と実書込を分ける。運用YAMLには適用しない |
| `codd fix --help` | `[PHENOMENON]` positionalあり | 自然言語の事象から設計書・実装・テストを更新する入口として使用可能 |

### 2026-07-01 鮮度確認

| 確認 | 結果 | 判断 |
|------|------|------|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | `codd, version 2.19.0` | §2/§5のv2.19.0前提は維持 |
| `git log --since=2026-06-23 -- scripts/codd scripts/codd_ skills/codd skills/codd-refactor` | 対象差分なし | CoDDコマンド体系・スキル参照の更新不要 |
| 通常`gate_context_freshness.sh` | 日数WARNのみ | 内容更新ではなく鮮度確認としてlast_updatedを更新 |

### 2026-07-09 鮮度確認

| 確認 | 結果 | 判断 |
|------|------|------|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | `codd, version 2.19.0` | §1/§2/§5のローカルCLI前提は維持 |
| `/home/simokitafresh/.codd-venv/bin/codd --help` | `drift`, `fixup-drift`, `propagate-from`, `qc`, `require`, `restore`, `watch`を含む | 2026-07-01記載の現行コマンド体系と矛盾なし |
| `git log --since=2026-07-01 -- context/codd.md scripts/gates/gate_context_freshness.sh scripts/context_freshness_check.sh` | context本体更新はGA-154のみ。以後はcontext freshness gate品質/重複mapping修正 | CoDD本文へ追記すべき新仕様なし。今回GA-203は日数WARNの再確認 |

### 2026-07-18 GA-288 鮮度防御

| 確認 | 結果 | 判断 |
|------|------|------|
| `git log 3370147d1..e22a319e8 -- skills/codd skills/codd-refactor scripts/codd scripts/codd_` | source commit 2件 (`0da0dccb9`, `e22a319e8`) | script参照契約の再検分であり本文のCoDD操作体系は不変 |
| source変更commit時の索引追随 | pre-commitに対応する強制なし | CoDD sourceと本索引を同一commitへstageするLevel4防御を追加 |
| 同一commit反映の鮮度判定 | source pathだけをgit log対象にしていた | sourceと本索引が同一commitなら反映済みとして除外し、次の未反映source変更だけをALERTする |

GA-299再分類: `81b1ea6d9` は `codd-refactor` の参照済みテスト契約注記のみで、CoDDのCLI・操作体系・副作用に実内容変更なし。

GA-300再分類: `ff52b26b3` は `run_tests.sh` の参照鮮度再検分（境界後の対象commit 0件）だけで、CoDDのCLI・操作体系・副作用に実内容変更なし。

### 2026-08-01 `run_tests.sh` 外部contract実行境界

- `skills/codd-refactor/SKILL.md` の外部backend contract testは、対象PJの`.venv` pytestとproject-root `PYTHONPATH`で実行する。`task` mode・明示test選択・FAIL/SKIP時の終了契約は不変。
- 参照: `skills/codd-refactor/SKILL.md`、source commit `1dae80c86`。

## §3 核心原理 (記事#1-#5)

| 原理 | 結論 | 参照 |
|------|------|------|
| Derive, Don't Configure | 下流設定を手で並べるな。上流の事実から下流を導出せよ | `memory/reference_codd_oshio_articles.md` |
| Wave順生成 | 依存チェーン順に生成することで、設計整合性を後付けレビューでなく生成順そのもので強制する | `memory/reference_codd_oshio_articles.md` |
| コンテキスト断捨離 (#3) | 情報を渡しすぎると退化する。`extract` のような構文解析ベースの粒度が最も安定 | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| Harness Engineering (#4) | 事前説明より事後フィードバックが効く。失敗時はDIVERGENTで仮説転換を強制する | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| 診断推論 (#5) | 情報注入より思考構造の強制が効く。先に根本原因を書かせ、Session Stateで学習を持ち越す | `memory/reference_codd_oshio_articles.md`, `docs/research/gunshi_codd_swebench_application_20260416.md` |
| 3層モデル | L1=事前設計書、L2=事後フィードバック+リトライ、L3=診断推論+記憶。3層が揃って初めて退化しにくい | `docs/research/gunshi_codd_swebench_application_20260416.md` |
| skeleton-complete (#6) | 設計書は作成でなく維持が本体。`scan`で依存グラフを作り、`impact`で影響範囲を出し、`propagate --update`で下流docsを追随させる | `memory/reference_codd_oshio_articles.md` |
| Lexicon-driven completeness | 要件の抜けは人間の注意でなく`elicit`+lexiconで発見し、coverage軸として機械検査に載せる | `memory/reference_codd_oshio_articles.md` |
| 感想駆動の継続改善 | `codd fix [PHENOMENON]`で、ユーザーが触って感じた事象を設計書・実装・テスト更新へ変換する | `memory/reference_codd_oshio_articles.md` |

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
| L1 事前 | codd extract設計書 | related_lessons + context_files | 有用率26%→3件絞込み実装済み(GP-199 CLEAR)。アーキテクチャ概要→ [[architecture-overview]] (`docs/research/cmd_1991_codd_extract/architecture-overview.md`) |
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
| `/codd` | 設計書/DAG/lexiconパイプライン専用。specからWave設計書群を起こし、必要に応じて`elicit`/`dag verify`/`propagate`まで確認する | `skills/codd/SKILL.md` |
| `/codd-refactor` | 計測 -> spec -> CoDD -> 実装試行/手動実装 -> 再計測の一連を回す。no-arg時は14列test timing ledgerの最新`cache_hit=0`完了runを基準にし、Phase 5は同一test_file/suite_rootのrun同士だけを比較、欠損・旧4列台帳は`UNVERIFIED`でfail-closed。反復・報告直前の`run_tests.sh task`は明示`test_path`/確定reportのtestを直接実行し、推論`planned_paths`/`files_to_modify`は所有境界としてproduction pathの依存選択にのみ使う。完走receiptのFAIL 0・SKIP 0を必須とする | `skills/codd-refactor/SKILL.md`, `scripts/run_tests.sh`, `docs/research/test-suite-time-immune-asis-tobe-5w1h_20260714.md`, `tests/unit/test_codd_refactor_contract.bats` |
| CoDD/GS速度検証の参照境界 | `cmd_3948`でCoDD系SKILLのscript参照契約を再検分。2026-07-16の再検分では`run_tests.sh`のsuite wall/sum_file_sec台帳副作用を追記しつつ、mode引数・test選択・終了status契約は不変と確認した。GS共通コードの現行runnerは旧`engine.py`ではなく`/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/gs_runner.py`であり、変更前後の性能判定は`skills/gs-bench-gate/SKILL.md`に従う | `skills/codd-refactor/SKILL.md`, `skills/gs-bench-gate/SKILL.md`, commits `3370147d1`, `3dcdb914e` |
| `codd fix` | CI RED修正向け。診断推論+Session State。家老CI RED検知→`codd fix`でパッチ生成→忍者配備 | `docs/research/gunshi_codd_swebench_application_20260416.md` §2, §4-§5 |
| `codd fix [PHENOMENON]` | 「ログインエラーをわかりやすくしたい」等の観測事象から設計書・実装・テストを更新する。非対話CIでは`--non-interactive --on-ambiguity abort`を優先 | `memory/reference_codd_oshio_articles.md` |
| `elicit` / `lexicon list/install/diff` / `coverage report` | 要件穴・coverage軸・業界標準制約を正本化する。v2.x系の主入口 | `memory/reference_codd_oshio_articles.md` |
| `dag verify --auto-repair` | DAG整合性違反の修復提案または`--apply`時の機械修復。運用YAMLや共有queueには適用しない | `memory/reference_codd_oshio_articles.md` |
| `scan` / `impact` / `propagate --update` | frontmatter依存グラフから変更波及先を出し、下流docsを更新する。記事`codd-skeleton-complete`の中核 | `memory/reference_codd_oshio_articles.md` |
| `review` / `verify` / `policy` / `audit` | 品質確認を単発でなく層として回す。レビュー、整合性、方針、監査を分離する | `memory/reference_codd_oshio_articles.md` |
| `measure` | 健全性を数値で監視し、リファクタや運用劣化を感覚でなくスコアで検知する | `memory/reference_codd_oshio_articles.md` |
| `ai_command` | `codd.yaml` で generate=Opus, implement=Codex など役割別に使い分け可能 | `~/.claude/skills/codd/SKILL.md` |
| 将軍インフラ内CoDD実行パス | `scripts/check_project_codd_ready.sh` と `cmd_complete_gate.sh` のCoDD後処理は、固定ユーザー名ではなく `${HOME}/.codd-venv/bin/codd` を既定にする。Node/Codex再起動PATHも `${HOME}/.nvm/...` 参照へ寄せ、ユーザーhome直書きを避ける | commit `677d0c7f9` (`scripts/check_project_codd_ready.sh`, `scripts/cmd_complete_gate.sh`, `scripts/ninja_monitor.sh`) |

## §6 参照

- 記事#0-#5: `memory/reference_codd_oshio_articles.md`
- `cmd_2067` 深掘り: `docs/research/cmd_2067_codd5_deep_analysis.md`
- 実戦教訓: `memory/tool_codd_lessons.md`
- 軍師分析(索引): `context/gunshi-codd-analysis.md`
- 軍師分析(全文): `docs/research/gunshi_codd_swebench_application_20260416.md`
- リファクタ台帳: **PJごとに1つ。各PJリポ内に配置**
  - infra: `/home/simokitafresh/multi-agent-shogun/docs/research/codd_refactor_registry.md`
  - dm-signal: `/mnt/c/Python_app/DM-signal/docs/research/codd_refactor_registry.md`
  - **対象スクリプトが属するリポの台帳に追記せよ。別リポの台帳に書くな**
- **根源ルール: CoDDで改善したものは必ず台帳に載せる。** 対象がスクリプト/テスト/ドキュメントに関わらず例外なし(殿厳命2026-04-19, LS047)
- gate改善設計(shogun startup): [[codd_gate_shogun_startup_reimprove_20260419]]
- CoDD生成成果物(semantic_search cmd_2586): [[codd_generated_semantic_search_acceptance_cmd_2586_20260506]] / [[codd_generated_semantic_search_adr_cmd_2586_20260506]] / [[codd_generated_semantic_search_mode_dispatch_cmd_2586_20260506]] / [[codd_generated_semantic_search_system_design_cmd_2586_20260506]]
- CoDD spec: [[codd_spec_gate_workaround_rate_after_20260418]] (gate WA率改善spec) / [[codd_spec_recalculate_fast]] (fullrecalculate高速化spec)
- CoDD refactor記録(before): [[codd_refactor_cmd_quality_log_before_20260607]] (cmd_quality_log改善前の状態記録)

## 因果リンク

- → [[system-context]] CoDD extractのsystem-context（cmd_1991 extract）
- → [[oshio]] おしお殿のCoDD設計思想(systems-knowledge-base)
- 既存設計書群: `docs/test/*.md` `docs/governance/*.md` `docs/design/*.md` `docs/detailed_design/*.md` `docs/plan/*.md` `docs/operations/*.md`

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi_idle_codd_ac3_ambiguity_20260424]] — 軍師idle: CoDD AC3曖昧性分析(2026-04-24)
