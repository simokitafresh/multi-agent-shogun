---
codd:
  node_id: governance:adr-awk-replacement
  type: governance
  depends_on:
  - id: req:cmd-publish-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:cmd_publish
    reason: YAML書込みは yaml_field_set 経路維持が必須。awk 置換は読取り専用関数に限定すること。
  modules:
  - cmd_publish
---

# ADR: Python YAML parse から awk block scanner への置換判断

## 1. Overview

本 ADR は `scripts/cmd_publish.sh` 内の `count_cmd_save_blocks_for_cmd()` 関数において、Python YAML parse を awk block scanner へ置換する判断根拠・決定事項・制約を記録する。

### 背景

`count_cmd_save_blocks_for_cmd()` は pre-flight チェックのたびに `python3` プロセスを起動し、`logs/cmd_design_quality.yaml` をパースしている。`test_cmd_publish_preflight.bats` の5テストケースすべてが `cmd_publish.sh` を起動するため、Python startup コストが累積し、テストスイート全体で数百ミリ秒のオーバーヘッドが発生している。

2026-05-06 時点の実測値（kagemaru 計測、`bats tests/unit/test_cmd_publish_preflight.bats`）:

| run | elapsed |
|---|---:|
| initial | 0.779s |
| 1 | 0.658s |
| 2 | 0.698s |
| 3 | 0.714s |
| 4 | 0.625s |
| 5 | 0.692s |

missing queue fast-fail path は 0.015–0.018s であり、通常テストとの差分の大半は pre-flight 内の外部プロセス呼び出しに起因する。

### 対象モジュールと I/O プロファイル

対象: `module:cmd_publish`

| pattern | 呼び出し回数 |
|---|---:|
| `_yaml_field_get_in_block` | 2 |
| `yaml_field_set` | 3 |
| `python3` | 1 |
| `grep` | 3 |

`python3` 呼び出しは1箇所だが、テスト5ケース × pre-flight 実行で計5回の Python startup が発生する。

### リファクタリングスコープ

本 ADR が扱う置換は2件である。

**R1: `count_active_shogun_lessons()` を awk count に置換**
`grep -c '^- id:' file || echo 0` は0件時に `0\n0` を返す既知の不具合パターンを持つ。`awk '/^- id:/{n++} END{print n+0}'` に置換し、常に単一整数を返すようにする。期待効果は正確性改善であり、速度影響は小さい。

**R2: `count_cmd_save_blocks_for_cmd()` を Python YAML parse から awk block scanner に置換**
`logs/cmd_design_quality.yaml` の `entries:` 配下にある `- cmd_id: ...` エントリブロックごとに以下3フィールドを走査する:

- `cmd_id == target`（対象コマンドID）
- `gate_result == BLOCK`
- `source == cmd_save`

条件をすべて満たすブロック数をカウントする。Python startup 削減により、テスト全量で数百ミリ秒の短縮を見込む。

### 制約の適用（release-blocking）

**`module:cmd_publish` に対する YAML 書込み経路の保全:**
YAML 運用ファイルへの書込みは既存の `yaml_field_set` 経路を維持する。awk 置換は読取り専用関数（`count_cmd_save_blocks_for_cmd()` および `count_active_shogun_lessons()`）に厳密に限定し、書込み系処理には一切適用しない。`yaml_field_set` の呼び出し3箇所はすべて現行のまま残す。この制約は `cmd_publish.sh` の外部 I/O 契約を破壊しないために必須であり、違反した場合は YAML ファイルの構造破壊につながる。

追加の不変条件:

- `cmd_save.sh` 実行前に pre-flight BLOCK する実行順序を維持する。
- `on_hold` フラグは `cmd_save.sh` 成功まで保持する。
- `cmd_publish.sh` の外部 I/O 契約（入出力ファイルパス、終了コード、標準出力フォーマット）は変更しない。

## 2. Decision Log

