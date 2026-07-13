# cmd_3874: lock_path()ドメイン統一 — 二系統lock不整合の棚卸しと対処

## §1 背景

2026-07-13 14:27-28、`queue/insights.yaml`が並行書込みで全損した(ヘッダ喪失+エントリ消失、corrupt退避4本、将軍が退避から全件復元)。
真因は「同一ファイルへの書き手が異なるロックファイルを取得し、排他が成立しない」こと。cmd_3874はこの直接原因(AC1)への対処と、
scripts配下全体での同種不整合の横断棚卸し+対処(AC2)を目的とする。

## §2 発見した不整合

### 2.1 queue/insights.yaml (直接の事故原因)

| 書き手 | 修正前のロック方式 |
|--------|------|
| `scripts/insight_write.sh` (追記/--resolve双方) | 隣接`.lock`: `$INSIGHTS_FILE.lock` |
| `scripts/insight_resolve.sh` | `yaml_field_set()`関数経由 → `scripts/lib/yaml_field_set.sh`内蔵の独自`lock_path()` |
| `scripts/gates/gate_shogun_startup.sh` (insights自動アーカイブ) | 隣接`.lock`: `${INSIGHTS_FILE}.lock`(insight_write.shとの同一lock依存をコメントで明記) |

`insight_write.sh`(隣接.lock)と`insight_resolve.sh`(yaml_field_set()内蔵ロジック)は、当時から**異なるロックファイル**を取得していた。
これが2026-07-13の全損事故の直接原因。

### 2.2 queue/tasks/{ninja}.yaml (より深刻な潜在事故要因、棚卸しで新規発見)

| 書き手 | ロック方式 |
|--------|------|
| `scripts/cmd_complete_gate.sh` (task idle化等) | 正本`scripts/lib/lock_path.sh`を直接source |
| `scripts/ninja_monitor.sh` (status更新、report_path clear等、10箇所超) | `yaml_field_set()`関数経由 |
| `scripts/deploy_task.sh` (task_id注入、AC注入等、多数箇所) | `yaml_field_set()`/`yaml_field_set_batch()`関数経由 |

実証(修正前):
```
$ source scripts/lib/lock_path.sh; lock_path "/mnt/c/tools/multi-agent-shogun/queue/tasks/saizo.yaml"
/tmp/shogun_lock_e7555141109944ab.lock

$ source scripts/lib/yaml_field_set.sh; lock_path "/mnt/c/tools/multi-agent-shogun/queue/tasks/saizo.yaml"
/tmp/shogun_lock__tools_multi-agent-shogun_queue_tasks_saizo_yaml.lock
```
同一ファイルパスに対し完全に異なるロックファイルが生成されていた。`queue/tasks/*.yaml`は忍者の状態管理の中核であり、
`cmd_complete_gate.sh`(正本lock_path.sh経由)と`ninja_monitor.sh`/`deploy_task.sh`(yaml_field_set()経由)が同時に同じtask_fileへ
書き込むと排他が成立しない — insights.yaml事故と同型かつ、トラフィックの多さゆえより高頻度に発火しうる潜在的事故要因だった。

### 2.3 根本原因: lock_path()という名前の実装が2つ存在していた

`scripts/lib/lock_path.sh`(正本、多数のスクリプトがsource)と`scripts/lib/yaml_field_set.sh`内蔵の`lock_path()`(独自実装、
「Inline lock_path helper to avoid sourcing another file on the hot path」というコメント付きで意図的に複製)が、`/mnt/c/*|/mnt/d/*`
パスに対して異なるハッシュアルゴリズムを使っていた:

- 正本: 純bash DJB2ハッシュ → `/tmp/shogun_lock_%016x.lock`
- yaml_field_set.sh内蔵版: サニタイズ文字列末尾48文字 → `/tmp/shogun_lock_%s.lock`

しかも`yaml_field_set.sh`内では、この独自ロジックが**3箇所**(トップレベル`lock_path()`関数、`yaml_field_set()`関数内インライン、
`yaml_field_set_batch()`関数内インライン)に重複していた。`/tmp`配下等の非`/mnt/c`パスでは両実装とも`${file}.lock`に収束するため、
このテスト環境(常に`/tmp`配下)では不一致が顕在化しない — 本番環境(`/mnt/c/tools/multi-agent-shogun/...`)でのみ発火する類の不整合であり、
発見が遅れやすい構造だった。

### 2.4 queue/pending_decisions.yaml

| 書き手 | 修正前のロック方式 |
|--------|------|
| `scripts/pending_decision_write.sh` | 隣接`.lock`: `${DATA_FILE}.lock` (`queue/pending_decisions.yaml.lock`) |
| `scripts/archive_completed.sh` (`archive_pending_decisions_for_cmd_locked`) | ハードコード固定名: `/tmp/mas-pending-decisions.lock` |

両者とも`lock_path()`を経由しない独自命名で、同一ファイルに対し異なるロックパスを使用していた。

