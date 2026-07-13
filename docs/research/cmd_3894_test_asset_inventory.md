# cmd_3894 テスト資産・既存車輪 静的棚卸し

日時: 2026-07-14 / 方法: `rg`・AST相当の構文パターン走査・`git log`・行番号付き現物読取のみ。Bats/Pytest実行は0回。

## §1 材料（一次情報）

|対象|現物・行|材料|
|---|---|---|
|時間台帳|`scripts/gates/gate_test_health.sh:20-105`|`--timing`時だけ全Batsを直列実行し台帳を上書き。通常経路は既存台帳を読むだけ。|
|台帳停止根因|`scripts/gates/gate_test_health.sh:26-30,44-67`; `git log -S test_timing_ledger`|writerは手動`--timing`経路1本だけで、CI・`run_tests.sh`からの呼出しなし。台帳末尾は2026-06-05世代、現行317 filesに対し旧行群でfailも残る。定期writer不在がstale根因。|
|現行runner|`scripts/run_tests.sh:15-24,41-61,64-230,240-287`|host-wide job cap=8、pass cache、source/file fingerprint、全実行に`--timing`はあるが結果を台帳へ永続化しない。|
|影響test選択|`scripts/test_select.sh:36-83,99-323`|命名・source解析・対象別mappingの既存3層車輪。未知対象はWARN後skipで、D7統合先として再利用可能。|
|CoDD台帳|`docs/research/codd_refactor_registry.md`|改善済み対象・phase・before/afterの既存SSOT。時間台帳とは用途分離し、P2候補の重複改善除外に利用。|
|test作成契約|`scripts/cmd_save.sh:6440-6491`|`check_ac_test_scope`が広すぎる全量test ACを検出。D7の入口契約へ統合候補。|
|レビュー契約|`instructions/generated/codex-gunshi.md:135-151`|fixture前提、非test caller、全入力modeを要求。D7のreview列へ統合候補。|
|pre-commit選択|`scripts/test_select.sh:3-14`; `tests/unit/test_pre_push_hook.bats`|変更影響選択の既存車輪あり。新selectorを作らずD7から呼ぶ。|
|coverage道具|repo全域静的検索|Bats: branch/contract/mutation専用計測器なし。利用可能な二値手段は各分岐fixtureのPASS/FAILとshell coverage導入可否判定。Pytest: pytest系fixtureはあるがbranch/mutation専用設定を現物で確認できず、`pytest-cov --cov-branch`/mutation tool導入有無をP1でdependency inventory化する。contractは既存の契約test名・negative fixtureを二値手段とする。|

## §2 静的スキャン材料

|母集団|件数|所見ではない材料|
|---|---:|---|
|infra Bats|317 files / 4,231 `@test`|現行tree（worktree複製除外）。|
|実時間待ち候補|47 files|`sleep`/timeout/wait系文字列を含むBats。|
|mock/test-double候補|72 files|mock/stub/fake/patch系文字列。4類型は (A)command shim/PATH差替え (B)env・file fixture (C)process/tmux fake (D)network/DB boundary double。|
|共有資源候補|248 files|DB/port/file/env/global cache関連文字列。catalog keyは resource_type, identity, owner, isolation, cleanup, parallel_safe。|
|同名候補|静的抽出あり|`gate_test_health.sh:111-126`の既存抽出器を再利用。今回の粗い文字列走査値は引用除去前なので設計値には採用しない。|
|統合候補|87 files|`@test` 5件以下。単純統合せずfixture/対象script/実行時間でクラスタ化する。|
|DM-Signal pytest|212 files|backend読取値。既報1810 tests/208 filesとの差は時点・探索root差として分離し、P1ではcommit SHA/rootを必須列にする。|
|DM実時間待ち候補|4 files|`sleep`系静的候補。|
|DM double候補|117 files|monkeypatch/mock/patch/fake静的候補。|
|DM共有資源候補|112 files|DB/port/cache/tempfile静的候補。|

陳腐化候補の二値化は `referenced_path_exists`、`production_symbol_exists`、`last_target_change_sha`、`spec_status` の4列で行う。コメントだけの「古そう」は候補にしない。

## §3 所見（材料から分離）

1. P1台帳schema: `run_id, repo, commit_sha, suite_root, runner, test_file, test_id_count, wall_sec, status, skip_count, cache_hit, source_fingerprint, measured_at, resource_tags`。writerは`run_tests.sh`の既存`--timing`出力を一度だけ収集しatomic更新する。
2. P2道具磨きtop: (1) timing永続化をrunnerへ統合 (2) cache fingerprintへunstaged差分を含める (3) `test_select.sh`未知skipの可視化。新runner/selectorは作らない。
3. P3 budget材料: 現台帳の分布はstaleゆえ閾値決定に使わない。P1再計測後にp50/p90/p95/max、cache hit/miss別、resource tag別で固定する。
4. 統合淘汰優先度: ≤5 testsの87 filesを第一母集団とし、同一fixture+同一target+高固定費の順。参照消失/production symbol消失は削除候補、単なる古い日付は非候補。
5. mock規律: 4類型catalogごとに「何を隔離したか」と「実境界を最低1本検証したか」を必須化。double数の多寡だけで良否判定しない。

## §4 テスト実行ゼロ証跡

本作業の実行コマンドは読取・検索・行数集計・git履歴確認・文書編集のみ。`bats ...`、`pytest ...`、`scripts/run_tests.sh ...`、`gate_test_health.sh --timing` の実行は0回。文書存在/非空はファイルサイズで確認する。
