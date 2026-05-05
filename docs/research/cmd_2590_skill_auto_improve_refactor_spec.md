# skill_auto_improve.sh リファクタリング CoDD Spec

**対象ファイル**: `scripts/skill_auto_improve.sh` (279行)
**作成日**: 2026-05-06
**作業タスク**: cmd_2590_exact

---

## 問題（ボトルネック関数+計測値）

### Phase 1 実測結果（3回平均）

| 指標 | Before |
|------|--------|
| dry-run 1回実行 | 117ms (min:112ms, max:123ms) |
| python3起動オーバーヘッド | ~26ms (22%) |
| yaml.safe_load (195エントリ) | ~91ms (78%) |
| stats_aggregation (66 FAIL) | ~0.3ms (<1%) |
| iter_skill_files (apply=True時) | ~181ms (apply時のみ) |

### 構造分析

`skill_auto_improve.sh`は bash + Python ヒアドキュメント（37-279行）の構造。

```
scripts/skill_auto_improve.sh
├── bash: 引数パース (1-36行)
└── python3 ヒアドキュメント (37-279行)
    ├── load_entries()       → yaml.safe_load 全195エントリ
    ├── iter_skill_files()   → 3ディレクトリ85スキルを毎回scan
    ├── skill_file_for()     → iter_skill_filesを毎回呼ぶ（apply時N回）
    ├── stats集計            → 全エントリイテレーション
    └── apply_prevention_steps() → SKILL.md更新
```

---

## 定量プロファイル（実測）

| ステップ | 時間 | 割合 | 発生条件 |
|----------|------|------|---------|
| yaml.safe_load (195 entries) | 91ms | 78% | 常時 |
| python3起動 | 26ms | 22% | 常時 |
| iter_skill_files (85 skills) | 181ms | — | apply=True時のみ |
| stats_aggregation | 0.3ms | <1% | 常時 |

**実行ログ**: entries=195, FAIL=66(34%), skills=85, apply_planスキル数=6

---

## リファクタリング対象

### R1: YAMLキャッシュ（最大ボトルネック: 91ms → 目標 <5ms）

**現状**: `load_entries(path)` が毎回 `yaml.safe_load` で全195エントリをロード。

**改善**: mtime+sizeベースのJSONキャッシュ
- ファイルパス: `/tmp/skill_auto_improve_cache_<sha1_of_path>.json`
- キャッシュキー: `(mtime, size)` のタプル
- キャッシュヒット時: JSONファイル読み込み (1ms以下)
- キャッシュミス時: yaml.safe_load → JSONダンプ → 次回利用

**凍結ロジック**: YAMLのパース結果は変えない。キャッシュ有効性チェックのみ追加。

### R2: iter_skill_files辞書化（apply時: N回→1回）

**現状**: `skill_file_for(skill_name, logged_path)` が毎回 `iter_skill_files()` を線形探索。
apply時に`len(apply_plan)`(=6)回呼ばれる → 181ms × 6 = 1086ms潜在オーバーヘッド

**改善**: `iter_skill_files()` 結果を事前に `{name: path}` 辞書化
```python
_skill_index = {name: path for name, path in iter_skill_files()}
def skill_file_for(skill_name, logged_path):
    if logged_path: ...
    return _skill_index.get(skill_name)
```

**凍結ロジック**: ディレクトリ探索ロジック・dedup処理は変えない。

### R3: FAILエントリのみ処理（stats集計最適化）

**現状**: 全195エントリをイテレーション後にFILTER
**改善**: `load_entries()` でFAILフィルタを組み込み（0.3msでほぼ無効化だが構造的明瞭化）

---

## 実施順序

1. R1実装 → 動作確認(dry-run出力同一性検証) → 計測
2. R2実装 → 動作確認(apply --dry-run出力同一性) → 計測
3. R3実装 → 動作確認 → 最終計測

---

## 制約

1. **API互換**: `--log`, `--skills-dirs`, `--top`, `--skill`, `--apply`, `--dry-run`, `-h` フラグは変えない
2. **出力互換**: TSVヘッダー行 + `skill | rank | fail_count | ...` 形式は変えない
3. **キャッシュ無効化**: `/tmp/` にキャッシュを置き、OSが自動掃除。明示的invalidateは不要
4. **凍結ロジック**: `marker_for()`, `concrete_prevention_steps()`, `apply_prevention_steps()` のコアロジックは変えない

---

## 期待効果（見込み）

| ステップ | Before | After (見込み) | 改善率 |
|----------|--------|----------------|--------|
| yaml.safe_load | 91ms | <5ms (cache hit) | -95% |
| iter_skill_files(apply) | 181ms×N | 181ms×1(初回のみ) | -83% (N=6想定) |
| 全体(dry-run) | 117ms | ~30ms | -74% |
| 全体(apply) | ~350ms | ~50ms | -86% |

> 注: キャッシュミス時(初回/ログ更新後)は改善なし。
