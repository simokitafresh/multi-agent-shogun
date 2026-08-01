## 軍師レビュー効果計測（cmd_1144導入）

家老+軍師の品質管理ユニット化（cmd_1144）の効果を定量計測する。

### ベースライン（導入前）
- **GATE CLEAR率**: 直近30cmdの初回GATE CLEAR率をdashboard.mdの戦果セクションから取得
- **Re-review率**: 直近30cmdのうちFAIL→再レビューが発生したcmdの割合

### 導入後計測
- 同指標を継続計測（軍師レビュー導入後30cmd分）
- データソース: dashboard.mdの戦果セクション（完了cmd一覧+karo_workaround記録）

### 判定基準（30cmd後）
| 指標 | 判定 | 結論 |
|------|------|------|
| CLEAR率維持 + Re-review率低下 | 付加価値あり | 軍師レビュー継続 |
| CLEAR率維持 + Re-review率変化なし | 判断保留 | さらに30cmd計測 |
| CLEAR率低下 | 要見直し | 軍師レビュー観点の調整を検討 |

## PD裁定反映（cmd_354同期）

| PD | 裁定 | 反映先 |
|----|------|--------|
| PD-037 | inbox_write.sh HIGH-1(Python直接展開インジェクション)+HIGH-2(パストラバーサル)修正。殿裁定2026-02-25 | L043修正済み。`scripts/inbox_write.sh` |
| PD-038 | ashigaru.md否定指示→案C(ハイブリッド)採用。forbidden_actions構造維持+positive_rule+reason追加。ACE準拠 | `instructions/ashigaru.md` cmd_324実装済み |

## skill_gate_feedback.sh 最適化パターン（cmd_2589, 2026-05-06）

subprocess.run → Python インライン + load_skill_log キャッシュで 220ms→50ms (-77%) 達成。
→ `docs/research/cmd_2589_skill_gate_feedback_after_20260506.md`（最適化パターン+禁止パターン+計測ベースライン）

## SKILL.md品質基準（7項目チェックリスト）

スキル作成・更新時に必ず確認。発火精度はdescription品質で決まる。
- L069: スキルがsystem-reminderに検出されるにはSKILL.mdにYAMLフロントマター必須（cmd_368）
- L103: skill.md(小文字)はcase-sensitive環境で未検出→SKILL.md(大文字)に統一（cmd_438）
- L122: SKILL.md手順追加時に原則セクションとの矛盾を確認せよ（cmd_490）

| # | 項目 | 基準 | NG例 | OK例 |
|---|------|------|------|------|
| 1 | What | 具体的な出力を明記 | 「ドキュメント処理」 | 「PDFからテーブル抽出しCSV変換」 |
| 2 | When | 使用シーンを明記 | (なし) | 「gate_lesson_health.shのALERT後に使用」 |
| 3 | トリガーワード | 発火キーワードを列挙 | (なし) | 「棚卸し」「監査」「メモリ整理」 |
| 4 | 動詞の具体性 | 「管理」禁止 | 「知識を管理する」 | 「検出・更新提案・実行」 |
| 5 | 長さ | 50-200文字 | 300文字の散文 | 簡潔な1-2文 |
| 6 | 差別化 | 既存スキルとの守備範囲明示 | (なし) | 「/shogun-teireは全層監査、本スキルはMemory MCPのみ」 |
| 7 | 角括弧不使用 | description内で[X]禁止 | 「[PDF]を処理」 | 「PDFを処理」 |

### フロントマター必須フィールド
- `allowed-tools`: 使用ツール制限（未指定=全ツール利用可。意図的な場合のみ省略）
- `argument-hint`: 補完表示（例: `[project-id]`）

### オプションフィールド
- `context: fork`: サブエージェント隔離実行（メインCTX圧迫防止）
- `model`: 実行時モデル指定

### North Star
カスタムフロントマターフィールドはClaude Codeに無視される。
判断基準はMarkdown本文に記載すること。

## Diff-aware Testing 方針（GStack/GBrain #26）

