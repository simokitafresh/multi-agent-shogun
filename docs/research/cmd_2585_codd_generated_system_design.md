---
codd:
  node_id: design:system-design
  type: design
  depends_on:
  - id: test:acceptance-criteria
    relation: constrained_by
    semantic: governance
  - id: governance:adr-awk-replacement
    relation: constrained_by
    semantic: governance
  depended_by:
  - id: detailed_design:preflight-sequence
    relation: depends_on
    semantic: technical
  - id: detailed_design:awk-block-scanner
    relation: depends_on
    semantic: technical
  conventions:
  - targets:
    - module:cmd_publish
    - module:cmd_save
    reason: cmd_save.sh 実行前の pre-flight BLOCK 順序と on_hold ライフサイクルをシステム設計に明示すること。順序逆転はリリース不可。
  - targets:
    - module:cmd_publish
    reason: 外部I/O契約（入出力ファイルパス・終了コード・標準出力フォーマット）の変更禁止。
  modules:
  - cmd_publish
  - cmd_save
  - preflight
---

# システム設計概要

## 1. Overview

本設計書は `scripts/cmd_publish.sh` のリファクタリング（R1: `count_active_shogun_lessons()` awk 置換、R2: `count_cmd_save_blocks_for_cmd()` awk block scanner 置換）に関するシステム設計を定義する。対象モジュールは `module:cmd_publish` および `module:cmd_save` である。

### 1.1 リファクタリングスコープ

| ID | 対象関数 | 変更内容 | 目的 |
|---|---|---|---|
| R1 | `count_active_shogun_lessons()` | `grep -c` パターンを `awk '/^- id:/{n++} END{print n+0}'` に置換 | 0件時の `0\n0` 二重出力バグの根本修正。`grep -c` は0件マッチで終了コード1を返し、`set -e` 環境下で `|| echo 0` との組合せが二重出力を引き起こす |
| R2 | `count_cmd_save_blocks_for_cmd()` | Python YAML parse を awk block scanner に置換 | Python startup コスト（pre-flight あたり約120–140ms、テスト5ケース累積で600–700ms）の排除 |

### 1.2 対象モジュール

| モジュール | ファイル | 役割 | 変更有無 |
|---|---|---|---|
| `module:cmd_publish` | `scripts/cmd_publish.sh` | pre-flight チェック実行・YAML 読取り・`cmd_save.sh` 呼出し制御 | R1・R2 による関数置換あり |
| `module:cmd_save` | `scripts/cmd_save.sh` | コマンド保存処理の実行 | 変更なし（pre-flight BLOCK 順序・`on_hold` 保持の検証対象） |

### 1.3 リリース不可制約（Non-Negotiable Constraints）

以下の4制約はすべてリリースブロッキングであり、本設計の全セクションで明示的に遵守する。

**制約 C1 — 外部 I/O 契約の凍結（`module:cmd_publish` 対象）:**
`cmd_publish.sh` の外部 I/O 契約（入出力ファイルパス・終了コード・標準出力フォーマット）はリファクタリング前後で同一でなければならない。読取り対象ファイル一覧、書込み対象ファイル一覧、各 pre-flight チェックの stdout 出力形式、各 pre-flight チェックの exit code が変化した場合はリリース不可とする。本制約は受入基準 AC-07 および失敗基準 FC-03 により検証される。

**制約 C2 — pre-flight BLOCK 順序の維持（`module:cmd_publish`, `module:cmd_save` 対象）:**
`cmd_save.sh` 実行前に pre-flight チェックが BLOCK を返す順序を保持する。BLOCK 判定が完了する前に `cmd_save.sh` が実行される順序逆転はリリース不可とする。BLOCK 条件成立時には `cmd_save.sh` は呼び出されない。本制約は AC-08 および FC-04 により検証される。

