# cmd_1980 gate_recalculate_completeness.sh 高速化 spec

## 1. before

- 既存 after 記録: `docs/research/gate_recalculate_completeness_after_20260416.md`
- live repro:
  - cold: `4.80s`
  - warm: `1.41s / 1.62s`
- ベースライン:
  - 直前改善後の実測: `2.74s`
  - warm run でもまだ `1.4-1.6s` 残る

## 2. bottleneck

1. SQL が `COUNT(*) + GROUP BY` で `signals` / `monthly_returns` / `fof_component_weights` を最後まで走査している。
2. `extract_db_host()` が Python `urlparse` を毎回起動しており、200回ベンチで `6.018s` (`≈30ms/call`) と無視できない固定費になっている。
3. success path でも DB 側で `ORDER BY p.type, p.name` を実行しており、失敗0件ケースでは恩恵よりコストが先に立つ。

## 3. optimization candidates

1. `COUNT/GROUP BY` → `EXISTS` semi-join:
   - same-connection bench:
     - current median: `267.6ms`
     - exists median: `83.1ms`
   - 見込み: クエリ本体を `~185ms` 短縮
2. Python host parser → pure bash parser:
   - `extract_db_host` 200回: `6.018s`
   - 見込み: 1回実行あたり `~20-30ms` 短縮
3. success path no-sort:
   - same-connection bench:
     - `exists + ORDER BY`: `80.3ms`
     - `exists + no ORDER BY`: `75.1ms`
   - 見込み: `~5ms` 短縮。失敗表示順は Python 側で不足分だけ整列

## 4. chosen changes

- 採用: 1, 2, 3
- 非採用:
  - 接続プーリング/daemon化: 単発 gate の scope を超える
  - 複数クエリ分割: network round-trip 増で不利
  - 失敗専用 query 化: current dataset では `exists` より遅い (`98.9ms`)

## 5. acceptance mapping

- AC1: 本 spec に残存ボトルネック3件と候補3件を記録
- AC2: `scripts/gates/gate_recalculate_completeness.sh` を機能不変で高速化
- AC3: before `2.74s` 比の after 計測を残す
- AC4: unit test / syntax / 実 gate 実行 / `docs/research/codd_refactor_registry.md` 更新

## 6. after

- live repro:
  - cold: `2.168s`
  - warm: `1.085s / 1.080s`
- 改善率:
  - baseline `2.74s` → `2.168s` (`-20.9%`)
  - warm run は `~1.08s` で baseline 比 `-60.4%`
- helper benchmark:
  - `extract_db_host` 200回: `6.018s` → `0.010s`
- 検証:
  - `bash -n scripts/gates/gate_recalculate_completeness.sh`
  - `bats tests/unit/test_gate_recalculate_completeness.bats` (`5/5 PASS`)
  - `bash scripts/gates/gate_recalculate_completeness.sh` (`3/3 PASS`)