**原則**: テストは変更されたファイルに関連するものを優先実行し、無関係なテストの全量実行でCTXと時間を浪費しない。

### 適用判断フロー

| 状況 | テスト範囲 | 理由 |
|------|-----------|------|
| 変更が1-3ファイルに限定 | 変更ファイルの関連テストのみ | 全量は過剰 |
| 変更が共通基盤（deploy_task.sh等）| 全テスト | 波及範囲が広い |
| CI修正 / ゲート改修 | 対象テストファイル + smoke test | 最小限で確認 |
| 本番リリース前 / cmd_complete_gate実行時 | 全テスト必須 | SKIP=FAILルール適用 |

### CI固有FAIL切り分け手順(ローカル未再現時)
1. `gh run list --limit 5` で最後のGREEN commit特定
2. `git log --oneline <GREEN>..<RED>` で間のcommit列挙
3. 各commitの`--stat`で変更ファイル確認→テストファイル変更があるcommitが最有力
4. `git ls-files -s <file>` で権限確認(100644=実行権限なし→CIでPermission denied)
5. revertで二分探索(1commitずつ)。ローカルPASSでもCI FAILする原因: git mode/bats並列/fixture共有

### WSL2固有の注意点
- `git ls-files -s` の100644/100755: WSL2 NTFSでは全ファイル755に見えるがgit indexは実権限を保持。CIはindex通りにcheckoutする
- `bash scripts/test_select.sh <file>` で間接依存テストを確認。マッピング漏れ=CI FAILの盲点

### 変更ファイルに関連するテスト特定方法
```bash
# 変更ファイルのテストを特定
git diff --name-only HEAD | while read f; do
  # 対応するbatsテストを探す
  base=$(basename "$f" .sh)
  find tests/ -name "*${base}*" -o -name "test_${base}*" 2>/dev/null
done | sort -u
```

### 制約（SKIP=FAILルール、Test Rules §1）
- **SKIP=FAIL**: Diff-aware実行でもSKIP数1以上は「テスト未完了」扱い
- **本番前は全量**: cmd_complete_gate.sh実行前・PR作成前は必ず全量テスト
- **全量前提の場合**: 呼び出し元が「全件テスト必須」と明示した場合はDiff-awareを適用しない（#26デメリット緩和策）

---

## DB guard = 語彙一致ではなく操作意図×信頼境界で判定せよ（cmd_karo_hotfix_guard14_db_trust_boundary_202607120854）

**結論**: DB直接接続を防ぐguard/hookは、特定文字列(ライブラリ名・関数名)の部分一致でBLOCKするな。
「(1)DB操作意図があるか(not_connection/connection)」×「(2)接続先信頼境界(local_ephemeral/untrusted)」
の2軸構造判定にせよ。語彙一致は必ず(a)grep/rg等の参照まで誤BLOCKする、(b)未列挙のclient/CLIを
素通りさせる、の両方が起きる。

**設計**:
- 判定は1箇所の共通分類器(`scripts/lib/guard14_db_trust_classify.py`)に集約。呼び出し元hookは
  分類結果(`not_connection`/`connection:local_ephemeral`/`connection:untrusted`)だけを見る
- connection intentの判定は特定client名(psycopg2/create_db_engine等)の列挙ではなく、構造的signal
  カテゴリで行う: DSN URLスキーム(postgres(ql)://)、DB意味を含むenv/DSN変数名(DB/DATABASE/POSTGRES/PG
  +_URL/_DSN。単なる_URL/_DSN suffixだけだとAPI_URL等まで拾う)、接続API呼出の形(`.connect(`)、
  engine factory呼出の形(`create_*engine(`)、host指定(host=)、in-memory(:memory:)、
  credential source(.env読込。それ自体が接続先を隠すsignal)
- 接続先の値はcommand全文への裸文字列一致("localhost"が無関係な別引数/別segmentにあるだけ)ではなく、
  接続runtimeを含むsegment自身のトークンからのみ構造抽出する。他segmentの文字列は一切参照しない
