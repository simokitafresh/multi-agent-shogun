# skill_gate_feedback.sh After設計書（リファクタリング後のas-is）
# cmd_2589 / 2026-05-06

## 概要

`scripts/skill_gate_feedback.sh` — gate FAIL 時に該当スキルへ注意ポイントを追記し、
ログエントリを記録する bash+Python ヒアドキュメント構成スクリプト（240行）。

## 現在の構造

### 関数一覧と責務（変更された関数に★）

| 関数 | 責務 | 変更 |
|------|------|------|
| `iter_skill_files()` | skills ディレクトリ走査、SKILL.md 列挙 | 変更なし |
| `skill_log_file()` | ログファイルパス解決 | 変更なし |
| `load_skill_log()` | YAML ロード + **キャッシュ返却** | ★R2: キャッシュ追加 |
| `_yaml_str(v)` | YAML 文字列エスケープ | ★R1: 新規追加 |
| `_write_skill_log(...)` | flock ログ書込み（インライン） | ★R1: 新規追加 |
| `latest_fail_entry()` | ログから直近 FAIL エントリ検索 | 変更なし |
| `exact_skill_file(...)` | スキル名→SKILL.md パス解決 | 変更なし |
| `has_duplicate_failure(...)` | 重複 FAIL 検知 | 変更なし |
| `has_duplicate_caution(...)` | SKILL.md 重複注意ポイント検知 | 変更なし |

### 依存関係

```
skill_gate_feedback.sh
  ├── Python stdlib: fcntl, os, re, sys, tempfile, datetime, pathlib
  ├── PyPI: yaml (load_skill_log)
  ├── skill_log_file() ← SKILL_EXECUTION_LOG_FILE 環境変数 or $LOG_SCRIPT/../logs/
  └── SKILL_FEEDBACK_SKILLS_DIRS 環境変数 or デフォルト3ディレクトリ
      (skill_execution_log.sh の呼び出しは廃止)
```

## R1: _write_skill_log インライン化

### 設計

`subprocess.run(["bash", log_script, ...])` を廃止し、Python `fcntl.flock` で直接書込み。

### 動作仕様

```python
def _write_skill_log(skill_name, executor_name, result_str, stumbling,
                     gate_name, source_path, skill_path_str):
    # 1. tests/ パス除外 (skill_execution_log.sh と同一ルール)
    if _TESTS_PATH_RE.search(source_path): return

    # 2. flock でログファイルに排他書込み
    #    ファイル不在/空 → "executions:\n" ヘッダ作成
    #    → YAML フィールドを append

    # 書込みフィールド順: ts, skill, executor, result, used, stumbling_points,
    #                      gate, source, skill_path (非空の場合のみ)
    # used は常に "false" (skill_gate_feedback の推論エントリを示す)
```

**`used: "false"`の意味**: `skill_gate_feedback.sh` が推論で作成したエントリ。
`latest_fail_entry()` はこれをスキップし、`skill_execution_log.sh` 経由の
`used: "true"` エントリのみを参照することで推論の二重ループを防止。

### 凍結ロジック

- source パス除外ルール: `r'(?:^|/)tests/'` — 変更禁止
- flock 方式: `fcntl.LOCK_EX` — 変更禁止
- ファイル構造: `executions:` ヘッダ + append 方式 — 変更禁止

## R2: load_skill_log() キャッシュ化

```python
_SKILL_LOG_CACHE = None  # module-level sentinel

def load_skill_log():
    global _SKILL_LOG_CACHE
    if _SKILL_LOG_CACHE is not None:
        return _SKILL_LOG_CACHE
    # ... YAML ロード ...
    _SKILL_LOG_CACHE = [entry for entry in entries if isinstance(entry, dict)]
    return _SKILL_LOG_CACHE
```

**同一プロセス内での 2 回呼出し**: `latest_fail_entry()` と `has_duplicate_failure()` が両方 `load_skill_log()` を呼ぶため、キャッシュで 71ms を節約。

## 最適化パターン（再利用すべき仕組み）

### A. subprocess 廃止 → Python インライン実装

同一ロジックを bash subshell 経由で呼ぶコストは Python heredoc 内で吸収できる。
`yaml_scalar` の 7 回呼出しが全て内部化され、8 × 37ms の Python startup を排除。

**いつ使うか**: bash スクリプトが bash サブシェル経由で Python スクリプトを呼ぶパターンで、
呼び先が `fcntl.flock` / YAML append など Python で自然に書けるもの。

### B. モジュールレベルキャッシュ

Python heredoc 内でグローバル変数 `_VAR = None` でセンチネルを使い、
同一プロセス内の複数回 I/O を 1 回に圧縮。

**いつ使うか**: 同一 Python プロセス内で同じファイルを複数回読む関数がある場合。

## 禁止パターン（やってはいけないこと+理由）

| NG | 理由 |
|----|------|
| `yaml.safe_dump` で YAML ファイル上書き | データ消失事故(cmd_1399) — append 専用 |
| `subprocess.run(["bash", log_script, ...])` の復活 | 8 × Python startup = 220ms の劣化 |
| `_SKILL_LOG_CACHE` をプロセス外に持ち出す | ファイル変更を見逃す — プロセス内のみ有効 |
| `used` フィールドなしで `_write_skill_log` を書く | `latest_fail_entry()` が推論エントリを誤検知 |

## 計測値（劣化検知のベースライン）

| ケース | Before | After | 改善率 |
|--------|--------|-------|--------|
| 1呼出し (PASS/FAIL, --skill 指定) | 220ms | **50ms** | **-77%** |
| SKIP case (skill 未検出) | 281ms | **52ms** | **-81%** |
| テストスイート 13件 | 3.634s | **2.441s** | **-33%** |

※ Before 計測: `subprocess.run` 主因 220ms × 1回/呼出し
※ After 計測: Python startup 37ms + YAML load 71ms (キャッシュ後0ms) + flock 書込み数ms
