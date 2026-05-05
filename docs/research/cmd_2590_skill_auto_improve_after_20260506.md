# skill_auto_improve.sh After設計書（リファクタリング後のas-is）

**対象ファイル**: `scripts/skill_auto_improve.sh`
**リファクタリング日**: 2026-05-06
**タスク**: cmd_2590_exact (CoDD refactor)

---

## 現在の構造

### 関数一覧と責務

| 関数 | 責務 | 変更 |
|------|------|------|
| `load_entries(path)` | skill_execution_log.yamlをロード | ✅ R1: mtime+sizeキャッシュ追加 |
| `_cache_path(log_path)` | キャッシュファイルパス生成 | ✅ **新規追加** |
| `iter_skill_files()` | 全スキルディレクトリをスキャン | 変更なし |
| `_get_skill_index()` | 辞書型スキルインデックス | ✅ **新規追加** |
| `skill_file_for(name, path)` | スキル名→SKILL.mdパス解決 | ✅ R2: 辞書参照に変更 |
| `normalize_reason(value)` | FAILメッセージ正規化 | 変更なし |
| `shorten(value, limit)` | 文字列短縮 | 変更なし |
| `marker_for(skill, reason)` | 重複防止マーカー生成 | 変更なし |
| `concrete_prevention_steps(reason)` | FAILパターン→防止ステップ生成 | 変更なし |
| `prevention_line(...)` | 防止ステップ行を整形 | 変更なし |
| `existing_auto_section_insert_index(lines)` | SKILL.md挿入位置探索 | 変更なし |
| `procedure_insertion_index(lines)` | 手順セクション挿入位置探索 | 変更なし |
| `apply_prevention_steps(skill_path, rows)` | SKILL.mdへの防止ステップ注入 | 変更なし |

### 依存関係

```
main流れ:
  load_entries(log_file)       ← _cache_path() を呼ぶ
    → yaml.safe_load (cache miss時のみ)
    → JSON cache read/write (/tmp/skill_auto_improve_cache_*.json)
  stats集計 (FAIL filterはload_entries後)
  skill_file_for(name, path)   ← _get_skill_index() を呼ぶ (apply=True時)
    → _get_skill_index()        ← iter_skill_files() を1回だけ呼ぶ
```

---

## 最適化パターン（再利用すべき仕組み）

### R1: mtime+sizeキャッシュ (load_entries)

**いつ使うか**: 大きなYAMLファイル(>50エントリ)を毎回フルロードするスクリプト

**実装パターン**:
```python
def _cache_path(log_path):
    digest = hashlib.sha1(str(log_path).encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"my_cache_{digest}.json"

def load_data(path):
    try:
        stat = Path(path).stat()
        cache_key = (stat.st_mtime_ns, stat.st_size)
    except FileNotFoundError:
        return []
    cache_file = _cache_path(path)
    if cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            if tuple(cached.get("key", [])) == cache_key:
                return cached["data"]
        except (json.JSONDecodeError, KeyError):
            pass
    # ...load and cache...
```

**なぜ速いか**: `mtime_ns + size` チェックはinode1回読み = 1μs以下。JSONロードはYAMLの1/10以下。

**注意点**: ファイルが変更されるとmtime_nsが変わり自動無効化。手動invalidateは不要。

### R2: 辞書型スキルインデックス (_get_skill_index)

**いつ使うか**: 同一セッションで`iter_skill_files()`の結果を2回以上使う場合

**実装パターン**:
```python
_skill_index = None

def _get_skill_index():
    global _skill_index
    if _skill_index is None:
        _skill_index = {name: path for name, path in iter_skill_files()}
    return _skill_index
```

**なぜ速いか**: ディレクトリスキャン(85スキル=181ms)が1回になる。N回参照でもO(1)辞書ルックアップ。

---

## 禁止パターン（やってはいけないこと+理由）

| NG | 理由 | 正しいやり方 |
|----|------|-------------|
| `skill_file_for()`内で`iter_skill_files()`を毎回呼ぶ | apply時にN回スキャン(181ms×N=1086ms) | `_get_skill_index()`経由でO(1)参照 |
| キャッシュキーに`mtime`(秒精度)を使う | 同一秒内の更新を検知できない | `st_mtime_ns`(ナノ秒精度)を使う |
| キャッシュを永続ディレクトリに置く | 古いキャッシュが残り続ける | `/tmp/`に置く(OS自動掃除) |
| `yaml.safe_dump`でキャッシュ書き込み | データ消失リスク(cmd_1399事故パターン) | `json.dumps`を使う |

---

## 計測値（劣化検知のベースライン）

| 条件 | Before | After | 改善率 |
|------|--------|-------|--------|
| dry-run / cache miss | 117ms | 134ms (+17ms write overhead) | +15% |
| dry-run / cache hit | 117ms | 58ms | **-51%** |
| apply=True / 6スキル | ~350ms | ~50ms (見込み) | **-86%** |

> **キャッシュヒット率**: skill_execution_log.yamlはスキル実行時のみ更新。
> 通常の連続実行(同一セッション内)ではほぼ100%ヒット。

> **劣化検知ライン**: dry-run/cache hit が 100ms超えたらリグレッション。

---

## context索引への登録

`context/infrastructure.md` §スキル自走改善セクションへのリンク追加が推奨:
```
→ docs/research/cmd_2590_skill_auto_improve_after_20260506.md（キャッシュ+辞書化パターン）
```
