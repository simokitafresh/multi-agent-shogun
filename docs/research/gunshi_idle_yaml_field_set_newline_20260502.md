# yaml_field_set.sh 改行エスケープ欠落分析

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-02
- 起源: idle自走 karo_workarounds cmd_2435 deploy_error 深掘り

## 事象

cmd_2435でdeploy_task.shのdescription注入時にバックスラッシュ混入→YAML引用破損。
家老がyaml_field_set.shで手動修正(WA)。

## 根因

deploy_task.sh L4246:
```bash
yaml_field_set "$task_file" "task" "description" "${note}"$'\n'"${existing_desc}" || true
```

`$'\n'`で改行を含む文字列をyaml_field_set.shに渡す。
yaml_field_set.sh(awk実装)に改行/バックスラッシュのエスケープ処理がない。
awkが改行をYAML構造の一部として解釈→引用破損。

## 影響範囲

- yaml_field_set.shは全運用YAMLの書込みに使用(queue/, tasks/, inbox/, reports/)
- 改行を含む値を渡す箇所: deploy_task.sh L4246(再配備引継ぎ description)
- grep結果: 他に改行を含む呼出しは未確認(今回のパターンのみ)

## 修正案

### Option A: 呼出し側で改行回避
deploy_task.sh L4246の`$'\n'`を` | `(パイプ+スペース)に変更。改行の代わりに区切り文字。
最小コスト。ただし根本修正ではない。

### Option B: yaml_field_set.sh にYAML引用処理追加
値に改行/特殊文字が含まれる場合、ダブルクォートで囲みエスケープ。
根本修正だがawk実装が複雑化。テスト必要。

### 推奨

Option A(即効)を先行し、Option Bは家老判断。
理由: 改行を含むyaml_field_set呼出しは現状1箇所のみ。根本修正のROIは低い。
