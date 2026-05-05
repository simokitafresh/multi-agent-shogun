# skill_gate_feedback.sh リファクタリング CoDD Spec
# cmd_2589 / 2026-05-06

## 問題（ボトルネック関数+計測値）

`scripts/skill_gate_feedback.sh` は gate FAIL 時にスキルに注意ポイントを追記し、
実行ログを `skill_execution_log.yaml` に記録する 216 行の bash+Python スクリプト。

### 主要ボトルネック

| ボトルネック | コスト | 原因 |
|-------------|--------|------|
| `subprocess.run(skill_execution_log.sh)` | **220ms** | 内部で8回 Python spawn (yaml_scalar×7 + validation×1) |
| `load_skill_log()` 2回呼出し | **71ms × 2 = 142ms** | 同一呼出し内で YAML を 2 回ロード |
| Python プロセス起動 | **37ms** | bash→python3 heredoc |

## 定量プロファイル(実測)

**計測日**: 2026-05-06
**環境**: WSL2 / Ubuntu / Python 3.x / PyYAML

### テストスイート全体
| 段階 | 時間 |
|------|------|
| before (bats 12 tests) | **3.634s** |

### 単体呼出し
| ケース | 計測値(avg) |
|--------|-----------|
| FAIL case (--skill 指定) | 220ms |
| PASS case (--skill 指定) | 224ms |
| SKIP case (no skill) | 281ms |

### 操作別内訳
| 操作 | コスト |
|------|--------|
| Python startup | 37ms |
| YAML load (195 entries) | 71ms |
| iter_skill_files (38 skills, cold) | 399ms (warm: 230ms) |
| iter_skill_files (1 skill in test) | 0.2ms |
| skill_file.read_text | 0.1ms |
| subprocess.run → skill_execution_log.sh | **220ms** |

### subprocess.run の内部コスト
`skill_execution_log.sh` は `yaml_scalar()` を 7 回呼出し、最後に YAML validation で計 **8 回** Python spawn:
- 8 × 37ms ≈ 296ms (startup のみ)
- flock + ファイル書込みで合計 ~220ms

### load_skill_log() の呼出しパス
```
explicit_skill=None の場合:
  latest_fail_entry() → load_skill_log() [1回目]
  logged_entry=None かつ FAIL → has_duplicate_failure() → load_skill_log() [2回目]

explicit_skill 指定の場合:
  FAIL → has_duplicate_failure() → load_skill_log() [1回のみ]
```

## リファクタリング対象

### R1: subprocess.run のインライン化（最大効果）

**現状**: `subprocess.run(["bash", log_script, skill, executor, result, ...])` → bash プロセス起動 → 8 Python spawn

**改善**: `skill_execution_log.sh` のロギック（ソース除外・flock 書込み・YAML追記）を Python heredoc 内に直接実装する `_write_skill_log()` 関数を追加。

**期待効果**: 220ms → ~5ms（-98%）
**API互換性**: `skill_execution_log.sh` はそのまま残す（他の呼出元が存在）

**実装方針**:
```python
import fcntl  # flock 相当
import re

TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')

def _write_skill_log(log_script, skill, executor, result, stumbling, gate, source, skill_path_str):
    # tests/ パス除外 (skill_execution_log.sh と同じルール)
    if TESTS_PATH_RE.search(source):
        return
    log_path = skill_log_file()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = log_path.parent / (log_path.name + ".lock")
    ts = datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")

    def _yaml_str(v):
        v = str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{v}"'

    lines = [
        f'- ts: {_yaml_str(ts)}\n',
        f'  skill: {_yaml_str(skill)}\n',
        f'  executor: {_yaml_str(executor)}\n',
        f'  result: {_yaml_str(result)}\n',
        f'  stumbling_points: {_yaml_str(stumbling)}\n',
    ]
    if gate:
        lines.append(f'  gate: {_yaml_str(gate)}\n')
    if source:
        lines.append(f'  source: {_yaml_str(source)}\n')
    if skill_path_str:
        lines.append(f'  skill_path: {_yaml_str(skill_path_str)}\n')

    with open(str(lock_path), "a") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            if not log_path.exists() or log_path.stat().st_size == 0:
                log_path.write_text("executions:\n", encoding="utf-8")
            with open(str(log_path), "a", encoding="utf-8") as fh:
                fh.writelines(lines)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)
```

**凍結ロジック**: source パス除外ルール (`tests/*` / `*/tests/*`) は変更禁止

### R2: load_skill_log() キャッシュ化

**現状**: 同一 Python プロセス内で最大 2 回 YAML ロード(71ms × 2 = 142ms)

**改善**: モジュールレベル変数でキャッシュ。`_SKILL_LOG_CACHE = None` → 2回目以降はキャッシュ返却。

**期待効果**: 71ms 節約（2回呼出し時のみ）
**凍結ロジック**: キャッシュはプロセス内のみ（プロセス間共有なし = 安全）

## 実施順序

```
R2 実装 → テスト全 PASS 確認
R1 実装 → テスト全 PASS 確認
Phase 5 計測 → before/after 比較表
Phase 6 After 設計書生成
```

## 制約

1. **テスト全 PASS 必須**: `bats tests/unit/test_skill_feedback_loop.bats` 12 件全 PASS
2. **API 互換**: 引数 (--gate/--result/--reason/--executor/--source/--skill) は変更禁止
3. **凍結ロジック**:
   - `has_duplicate_caution()` のロジック（文字列マッチング）
   - `has_duplicate_failure()` のロジック（エントリ比較）
   - source が tests/ の場合の除外ルール
   - flock による排他制御
4. **`skill_execution_log.sh` は削除禁止**: 他の呼出元（テスト・dash_update 等）が存在する
5. **Python の `yaml.safe_dump` 使用禁止**: YAML上書き事故防止（CLAUDE.md ルール）
