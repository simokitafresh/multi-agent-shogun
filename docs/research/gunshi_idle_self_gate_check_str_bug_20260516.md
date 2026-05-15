# self_gate_check str型バグ — なぜなぜ7回

## 現象
gate_report_format.shが`self_gate_check: is str (must be dict)`で22件FAIL。全忍者で発生。

## なぜなぜ
1. なぜstr型？ → gate_report_format_main.pyがyaml.safe_loadでstr判定
2. なぜstr値がYAMLに入る？ → report_field_set.sh経由でトップレベル書込み
3. なぜreport_field_set.shがstr書込みを許可？ → L191-196がPASS/FAILのscalar値を受付
4. なぜscalar書込みでdict消失？ → yaml_field_set.shがトップレベルフィールドをscalar上書き
5. なぜ忍者がトップレベルで書く？ → self_gate_checkの4子キーをまとめて更新しようとする
6. なぜ子キーで書かない？ → 忍者は「self_gate_check PASS」で全部PASSにできると推測
7. 根因: **report_field_set.shのself_gate_checkバリデーションがscalar受付を許可する構造バグ**

## 再現手順
```bash
tmpfile=$(mktemp)
cat > "$tmpfile" << 'EOF'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
EOF
bash scripts/report_field_set.sh "$tmpfile" self_gate_check PASS
cat "$tmpfile"
# → self_gate_check: PASS (dict消失)
```

## 影響
- 22件FAIL発生。21件は忍者自力修正(8-17秒)で回復。1件STUCK
- 修行cmd/通常cmd両方で発生(11件ずつ)
- 全忍者で発生(kagemaru 25件, hayate 16件, saizo 15件, kotaro 2件, hanzo 2件)

## 修正案
report_field_set.shのself_gate_check検証を変更:
- トップレベル`self_gate_check`書込みをBLOCK（「子キーで書け」とガイド）
- `self_gate_check.lesson_ref PASS`等のdot notation書込みのみ許可

## 因果鎖
忍者がself_gate_check全体をPASSで上書き→yaml_field_setがdict→scalar→gate FAIL→autofix不発(フィールド存在)→忍者手動修正(8-17秒)→無駄サイクル。
トップレベル書込みBLOCK→dot notation必須→dict構造保持=正の複利(22件/月の無駄サイクル根絶)