## §3 対処内容(実施済み)

| # | 対象 | 変更 | 検証 |
|---|------|------|------|
| 1 | `scripts/insight_write.sh` | `scripts/lib/yaml_field_set.sh`をsourceし、2箇所のロック取得(追記/--resolve)を`$(lock_path "$INSIGHTS_FILE")`経由に統一 | `tests/unit/test_insight_write.bats` 27/27 PASS。並行排他の新規回帰テスト追加(insight_write x20 + yaml_field_set x5 同時実行、35試行中0件データ損失。旧実装は15試行中5件損失を実証した上で修正版と対比) |
| 2 | `scripts/lib/yaml_field_set.sh` | トップレベル`lock_path()`と`yaml_field_set()`/`yaml_field_set_batch()`内の重複インラインロジック(2箇所)を正本`scripts/lib/lock_path.sh`と完全同一のDJB2ハッシュへ統一。関数呼び出し化により3箇所の実装重複を解消 | `tests/unit/test_yaml_field_set.bats` 43/43 PASS、`tests/unit/test_lesson_lock_path.bats` 3/3 PASS。正本との出力一致を実測で確認(`/mnt/c/.../queue/tasks/saizo.yaml`で同一ハッシュ生成を確認) |
| 3 | `scripts/gates/gate_shogun_startup.sh` | insights自動アーカイブブロックのロックを`${INSIGHTS_FILE}.lock`(隣接)から`$(lock_path "$INSIGHTS_FILE")`へ変更(#1修正によりinsight_write.shとの同一lock依存が崩れるため) | `tests/unit/test_gate_shogun_startup.bats`: 91件中67 PASS/24 FAIL。**FAILは修正前(HEAD版)でも完全同一の91件中67 PASS/24 FAIL(同一テスト名リスト)** — 私の変更によるregressionは0件と実測確認済み。24件は全て本セッション以前からの既存問題(環境依存のdisk残量計測失敗等) |
| 4 | `scripts/archive_completed.sh` | `archive_pending_decisions_for_cmd_locked()`のロックを固定名`/tmp/mas-pending-decisions*.lock`から`$(lock_path "$PENDING_DECISIONS_FILE")`/`$(lock_path "$PENDING_DECISIONS_ARCHIVE")`へ変更。`scripts/lib/lock_path.sh`をsource追加 | `tests/unit/test_archive_completed.bats` 25/25 PASS(3回連続)。テストフィクスチャ`setup_file()`に`lock_path.sh`のsymlinkを追加(fixture更新漏れで一時的に25件中23件が実行時FAILしたが、fixture修正で解消。原因は本番実行ではなくテスト環境の依存ファイル欠落) |

## §4 対象外と判断した箇所(根拠付き)

`scripts/archive_completed.sh`内には他に3種の固定名ロックが残存する:

| ロック名 | 対象ファイル | 対象外理由 |
|----------|-------------|-------------|
| `/tmp/mas-chronicle.lock` | `context/cmd-chronicle.md` | `.md`ファイルでありCLAUDE.mdのYAML安全書込み対象外(queue/tasks/inbox/reports/shogun_to_karo/karo_snapshot)。他の書き手の有無は今回未調査 |
| `/tmp/mas-dashboard.lock` | `dashboard.md` | 同上。`.md`ファイル |
| `/tmp/mas-stk.lock` | `queue/shogun_to_karo.yaml` | CLAUDE.mdの安全書込み対象に該当する重要YAML。`cmd_save.sh`等、他の書き手の具体的ロック機構の完全特定に追加調査を要するため今回は見送り。**要継続調査**(次点候補) |

いずれも今回のcmd_3874スコープ(AC1直接原因+実証済み最重要派生問題)には含まれず、対処すると影響範囲が広がりすぎるため見送った。
`mas-stk`(shogun_to_karo.yaml)は運用上の重要度が高いため、別cmdでの継続調査を推奨する。

## §5 結論

`scripts/lib/yaml_field_set.sh`内の独自`lock_path()`実装を正本`scripts/lib/lock_path.sh`と統一したことで、`yaml_field_set()`/
`yaml_field_set_batch()`を経由する**全ての**書き込み元(cmd_complete_gate.sh, ninja_monitor.sh, deploy_task.sh, lesson_write*.sh,
insight_resolve.sh等、数十スクリプト)が、正本`lock_path.sh`を直接sourceする書き手と自動的に整合するようになった。これは
insights.yaml単体の修正(AC1)を大きく超える範囲の根治であり、`queue/tasks/*.yaml`という高トラフィックな運用ファイルに存在していた
より深刻な潜在的事故要因を、insights.yaml事故の発覚前に予防的に解消した。

今後の同種gate/hook設計では、「ロック計算ロジックを複数箇所に複製しない」「同名関数`lock_path()`は必ず単一の正本を指す」を
既定とすべき。詳細な運用ルールは`context/infrastructure.md`へ還流する。