- セグメント分割は`shlex.shlex(posix=True, punctuation_chars=";&|")`で空白の有無に関わらず
  演算子境界(&&/||/;/|/単独&)を検出する。素朴な正規表現pre-splitはquote内の演算子文字を誤分割する
- host候補の空文字列(host=空値、URL authority欠落かつquery override無し)は「未解決」としてfail-closed
  でuntrusted扱いする。credential source segment(source builtin等)自体も接続先不明のためuntrusted
- 免除(db-check等)は自由文字列一致ではなく、実行operandのrealpathをconfig/projects.yaml(SSOT)由来の
  正規パスとsamefile同一性確認まで行う。basename一致だけでは同名の別ファイルでなりすませる
- file-backed SQLiteのread-only能力は、設定済みproject root配下へrealpath confinementできる実在file、
  literal `file:` URI、`mode=ro`、`uri=True`が全て証明できる場合だけ`local_ephemeral`として許可する。
  writable mode、動的引数、project外path、symlink escape、remote engineとの混在はfail-closedでuntrusted。

**性能**: 全Bash commandを無条件でPython classifierへ渡すとWSL2実測+29-33ms/呼び出し(baseline比
約60-77%増)で許容不能。解決策は「外側if(語彙gate)を復活させる」ではなく「共通classifier自体の
二段化」: `scripts/lib/guard14_db_trust_classify.sh`の`guard14_classify()`が唯一の入口(SSOT)。
内部でbash-nativeの保守的negative filter(`guard14_maybe_connection()`。Python側のconnection intent
判定に必要な構造的signalを1対1でミラー)を先に通し、1つも一致しなければpython3を起動せず
`not_connection`を直接返す。一致した場合のみ`python3 -S`(site初期化skip)でPython構造判定へ委譲。
fast filter/slow pathを呼び出し元hook本体へ直書きすると「hook側語彙gate+Python側intent」の
二重SSOTになるため、両方とも共有ファイル側に閉じ込める。fast filterとPython側markerの乖離
(false negative)は`tests/unit/test_pre_bash_guard14_fast_filter_sync.bats`で全connection fixtureが
slow-pathへ到達することを回帰検証する。実測: benign command E2E 48ms(元baseline)→77ms(unconditional
classify)→48-53ms(二段化後、実質回帰なし)。

**helper欠落時のfail-closed**: Python/bash両ヘルパーの欠落・実行失敗は空判定→hookのif条件が
`not_connection`/`connection:local_ephemeral`いずれとも一致しないため自動的にBLOCK側へ倒れるが、
`set -euo pipefail`下で`source`自体が失敗するとexit 1(hookエラー扱い。Codex CLIクラッシュ要因)に
なり得るため、source前に明示的な実在確認+専用BLOCKメッセージ(exit 2)を置く。

→ `scripts/lib/guard14_db_trust_classify.py` / `scripts/lib/guard14_db_trust_classify.sh` /
`.claude/hooks/pre-bash-combined.sh` Guard14 / `tests/unit/test_pre_bash_guard14_db_trust_boundary.bats` /
`tests/unit/test_pre_bash_guard14_fast_filter_sync.bats`

## 重量テストジョブのhost-wide admission契約（cmd_karo_hotfix_heavy_job_admission_202607121348）

**結論**: 同一8コアWSL2ホスト上でbats全量/pytest全量/DM-Signal golden regressionが無調停で並走すると、
OSスケジューラの強制プリエンプション(CPUオーバーサブスクリプション)でwall時間が大幅に増幅する
(実測baseline: golden単独550.82s wall/337.84s CPU、involuntary context switch 306,138件、
load average最大40.05/8コア。全量backend/tests(206ファイル)合計455.55sより単独実行の方が遅い逆転現象)。
`scripts/heavy_job_admission.sh`(flock host-wide semaphore、最大同時1実行、異常終了は自動lock解放)
経由を、`.claude/hooks/pre-bash-combined.sh` Guard17がargv位置分類器
(`scripts/lib/heavy_job_classify.{sh,py}`)で強制する。

