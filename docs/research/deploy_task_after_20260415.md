# deploy_task.sh After設計書（2026-04-15リファクタリング後のas-is）

## 現在の構造（3607行→3597行）

### 変更された関数

| 関数 | 行 | 変更内容 |
|------|-----|---------|
| resolve_cmd_to_task() | L247 | yaml_field_set 7回→yaml_field_set_batch 1回 |
| inject_ac_version() | L680 | field_get 6回→field_get_multi 1回、yaml_field_set 3回→yaml_field_set_batch 1回 |

### 新規ユーティリティ（scripts/lib/）

| 関数 | ファイル | 用途 |
|------|---------|------|
| yaml_field_set_batch | yaml_field_set.sh L560+ | 1 flock + 1 awk passで複数フィールド同時更新 |
| field_get_multi | field_get.sh L370+ | 1 awk passで複数フィールド一括読取（eval可能出力） |

### テストインフラ

| 仕組み | ファイル | 用途 |
|--------|---------|------|
| func cache | deploy_task_scaffold.bash L11-17 | setup_file()でdeploy_task.sh全関数をキャッシュ。各テストsubshellはcacheからsource |
| --jobs 8 | .github/workflows/test.yml, scripts/run_tests.sh | bats並列化。CI+ローカル両対応 |
| run_tests.sh | scripts/run_tests.sh | --jobs 8自動適用ラッパー |
| fullrun guard | scripts/hooks/pre-bash-test-fullrun-guard.sh | bats直接全量実行をBLOCK→run_tests.sh誘導 |

## 最適化パターン（再利用すべき仕組み）

### yaml_field_set_batch
```bash
yaml_field_set_batch <file> <block_id> "field1=val1" "field2=val2" ...
```
- **いつ使うか**: 同一ファイルの同一ブロックに3回以上yaml_field_setする場合
- **なぜ速いか**: flock取得1回+awk全量rewrite 1回+verify 1回。逐次N回だとN倍のflock+rewrite
- **注意**: value内の`=`は安全（`${arg%%=*}`/`${arg#*=}`でパース）

### field_get_multi
```bash
eval "$(field_get_multi <file> field1 field2 ...)"
```
- **いつ使うか**: 同一ファイルから3フィールド以上読む場合
- **なぜ速いか**: 1回のawk passで全フィールド抽出。逐次N回だとN回のgrep/sed
- **注意**: 未存在フィールドは空文字列（エラーにならない）。eval前にlocal宣言必須

### func cache
```bash
setup_file() {
    export _DT_FUNC_CACHE="/tmp/_dt_func_cache_$$_$(date +%s).sh"
    ( DEPLOY_TASK_LIB_ONLY=1; source "$SCRIPT"; declare -f ) > "$_DT_FUNC_CACHE"
}
```
- **いつ使うか**: テストのsubshellで大きなスクリプトをsourceする場合
- **なぜ速いか**: sourceが3607行→キャッシュファイル（関数定義のみ）。137ms→数ms
- **注意**: SCRIPT_DIRは各テストで再設定必要。キャッシュはPID分離で並列安全

## 禁止パターン

| NG | 理由 | 代替 |
|----|------|------|
| 同一ファイルにyaml_field_set 3回以上 | flock 3回+rewrite 3回=60-150ms | yaml_field_set_batch 1回 |
| 同一ファイルにfield_get 3回以上 | grep 3回=6-45ms | field_get_multi 1回 |
| テスト内でdeploy_task.shを毎回source | 137ms/回 | func cache |
| bats直接全量実行 | 逐次4:51 | scripts/run_tests.sh（--jobs 8） |

## 計測値（劣化検知ベースライン 2026-04-15）

| 指標 | 値 | 閾値（これ超えたらリグレッション） |
|------|-----|------|
| deploy_task_template_only 1テスト(func cache有) | 88ms | 200ms |
| deploy_task_template_only 1テスト(func cache無) | 2164ms | 3000ms |
| template_generation 14テスト | 2.7s | 5s |
| ac_handling 48テスト | 25.8s | 35s |
| unit全量 --jobs 8 | 1:39 | 2:30 |
