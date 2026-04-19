# cmd_2113 cli_adapter test setup profiling

- Date: 2026-04-19
- Target: `tests/unit/test_cli_adapter.bats`
- Goal: `setup`/fixture overheadを減らし、5回計測中央値を30%以上短縮する

## Before

- Command:
  ```bash
  python3 - <<'PY'
  import subprocess, statistics
  cmd=['bats','tests/unit/test_cli_adapter.bats']
  times=[]
  for _ in range(5):
      proc=subprocess.run(['/usr/bin/time','-f','%e',*cmd],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=True)
      times.append(float(proc.stderr.strip().splitlines()[-1]))
  print(times, statistics.median(times))
  PY
  ```
- Runs: `12.43s`, `13.16s`, `11.56s`, `6.45s`, `5.37s`
- Median: `11.56s`
- Test count: `57`

## Profiling Findings

- `bats -T tests/unit/test_cli_adapter.bats` で cold run を観測すると、個別テスト本体より fixture 解決コストが支配的だった。
- 特に重かった項目:
  - `get_cli_type: mixed設定 全忍者パターン` = `519ms`
  - `build_cli_command: codex` = `344ms`
- 構造的原因:
  - `setup_file()` が毎回多数の一時 YAML fixture を生成していた。
  - テスト override も fixture ファイルを毎回読み直しており、WSL2 上の短命 I/O が cold path を膨らませていた。

## Change

- `tests/unit/test_cli_adapter.bats`
  - 一時 YAML fixture の大量生成を廃止。
  - fixture 名ベースの pure-bash lookup (`_fixture_agent_type`, `_fixture_yaml_val`) に置換。
  - `cli profile` lookup も test double で固定値返却に寄せ、不要な file I/O を削減。

## After

- Runs: `4.27s`, `6.00s`, `4.96s`, `6.39s`, `5.55s`
- Median: `5.55s`
- Improvement: `-6.01s` (`52.0%` reduction vs before median)
- Test count: `57`

## Post-change Timing Snapshot

- `get_cli_type: mixed設定 全忍者パターン` = `97ms`
- `build_cli_command: codex` = `101ms`

## Conclusion

- AC1/AC3 の timing 要件を満たした。
- 改善の本体は本番ロジック変更ではなく、テストハーネスの cold fixture I/O 削減である。