**設計**:
- 重量判定(SSOT)はargv位置ベース: `bats`複数ファイル/全量ディレクトリ、`pytest`複数対象/ディレクトリ、
  `python(3) <golden|regression_check|fullrecalculate系スクリプト>`、`bash run_tests.sh`。単一.batsファイル
  1つ・単一`::`テスト関数指定は軽量として対象外
- heredoc本文中の"bats"/"pytest"という単語(commit message等のprose)は、GA-220と同じheredoc本文/
  terminator行除去の前処理で誤検出しない
- `scripts/run_tests.sh`は自分自身をwrapper経由でself-reexecするため、既存の`bash scripts/run_tests.sh`
  呼び出しはそのまま動作する(runner自身がadmissionを内包。Guard17はrun_tests.sh経由コマンドを除外)。
  `run_tests.sh`は`_run_tests_main()`+`"BASH_SOURCE==0"`ガードへリファクタ済みで、sourceしても
  副作用ゼロ(テストがrun_bats_files_parallel()単体を直接呼べる)
- nested呼出し(wrapper経由コマンドの内部からさらにwrapperを呼ぶ)はself-deadlockしない
  (`SHOGUN_HEAVY_JOB_LOCK_HELD=1`環境変数で二重ロック取得をスキップ)
- 実測(AC5): wrapper経由でgolden regression再計測しwall 550.82s→293.31s(-46.7%)、
  involuntary context switch 306,138→44,230(-85.6%)、verdict PASS(78/78 exact, 243,293行)維持
  (計測時host負荷が相対的に低かった交絡因子あり、純粋なadmission効果とは限らない)

**既知の限界**:
- bats-coreは`@test`ブロック内からのnested bats実行で内部通信FDが外側batsのTAP集計と衝突し、
  内側テストを実行せずexit0化することがある(env -i完全隔離+FD明示closeでも解消せず)。
  `run_bats_files_parallel()`自体の終了コード集約検証はfake bats(PATH差し替えスタブ)で
  実bats-core実行を経由せず行う(`tests/unit/test_heavy_job_admission.bats`)
- `heavy_job_classify.py`のtokenizerは`shlex.split()`ベースのため、bashの`'"'"'`クォート結合
  パターン(シングルクォート文字列内でアポストロフィを使う際の標準イディオム。Bashツールが
  コマンド文字列を再構成する過程で生成されることがある)を解釈できずfail-closedでheavyと
  誤判定することがある(GA-220のheredoc問題と同根のshlex限界)。実害はwrapper経由への誘導のみ
  (機能破損なし)。再発したらwrapper経由で回避可能

→ `scripts/heavy_job_admission.sh` / `scripts/lib/heavy_job_classify.py` / `scripts/lib/heavy_job_classify.sh` /
`scripts/run_tests.sh` / `.claude/hooks/pre-bash-combined.sh` Guard17 /
`tests/unit/test_heavy_job_admission.bats` /
`docs/research/cmd_karo_hotfix_dm_golden_standalone_timeout_20260712_findings.md`(baseline実測+host-wide admission契約による解決、multi-agent-shogun repo正本)

---

## 因果リンク

