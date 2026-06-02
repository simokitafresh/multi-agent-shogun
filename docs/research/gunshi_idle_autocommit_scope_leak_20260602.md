# auto_commit_before_clear scope未フィルタバグ
<!-- generated: 2026-06-02T23:20:00+09:00 by gunshi idle analysis -->

## バグ概要

ninja_monitor.sh `auto_commit_before_clear()` L338が`git add`で全未commit変更を拾い、忍者Aの成果物を忍者Bのauto-commitが包含する。

## 根因コード

```bash
# ninja_monitor.sh L338
printf '%s\n' "$regular_paths" | xargs -d '\n' git add -- 2>/dev/null || true
```

`regular_paths`は`filter_regular_auto_commit_paths`でフィルタされるが、このフィルタはファイルパターン(queue/*, logs/*等)のみ。**どの忍者の変更か**は考慮しない。

## 発生メカニズム

```
1. 忍者A(kotaro)がscripts/deploy_task.sh修正→未commit
2. 忍者B(hayate)がidle→/clear発火
3. ninja_monitorがhayateのauto_commit_before_clearを実行
4. L338: git add -- scripts/deploy_task.sh (kotaroの変更を含む)
5. L345: git commit -m "chore: auto-commit before /clear (hayate)"
6. kotaroの成果物がhayate名義でcommit
```

## 本セッション影響(4件)

| cmd | 忍者 | 混入先 | 影響 |
|-----|------|--------|------|
| cmd_3136 | kotaro | 7109446c(hayate auto-commit) | commit帰属誤り |
| cmd_3137 | hanzo | 7109446c(hayate auto-commit) | commit帰属誤り |
| training_kotaro | kotaro | 7898a094(hanzo batch) | commit帰属誤り |
| training_tobisaru | tobisaru | — | bc:no誤記入→GATE BLOCK |

## 既存防御

- L324-329: `preexisting_staged_paths`チェック → staged変更のみ。working tree変更はスルー
- L333: 30分cooldown → 頻度制限のみ。cross-ninja混入は防げない

## 修正案

### 案A: task scope フィルタ(推奨)

auto_commit_before_clear()内で、triggering ninjaのtask YAMLからtarget_path/files_modifiedを取得し、**それ以外のファイルをgit addから除外**。

```bash
# 疑似コード
ninja_scope_files=$(get_task_scope "$agent_name")  # target_path + files_modified
filtered_paths=$(printf '%s\n' "$regular_paths" | filter_by_scope "$ninja_scope_files")
printf '%s\n' "$filtered_paths" | xargs -d '\n' git add -- 2>/dev/null || true
```

### 案B: 全忍者pre-commit強制

ninja_monitorが/clear前にninja-commitスキルを実行。自分のcommitが終わってからauto-commit。

### 推奨: 案A

案Bはninja CLIへの介入が必要(稼働中CLI操作禁止に抵触しうる)。案Aはninja_monitor内部で完結。

## 因果リンク

- → [[ninja_monitor.sh]] auto_commit_before_clear L310-364
- → [[cmd_3136]] kotaro成果物がhayate auto-commitに混入
- → [[tobisaru BLOCK]] bc:no誤記入の遠因(auto-commit混入で帰属が不明確)
- → [[洗脳#5]] 4件検出しながら「次のサイクルで」と先送りした