**制約 C3 — `on_hold` ライフサイクルの保全（`module:cmd_publish`, `module:cmd_save` 対象）:**
`on_hold` 状態は `cmd_save.sh` が成功を返すまで解除されない。`cmd_save.sh` 成功前に `on_hold` が解除された場合はリリース不可とする。本制約は AC-09 および FC-05 により検証される。

**制約 C4 — YAML 書込み経路の限定（`module:cmd_publish` 対象）:**
YAML 運用ファイル（`logs/cmd_design_quality.yaml` 等）への書込みは既存 `yaml_field_set` 関数経由のみ許可する。awk 置換は読取り専用関数（`count_active_shogun_lessons()` および `count_cmd_save_blocks_for_cmd()`）に厳密に限定する。`yaml_field_set` の呼び出し3箇所はすべて現行のまま残す。リダイレクト（`>`, `>>`）、`sed -i`、awk 直接書込み、`tee` 等による `.yaml` ファイルへの書込みが検出された場合はリリース不可とする。本制約は AC-10 および FC-06 により検証される。

### 1.4 性能目標

| メトリクス | ベースライン | 目標値 | 検証方法 |
|---|---|---|---|
| テストスイート全量平均実行時間 | 0.694s（5回計測: 0.658s, 0.698s, 0.714s, 0.625s, 0.692s） | 0.694s 未満 | `time bats tests/unit/test_cmd_publish_preflight.bats` を5回以上計測し平均を算出 |
| テストスイート全量短縮幅 | — | 200ms 以上短縮 | before/after の平均差分 |
| missing queue fast-fail path | 0.015–0.018s | 0.020s 以下 | fast-fail 条件のテストフィクスチャで計測 |
| `python3` 起動回数 | 1（テスト実行あたり5回累積） | 0 | `strace -f -e execve` または `grep -n 'python3'` による確認 |

---

## 2. Architecture

### 2.1 実行フローの全体像

`cmd_publish.sh` の実行フローは以下の3フェーズで構成される。リファクタリングはフェーズ1の内部実装のみを変更し、フェーズ間のインターフェースは不変である。

```
フェーズ1: Pre-flight チェック
  ├── count_active_shogun_lessons()    ← R1: awk count に置換
  ├── count_cmd_save_blocks_for_cmd()  ← R2: awk block scanner に置換
  └── 判定: BLOCK / PASS

フェーズ2: 条件分岐
  ├── BLOCK → cmd_save.sh を呼び出さずに終了（on_hold 維持）
  └── PASS  → フェーズ3 へ

フェーズ3: コマンド保存
  ├── cmd_save.sh 実行
  └── 成功時: on_hold 解除
```

**制約 C2 の反映:** フェーズ1（pre-flight チェック）の BLOCK 判定は必ずフェーズ3（`cmd_save.sh` 実行）より先に完了する。BLOCK 判定が出た場合、フェーズ3 には遷移しない。この順序は不変であり、逆転した場合はリリース不可とする。

**制約 C3 の反映:** `on_hold` 状態はフェーズ1 開始前に設定され、フェーズ3 の `cmd_save.sh` が正常終了（exit code 0）した場合にのみ解除される。フェーズ2 で BLOCK 分岐した場合は `on_hold` が維持されたまま終了する。

### 2.2 I/O プロファイルと契約

**制約 C1 の反映:** 以下の I/O 契約はリファクタリング前後で完全に同一である。

#### 読取り対象ファイル

| ファイル | 読取り元関数 | 置換対象 |
|---|---|---|
| `shogun_lessons` ファイル（`- id:` 行を含む） | `count_active_shogun_lessons()` | R1: `grep -c` → `awk` |
| `logs/cmd_design_quality.yaml`（`entries:` セクション） | `count_cmd_save_blocks_for_cmd()` | R2: `python3` → `awk` |

#### 書込み対象ファイル

| ファイル | 書込み手段 | 呼出し回数 | 置換対象 |
|---|---|---|---|
| `logs/cmd_design_quality.yaml` 等 | `yaml_field_set` | 3回 | 変更なし |

