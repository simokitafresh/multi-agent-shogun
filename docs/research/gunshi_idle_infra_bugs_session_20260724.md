# 軍師セッション時間消費分析 — インフラバグ4件 (2026-07-24)

## 概要

本セッション(11:14-12:38)でレビュー処理に約38分の追加時間消費が発生。根因はインフラバグ4件。

## BUG一覧

| # | 対象 | 状態 | 時間消費 | 根因 |
|---|------|------|---------|------|
| BUG1 | gate_gunshi_cs_checklist.sh awk indent | **D0修正済** (a87ebc1e4) | ~15分 | `{4,}`パターンがPython yaml.dump 2spインデントを検出不能 |
| BUG2 | review_bundle.py result:true vs yes | **未修正** | ~10分 | gate_report_format.sh=寛容 vs review_bundle.py=厳格。判定基準不一致 |
| BUG3 | CS checklist L6 cmd_\d+ 誤抽出 | **未修正** | ~8分 | awk(L1086-1092)がreport_review全文からcmd_\d+抽出→context_push内文脈参照を誤検出 |
| BUG4 | yaml_field_set.sh リスト文字列化 | **未修正** | ~5分 | `[a,b,c]`形式をYAMLリストでなく文字列`"[a,b,c]"`として保存 |

## BUG1: awk indent pattern (修正済)

- **現象**: GP-262(6件) + cmd_3573-verified_files(10件) = 16件の偽陽性WARN
- **根因**: gate_gunshi_cs_checklist.sh L175/L765/L773のawkパターン`{4,}`がgunshi_log_append.sh(Python yaml.dump)の2spインデントYAMLを検出不能
- **修正**: `{4,}` → `{2,}` (3箇所)。commit a87ebc1e4
- **効果**: 16件偽陽性→0件

## BUG2: review_bundle.py result判定 (未修正)

- **現象**: cmd_4151のbinary_checks `result: true` (YAML boolean) を review_bundle.py / review_approval.sh が拒否
- **根因**: gate_report_format.shはtrue/yesどちらもPASSだが、review_bundle.pyはyes文字列のみ受入
- **影響**: completed報告は不変(fingerprint保護)のためresultをyesに修正不可→手動inbox_write回避
- **修正案**: review_bundle.pyのbinary_checks判定で`result in ("yes", True, "true")`を許容

## BUG3: L6 cmd_\d+ 誤抽出 (未修正)

- **現象**: cmd_4034/cmd_4118がL6-洗脳#1でWARN(レビュー未実施)
- **根因**: CS checklistのawk(L1086-1092)がreport_review typeのinbox全文からcmd_\d+を抽出→review_context_push本文内の文脈参照cmd番号も誤検出
- **修正案**: `[review_context_push]`〜`[/review_context_push]`ブロックを除外してからcmd_\d+抽出

## BUG4: yaml_field_set.sh リスト文字列化 (未修正)

- **現象**: finding_categoriesをyaml_field_set.shで更新すると`"[assumptions, numbers, ...]"`文字列になる
- **根因**: yaml_field_set.shが`[`で始まる値をYAML flow sequence (リスト)でなくquoted scalar (文字列)として保存
- **修正案**: 値が`[`で始まり`]`で終わる場合、YAML flow sequenceとして解釈して保存

## 因果リンク

- → [[gate_gunshi_cs_checklist]] GP-262/verified_files/L6偽陽性
- → [[review_bundle.py]] result判定基準不一致
- → [[yaml_field_set.sh]] リスト型保存
- → [[LG014]] 忍者ミスに見える問題はインフラ真因を疑え