| # | 日付 | 決定 | 根拠 | 却下した代替案 |
|---|---|---|---|---|
| D1 | 2026-05-06 | R1 を先行実装し、R2 の前にテストスイートを通す | R1 は正確性バグの修正であり、R2 の性能改善と独立している。R1 単独で回帰を検出できる状態にしてから R2 に進むことでリスクを分離する | R1・R2 同時実装（回帰原因の切り分けが困難） |
| D2 | 2026-05-06 | `count_cmd_save_blocks_for_cmd()` の Python YAML parse を awk block scanner に置換する | Python startup が pre-flight あたり約120–140ms を占め、5テスト累積で600–700ms のオーバーヘッドとなる。awk はシェル組込みに近い起動コストで同等の読取りが可能 | (a) Python を常駐デーモン化する案 — 複雑性が過大。(b) `yq` コマンド利用案 — 外部依存の追加が必要で CI 環境への導入コストがかかる。(c) 現状維持 — テスト実行速度の劣化を許容できない |
| D3 | 2026-05-06 | awk 置換は読取り専用関数に限定し、`yaml_field_set` 経路には手を加えない | YAML 書込みは構造的整合性の保証が必要であり、awk による書込みは YAML 仕様違反のリスクがある。`yaml_field_set` は既にテスト済みかつ信頼性が確立されている | awk で書込みも置換する案 — YAML マルチラインや特殊文字のエッジケースで破壊リスクがある |
| D4 | 2026-05-06 | awk block scanner は `entries:` セクション配下の YAML リストエントリを行指向で走査する設計とする | 対象 YAML ファイル（`logs/cmd_design_quality.yaml`）はインデント2スペースの固定フォーマットであり、`- cmd_id:` 行でブロック境界を検出し、ブロック内の `gate_result:` と `source:` を文字列一致で判定できる | 汎用 YAML パーサの再実装 — 過剰設計であり、対象ファイルの固定フォーマットに対して不要 |
| D5 | 2026-05-06 | R1 の `count_active_shogun_lessons()` は `awk '/^- id:/{n++} END{print n+0}'` パターンに置換する | `grep -c` + `|| echo 0` は grep がマッチ0件時に終了コード1を返し `set -e` 環境で `0\n0` 二重出力となる既知バグ。awk は常に終了コード0で単一整数を返す | `grep -c ... \|\| true` でラップする案 — 根本原因を解決せず、出力フォーマットの不安定性が残る |

### 実施順序

1. R1 実装: `count_active_shogun_lessons()` を awk count に置換
2. テスト実行: `bats tests/unit/test_cmd_publish_preflight.bats` — 全5テスト合格を確認
3. R2 実装: `count_cmd_save_blocks_for_cmd()` を awk block scanner に置換
4. テスト実行: `bats tests/unit/test_cmd_publish_preflight.bats` — 全5テスト合格を確認
5. before/after 比較: 上記実測値（0.625–0.779s）と置換後の elapsed を比較し、数百ミリ秒の短縮を検証
6. after 設計書を `docs/research/` に保存

### 検証基準

- `bats tests/unit/test_cmd_publish_preflight.bats` 全5テスト合格
- `count_cmd_save_blocks_for_cmd()` が Python プロセスを起動しないこと（`python3` 呼び出し回数が 1 → 0）
- `count_active_shogun_lessons()` が0件入力時に単一の `0` のみを標準出力に返すこと
- `yaml_field_set` の呼び出し3箇所が変更されていないこと（`grep -c 'yaml_field_set' scripts/cmd_publish.sh` が 3 を返す）
- テストスイート全体の elapsed が before 計測値（平均 0.694s）から 200ms 以上短縮されること

## 3. Follow-ups

| # | アクション | 優先度 | トリガー条件 | 担当 |
|---|---|---|---|---|
| F1 | after 計測結果を `docs/research/` に保存し、before/after 比較表を含める | 高 | R2 実装完了後、テスト合格確認直後 | 実装者 |
| F2 | `_yaml_field_get_in_block`（2箇所）の awk 置換を検討する | 中 | 本 ADR の R1・R2 完了後。ただし書込み経路（`yaml_field_set`）には波及させない | 実装者 |
| F3 | `logs/cmd_design_quality.yaml` のフォーマットが変更された場合、awk block scanner のパターンマッチを更新する | 中 | YAML フォーマット変更の PR がマージされた時点 | YAML スキーマ変更者 |
| F4 | CI パイプラインで `test_cmd_publish_preflight.bats` の実行時間を監視し、0.5s を超えた場合にアラートを出す | 低 | CI 基盤の監視設定更新時 | CI 管理者 |
| F5 | `grep` 呼び出し3箇所についても awk 統合の余地を調査する（R1・R2 の効果確認後） | 低 | after 計測で目標短縮に未達の場合 | 実装者 |