**制約 C4 の反映:** 書込みは `yaml_field_set` の3箇所のみであり、awk やリダイレクト等の代替書込み手段は使用しない。`grep -c 'yaml_field_set' scripts/cmd_publish.sh` の結果が3であることを検証する。

#### 標準出力フォーマット

| 関数 | 出力形式 | exit code |
|---|---|---|
| `count_active_shogun_lessons()` | 単一整数値（改行1つ）。0件時は `0` のみ | 常に 0 |
| `count_cmd_save_blocks_for_cmd()` | 単一整数値（改行1つ） | 常に 0 |
| pre-flight チェック全体 | リファクタリング前後で diff 差分なし | 同一条件で同一値 |

### 2.3 R1: `count_active_shogun_lessons()` の awk 置換

#### Before（現行実装）

```bash
grep -c '^- id:' "$file" || echo 0
```

問題: `grep -c` は0件マッチ時に終了コード1を返す。`set -e` 環境下で `|| echo 0` が実行され、grep の出力 `0` と echo の出力 `0` が連結して `0\n0` となる。

#### After（置換後）

```bash
awk '/^- id:/{n++} END{print n+0}' "$file"
```

awk は常に終了コード0で終了し、`END` ブロックで `n+0` を出力することで0件時も単一の `0` を返す。

#### 検証ポイント

- 出力が `^[0-9]+$` にマッチし、`wc -l` が1であること（AC-01）
- 0件入力時に文字列 `"0"` と完全一致すること（AC-02）
- `0\n0` パターンが再現しないこと（FC-07）

### 2.4 R2: `count_cmd_save_blocks_for_cmd()` の awk block scanner 置換

#### Before（現行実装）

```bash
python3 -c "import yaml; ..." logs/cmd_design_quality.yaml
```

Python startup コストが pre-flight 実行ごとに約120–140ms 発生する。

#### After（awk block scanner 設計）

`logs/cmd_design_quality.yaml` は固定フォーマット（インデント2スペース）であり、以下の行指向走査で処理する:

1. `entries:` セクションの開始を検出する
2. `- cmd_id:` 行でブロック境界を検出し、新規ブロックの走査を開始する
3. ブロック内で以下の3フィールドを文字列一致で判定する:
   - `cmd_id` が引数 `target` と一致するか
   - `gate_result` が `BLOCK` と一致するか
   - `source` が `cmd_save` と一致するか
4. 3条件すべてを満たすブロック数をカウントし、`END` ブロックで出力する

#### 対象 YAML 構造

```yaml
entries:
  - cmd_id: <target>
    gate_result: BLOCK
    source: cmd_save
  - cmd_id: <other>
    gate_result: PASS
    source: other_source
```

#### 検証ポイント

- `python3` プロセスが `count_cmd_save_blocks_for_cmd()` 経路で起動しないこと（AC-06, FC-02）
- 0件 / 1件 / 複数件マッチで正確なカウントを返すこと（AC-05, FC-09）
- `gate_result == PASS` のエントリが除外されること（AC-04）
- `source != cmd_save` のエントリが除外されること（AC-04）
- `cmd_id != target` のエントリが除外されること（AC-04）

### 2.5 実施順序

ADR D1 の決定に基づき、以下の順序で実施する。R1 と R2 を独立させることで回帰原因の切り分けを可能にする。

| ステップ | 内容 | 合格基準 |
|---|---|---|
| 1 | R1 実装: `count_active_shogun_lessons()` を awk count に置換 | `bash -n scripts/cmd_publish.sh` で構文チェック通過 |
| 2 | テスト実行 | `bats tests/unit/test_cmd_publish_preflight.bats` 全5テスト PASS |
| 3 | R2 実装: `count_cmd_save_blocks_for_cmd()` を awk block scanner に置換 | `bash -n scripts/cmd_publish.sh` で構文チェック通過 |
| 4 | テスト実行 | `bats tests/unit/test_cmd_publish_preflight.bats` 全5テスト PASS |
| 5 | before/after 性能比較 | 平均実行時間が 0.694s を下回り、200ms 以上短縮 |
| 6 | after 計測結果を `docs/research/` に保存 | before/after 比較表を含むドキュメントが存在する |

