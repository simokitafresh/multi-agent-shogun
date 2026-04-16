# gate_cycle_health.sh リファクタリング CoDD Spec (事後作成)

## cmd: cmd_1955 (CoDD改善#3)
## 実施者: kagemaru

## 問題（ボトルネック関数+計測値）

gate_cycle_health.sh の実行時間 793ms。
ボトルネック: S3(find -newer + grep -q ループ = 584ms) + S4(python3 = 80ms) が全体の84%を占有。

- S3: ~500ファイルに対して find -newer で全件 stat → grep -q ループで37回サブプロセス起動
- S4: PI原理率計算に python3 インタプリタ起動(80ms)

## 定量プロファイル(実測 before)

| セクション | 時間 | 根因 |
|------------|------|------|
| S3 (find -newer + grep -q ループ) | 584ms | ~500ファイル全stat + 37サブプロセス grep -q |
| S4 (python3 PI原理率計算) | 80ms | python3 インタプリタ起動オーバーヘッド |
| その他 (S1, S2, etc.) | ~129ms | - |
| **合計** | **793ms** | S3+S4 = 664ms (84%) |

## リファクタリング対象

### R1: S3 — find全件stat+grep-qループ → 名前フィルタ+部分stat+awk in-memory lookup

**現状**:
- find -newer で ~500ファイル全件 stat
- grep -q ループで37回のサブプロセス起動
- CLEAR済みcmd含めて全件走査

**改善**:
1. find で名前のみ取得(10ms)
2. grep -oE で CLEAR済み cmd_id を抽出
3. 非CLEAR分(~269件)のみ xargs stat で走査(500→269に削減)
4. 最近のファイルのみ grep -l
5. awk in-memory lookup で集計(37サブプロセス grep -q を廃止)

- 期待効果: 584ms → ~200ms(サブプロセス37回廃止 + stat対象46%削減)
- 実績: 全体で793ms → 296ms達成

### R2: S4 — python3(80ms) → awk(7ms)

**現状**:
- python3 を起動して PI原理率を計算(80ms)
- インタプリタ起動コストが計算本体より支配的

**改善**:
- awk 1パスで PI原理率を計算
- python3 起動コスト(80ms)を完全排除

- 期待効果: 80ms → ~7ms(73ms削減)
- 実績: python3(80ms) → awk(7ms)

### 追加修正: set -o pipefail 安全対策

- set -o pipefail 環境下で grep -oE が no-match(exit 1)時にスクリプト全体が異常終了する問題に対応
- `|| true` を追加して安全にハンドリング(L480/L481教訓の適用)

## 制約

- テスト全PASS必須(全11テスト)
- API互換（出力形式変更なし）: ゲート判定ロジック(CLEAR/WARN/BLOCK)は不変
- 凍結ロジック: S1(ヘッダ/定数), S2(基本チェック), S5以降(判定・出力ロジック)

## 結果

- before: 793ms
- after: 296ms
- 改善率: 63%削減(目標500ms達成)
- テスト: 全11テストPASS
- 対象ファイル: `scripts/gates/gate_cycle_health.sh`
