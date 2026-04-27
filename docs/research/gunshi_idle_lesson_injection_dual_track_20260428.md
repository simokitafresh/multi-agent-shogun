# 軍師idle分析: 教訓注入二系統混在問題 (2026-04-28)

## 問い
cmd_2342(kagemaru) lessons_useful useful率0%(10件全て「対象外で未使用」)。GP-218/221/225で改善後もなぜ0%か。

## 発見
教訓注入に2系統が混在:
1. **related_lessons** (L1370-1395): universal+target_files型。最新教訓をID順で注入。→ lessons_usefulテンプレートに反映
2. **description埋込** (inject_related_lessons L1858): task-specific型。cmdのpurpose/target_path/context_filesでスコアリング。→ descriptionフィールドに「【注入教訓】」として直接記載

cmd_2342の実態:
- related_lessons注入: L503-L512 (universal最新10件)
- description埋込: L508,L536,L308,L300,L276,L389 (task-specific)
- 忍者がlessons_usefulに書いたID: description埋込のIDを使用
- related_lessonsのL503-L512は評価されず

## 因果鎖
2系統混在 → 忍者がdescription記載のIDをlessons_usefulに書く → related_lessonsテンプレートIDとの不一致 → useful率が実態を反映しない

## 10回繰返したら？
毎cmdで忍者がdescription埋込IDとrelated_lessonsテンプレートIDの不一致に遭遇 → 混乱×10回 = 負の複利

## 改善方向
- related_lessonsとdescription埋込を統合: lessons_usefulテンプレートにdescription埋込IDも含める
- または: description埋込IDをrelated_lessonsに統合し、1系統にする