### 2.6 呼出しパターンの変化

| パターン | Before | After | 備考 |
|---|---|---|---|
| `_yaml_field_get_in_block` | 2回 | 0回（awk 置換対象） | 読取り経路のみ置換。将来フォローアップ F2 で追加検討 |
| `yaml_field_set` | 3回 | 3回（不変） | 制約 C4 により書込み経路は変更禁止 |
| `python3` | 1回 | 0回 | R2 による置換。FC-02 で検証 |
| `grep` | 3回 | 2回以下（R1 による削減） | R1 で `grep -c` を awk に置換 |
| `awk` | 0回 | 2回以上（R1 + R2 で追加） | 読取り専用関数にのみ使用 |

### 2.7 テストアーキテクチャ

#### 既存テスト

- **ファイル:** `tests/unit/test_cmd_publish_preflight.bats`
- **テスト数:** 5件
- **フレームワーク:** bats-core
- **全件 PASS が必須（AC-12, FC-01）**

#### E2E テスト構成

| ドメイン | ファイル | 検証対象 |
|---|---|---|
| `awk-count` | `tests/e2e/awk-count.spec.bats` | R1 の awk 置換正確性 |
| `awk-block-scanner` | `tests/e2e/awk-block-scanner.spec.bats` | R2 の awk block scanner 正確性 |
| `io-contract` | `tests/e2e/io-contract.spec.bats` | 外部 I/O 契約の維持（制約 C1） |
| `preflight-order` | `tests/e2e/preflight-order.spec.bats` | pre-flight BLOCK 順序（制約 C2）・`on_hold` 保持（制約 C3） |
| `preflight-order` (workflow) | `tests/e2e/preflight-order.workflow.spec.bats` | pre-flight → cmd_save 連携の end-to-end ワークフロー |
| `yaml-write-guard` | `tests/e2e/yaml-write-guard.spec.bats` | YAML 書込み経路制限（制約 C4） |
| `performance` | `tests/e2e/performance.spec.bats` | 実行時間短縮・fast-fail 性能維持 |

#### 共有ヘルパー

| ファイル | 責務 |
|---|---|
| `tests/e2e/helpers/fixture_setup.bash` | テスト用 YAML フィクスチャ生成・一時ディレクトリ管理・`setup()`/`teardown()` 共通処理 |
| `tests/e2e/helpers/yaml_fixtures.bash` | `logs/cmd_design_quality.yaml` のテストパターン生成（0件/1件/複数件/混合条件） |
| `tests/e2e/helpers/assertions.bash` | 共通アサーション（単一整数出力検証、exit code 検証、ファイル差分検証、実行時間検証） |
| `tests/e2e/helpers/source_loader.bash` | `cmd_publish.sh` の関数を個別にロードするユーティリティ |

#### ランタイム要件

- **シェル:** bash 4.3 以上
- **依存コマンド:** `awk`, `grep`, `bats`
- **テストフィクスチャ:** `$BATS_TMPDIR` に作成し並列実行可能
- **ヘルスチェック:** テスト実行前に `bash -n scripts/cmd_publish.sh`（構文チェック）、`which awk && which bats`（ツール存在確認）、`type -t yaml_field_set`（依存関数存在確認）を実施

### 2.8 品質ゲートと失敗基準

リリース判定は以下の9つの失敗基準（FC-01〜FC-09）のいずれにも該当しないことを条件とする。