- ← [[deepdive_why_chain_20260321]] Phase 6-7: gate/hook=知性の外部化の実装先
- → [[growth-loop]] 成長ループ=インフラの設計原理
- → [[training-cycle]] 修行サイクル=インフラで駆動する忍者成長
- → [[karo-operations]] 家老運用=インフラを操作する手順
- → [[gunshi_idle_ntfy_rate_limit_global_20260516]] ntfyグローバルレート制限の分析
- → [[gunshi_idle_numbers_cold_bugfix_20260426]] numbersのコールドバグ修正: インフラバグ実例
- → [[gunshi_idle_observations_gap_analysis_20260519]] MCP observations gapの分析: 三層記憶インフラの穴
- → [[gunshi_idle_precision_fix_inbox_nudge_20260527]] inbox nudge精度修正: watcher誤検知根因
- → [[karo-direct]] 家老自立配備スキル: 将軍cmd不要の直接配備標準化
- → [[gunshi_idle_dream_gate_analysis_20260507]] dreamゲート分析: Phase設計品質検証
- → [[gunshi_idle_project_dir_false_rc_20260430]] project_dir false RC: gate判定バグの根因
- → [[gunshi_idle_recording_error_analysis_20260409]] recording error分析: lord_conversation記録失敗の根因
- → [[gunshi_idle_session_efficiency_20260503]] セッション効率分析: CTX消費ボトルネックの特定
- → [[gunshi_idle_session_nazenaze_20260519]] セッションのなぜなぜ: clear後の復旧速度問題
- → [[gunshi_idle_speed_bottleneck_nazenaze_20260602]] 速度ボトルネックのなぜなぜ: インフラ全体の遅延根因
- → [[gunshi_idle_stall_ghost_nazenaze_20260521]] STALL-GHOSTのなぜなぜ: ninja_monitor誤検知根因
- → [[gunshi_idle_state_divergence_20260603]] 状態乖離分析: karo_snapshot不整合の根因
- → [[gunshi_idle_wsl2_symlink_limitation_20260427]] WSL2シンボリックリンク制限の分析
- → [[gunshi_idle_yaml_field_set_newline_20260502]] yaml_field_set改行バグ: YAML安全書込みの問題
- → [[gunshi_idle_yaml_parse_vulnerability_20260505]] YAML parseの脆弱性分析: 運用YAML破損リスク
- → [[gunshi_idle_inbox_watcher_fp_repeat_20260602]] inbox watcher偽陽性繰り返しの根因分析
- → [[gunshi_watcher_silent_cycle_rootcause_20260425]] watcher silent cycleの根因: watcher設計の構造的問題
- → [[gunshi_startup_gate_auto_exec_bug_20260412]] startup gate自動実行バグ: gate設計の問題
- → [[gunshi_idle_semantic_audit_20260505]] セマンティック監査2026-05-05: インデックス品質評価
- → [[gunshi_idle_semantic_audit_20260509]] セマンティック監査2026-05-09: aliases品質評価
- → [[gunshi_idle_semantic_audit_20260517]] セマンティック監査2026-05-17: aliases漏れの検出
- → [[gunshi_idle_semantic_audit_20260519b]] セマンティック監査2026-05-19b: 品質精度の再測定
- → [[gunshi_idle_semantic_audit_20260521]] セマンティック監査2026-05-21: 改善効果の検証
- → [[gunshi_idle_semantic_audit_causal_nw_20260518]] セマンティック監査+因果NW統合: 三層記憶の接続品質
- → [[gunshi_idle_semantic_audit_cmd2681_2684_20260512]] cmd2681/2684のセマンティック監査: aliases注入効果
- → [[gunshi_idle_semantic_audit_daemon_watcher_20260530]] daemon_watcherのセマンティック監査
- → [[gunshi_idle_semantic_audit_infra_bugs_20260525]] インフラバグのセマンティック監査: 概念接続の穴
- → [[gunshi_idle_semantic_audit_post_backup_first_20260519]] backup_first後のセマンティック監査
- → [[gunshi_idle_semantic_audit_scripts_20260529]] スクリプトのセマンティック監査: 索引品質向上
- → [[gunshi_idle_semantic_audit_skill_scripts_20260506]] スキルスクリプトのセマンティック監査
- → [[gunshi_idle_semantic_index_gap_20260515]] セマンティックインデックスgap分析: 未カバー概念の特定
- → [[gunshi_semantic_audit_catalog_design_20260503]] セマンティック監査カタログ設計: 監査の標準化
- → [[gunshi_semantic_audit_cmd2621_20260510]] cmd2621のセマンティック監査結果
- → [[gunshi_semantic_audit_cmd2635_20260510]] cmd2635のセマンティック監査結果
- → [[gunshi_staleness_audit_20260510]] 陳腐化監査: コンテキストファイルの鮮度評価
- → [[cmd_karo_reprofile_bench_20260426]] 家老CTXプロファイリングベンチマーク(2026-04-26: bottleneck特定)
- → [[cmd_karo_reprofile_freq_20260426]] 家老CTXプロファイリング頻度分析(2026-04-26: 頻度別コスト)
- → [[multinode_portable_environment_20260609]] マルチノードポータブル環境設計(2026-06-09: 可搬性向上)
- → [[rollback_english_design_20260422]] ロールバック英語版設計(2026-04-22: 英語対応設計書)
- → [[language_policy_design_20260421]] 言語ポリシー設計(2026-04-21: 日英混在ルール策定)
- → [[statistical-wheels-for-quality]] 品質のための統計的車輪原則(車輪の再発明禁止+既存計測活用)
- → [[three_layer_memory_first_priority_design_20260606]] 三層記憶ファーストプライオリティ設計(2026-06-06: 検索順序強制)
- → [[cmd_316_rate_limit_analysis]] APIレート制限分析(cmd_316)
- → [[cmd_316_rate_limit_consumption]] APIレート制限消費分析(cmd_316)
- → [[cmd_317_config_dir_codex]] Codex設定ディレクトリ調査(cmd_317)
- → [[cmd_317_config_dir_opus]] Opus設定ディレクトリ調査(cmd_317)
- → [[cmd_317_config_dir_sonnet]] Sonnet設定ディレクトリ調査(cmd_317)
- → [[cmd_317v2_model_comparison]] モデル比較実験(cmd_317v2)
- → [[cmd_319_oss_preparation]] OSS公開準備(cmd_319)
- → [[cmd_344_knowledge_metrics_design]] 知識メトリクス設計(cmd_344)
- → [[cmd_504_qiita-idea-council]] Qiita記事アイデア会議(cmd_504)
- → [[cmd_506_hermit-technical-recon]] 仙人技術偵察(cmd_506)
- → [[cmd_508_screenshot-paste-recon]] スクリーンショット貼付偵察(cmd_508)
- → [[cmd_798_ndlocr-lite]] NDLOCR-Lite調査(cmd_798)
- → [[cmd_888_self-healing-patterns]] 自己修復パターン分析(cmd_888)
- → [[cmd_2087_codd_spec_ntfy_20260418]] ntfy CoDD仕様書(cmd_2087)
- → [[cmd_2108_deploy_task_template_generation_profile]] テンプレート生成プロファイル(cmd_2108)
- → [[cmd_2109_gate_shogun_startup_test_profiling]] startup gateテストプロファイル(cmd_2109)
- → [[cmd_2110_report-template-gate-compat-setup-profile]] レポートテンプレートgateプロファイル(cmd_2110a)
- → [[cmd_2110_test_report_template_gate_profiling]] レポートテンプレートgateプロファイル(cmd_2110b)
- → [[cmd_2112_test_deploy_task_lifecycle_profiling]] deploy_taskライフサイクルプロファイル(cmd_2112)
- → [[cmd_2113_cli_adapter_setup_profile]] CLIアダプタセットアッププロファイル(cmd_2113)
- → [[cmd_2115_test_cmd_save_profile]] cmd_saveテストプロファイル(cmd_2115)
- → [[cmd_2116_test_build_system_profiling]] ビルドシステムプロファイル(cmd_2116)
- → [[cmd_2126_mizchi_red_flags_skip_reasons_20260419]] mizchi red flags調査(cmd_2126)
- → [[cmd_3005_document_inventory_kagemaru]] ドキュメントインベントリ(cmd_3005)
- → [[adoption-log]] 知識採用ログ(systems-knowledge-base/our-army)
- → [[claude-code]] Claude Code知識ベース(systems-knowledge-base)
- → [[our-army]] 我ら軍の知識ベース(systems-knowledge-base)
- → [[vercel]] Vercel設計原則(systems-knowledge-base)
- → [[mizchi]] mizchi記事知識ベース(systems-knowledge-base)
- → [[gyakusegawa]] 逆瀬川記事知識ベース(systems-knowledge-base)
- → [[dm-signal]] DM-Signal=インフラが支えるPJ

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi_idle_infra_bug_audit_20260409]] — 軍師idle: インフラバグ監査(2026-04-09)
- [[gunshi_idle_infra_bugs_full_audit_20260424]] — 軍師idle: インフラバグ全量監査(2026-04-24)
- [[gunshi_idle_infra_health_20260425]] — 軍師idle: インフラ健全性レポート(2026-04-25)
- [[gunshi_idle_infra_bug_universal_commit_20260430]] — 軍師idle: インフラバグ汎用コミット対策(2026-04-30)
- [[gunshi_idle_infra_bug_trio_20260502]] — 軍師idle: インフラバグトリオ分析(2026-05-02)
- [[gunshi_idle_infra_bug_trio_fix_20260503]] — 軍師idle: インフラバグトリオ修正(2026-05-03)
- [[gunshi_idle_infra_speed_hidden_bugs_20260605]] — 軍師idle: インフラ速度の隠れバグ(2026-06-05)
- [[gunshi_idle_clear_durability_nazenaze_20260515]] — 軍師idle: /clear耐久性なぜなぜ分析(2026-05-15)
- [[gunshi_idle_clear_durability_flag_gap_20260515]] — 軍師idle: /clear耐久性フラグギャップ(2026-05-15)
- [[gunshi_idle_clear_durability_nazenaze_20260515d]] — 軍師idle: /clear耐久性なぜなぜ分析(続)(2026-05-15)
- [[gunshi_idle_clear_durability_fix_20260516]] — 軍師idle: /clear耐久性修正(2026-05-16)
- [[gunshi_idle_clear_respawn_bug_20260607]] — 軍師idle: /clear respawnバグ分析(2026-06-07)
- [[gunshi_idle_deploy_yaml_parse_error_20260516]] — 軍師idle: 配備YAMLパースエラー(2026-05-16)
- [[gunshi_idle_deploy_structural_bugs_20260517]] — 軍師idle: 配備構造バグ分析(2026-05-17)
- [[gunshi_idle_direct_mode_stale_ac_20260502]] — 軍師idle: ダイレクトモード古いAC問題(2026-05-02)
- [[gunshi_idle_gitignore_wa_20260409]] — 軍師idle: .gitignore WAパターン(2026-04-09)
- [[gunshi_idle_autocommit_scope_leak_20260602]] — 軍師idle: 自動コミットスコープ漏洩(2026-06-02)
- [[gunshi_idle_dashboard_corruption_20260603]] — 軍師idle: ダッシュボード破損分析(2026-06-03)
- [[gunshi_idle_codex_commit_missing_20260413]] — 軍師idle: Codexコミット欠落分析(2026-04-13)
- [[gunshi_idle_codex_respawn_loop_20260516]] — 軍師idle: Codex respawnループ分析(2026-05-16)
- [[gunshi_idle_codex_respawn_loop_nazenaze_20260520]] — 軍師idle: Codex respawnループなぜなぜ(2026-05-20)
- [[gunshi_codex_clear_judgment_20260422]] — 軍師分析: Codex clear判断基準(2026-04-22)
- → [[cdp-browse]] CDPブラウザ自動化スキル（persistent daemon + AXTree操作）
- → [[reset-layout]] tmuxペイン配置復元スキル（agentsウィンドウ一発復元）
- → [[shogun-all-codex-switch]] 全忍者Codex一括切替スキル（Claude→Codex全員切替）
- → [[shogun-peacetime-rollback]] Codex→Claude平時ロールバックスキル
- → [[shogun-cli-switch]] 個別エージェントCodex切替スキル
- → [[shogun-cli-switch]] 個別エージェントOpus CLI切替スキル
- → [[switch-project]] プロジェクト切替スキル（current_project変更）
- → [[hensei-mixed]] 混成編成切替スキル（GPT+Sonnet+Opus混成）
- → [[hensei-opus]] Opus統一編成スキル（決戦モード全忍者Opus化）