| ID | 失敗条件 | 関連制約 |
|---|---|---|
| FC-01 | `test_cmd_publish_preflight.bats` の5テスト中1件以上が FAIL | — |
| FC-02 | `count_cmd_save_blocks_for_cmd()` 実行パスで `python3` が起動 | — |
| FC-03 | stdout 出力・exit code・読取り/書込みファイル一覧のいずれかがリファクタリング前後で変化 | C1 |
| FC-04 | BLOCK 判定完了前に `cmd_save.sh` が実行（順序逆転） | C2 |
| FC-05 | `cmd_save.sh` 成功前に `on_hold` が解除 | C3 |
| FC-06 | YAML 運用ファイルへの `yaml_field_set` 以外の書込み（`>`, `>>`, `sed -i`, awk 直接書込み, `tee` を含む） | C4 |
| FC-07 | `count_active_shogun_lessons()` が0件時に `0` 以外を出力（`0\n0` を含む） | — |
| FC-08 | テスト全量平均実行時間がベースライン 0.694s を上回る | — |
| FC-09 | `count_cmd_save_blocks_for_cmd()` のカウント不正確（条件外エントリのカウントまたはカウント漏れ） | — |

### 2.9 制約遵守の明示的サマリ

| 制約 | 設計上の対応 | 検証手段 |
|---|---|---|
| C1: 外部 I/O 契約の凍結 | R1・R2 は読取り関数の内部実装のみ変更。入出力ファイルパス・exit code・stdout フォーマットは不変 | AC-07 / FC-03: リファクタリング前後で同一テストフィクスチャを与え diff 比較 |
| C2: pre-flight BLOCK 順序維持 | フェーズ1（pre-flight）→ フェーズ2（判定）→ フェーズ3（cmd_save）の実行順序は変更しない。BLOCK 時にフェーズ3 へ遷移しない | AC-08 / FC-04: BLOCK 条件でモック/スパイにより `cmd_save.sh` 非実行を確認 |
| C3: `on_hold` ライフサイクル保全 | `on_hold` 解除は `cmd_save.sh` 成功（exit code 0）時のみ。BLOCK 分岐時は `on_hold` 維持 | AC-09 / FC-05: 成功前後で `on_hold` 状態遷移を確認 |
| C4: YAML 書込み経路限定 | awk 置換は読取り専用関数のみ。`yaml_field_set` 3箇所は現行維持。代替書込み手段は使用しない | AC-10 / FC-06: ソースコード検査で `yaml_field_set` 以外の YAML 書込みが存在しないことを確認 |

---

## 3. Open Questions

| # | 質問 | 影響範囲 | 判断期限 | 暫定方針 |
|---|---|---|---|---|
| OQ-1 | `_yaml_field_get_in_block`（2箇所）の awk 置換を R1・R2 と同一リリースで実施するか、フォローアップとするか | `module:cmd_publish` の読取り性能と変更範囲 | R2 実装完了・after 計測後 | ADR F2 に従いフォローアップとして分離。R1・R2 の効果を計測してから判断する |
| OQ-2 | `logs/cmd_design_quality.yaml` のフォーマットが将来変更された場合の awk block scanner 保守戦略 | awk パターンマッチの脆弱性 | YAML スキーマ変更 PR のマージ前 | ADR F3 に従い、フォーマット変更者が awk パターンも更新する運用ルールを設ける。対象 YAML はインデント2スペースの固定フォーマットを前提とする |
| OQ-3 | CI パイプラインでの `test_cmd_publish_preflight.bats` 実行時間監視の閾値とアラート先 | CI 基盤の監視設定 | CI 管理者との合意後 | ADR F4 に従い 0.5s を閾値候補とする。アラート先は CI 管理者が決定する |
| OQ-4 | `grep` 呼出し3箇所の awk 統合による追加性能改善の余地 | テスト実行時間のさらなる短縮 | R1・R2 の after 計測で目標短縮に未達の場合 | ADR F5 に従い、after 計測結果を確認してから着手判断する。目標（200ms 以上短縮）を達成していれば優先度を下げる |
