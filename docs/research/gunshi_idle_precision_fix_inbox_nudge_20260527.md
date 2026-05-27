# スキル推薦precision偽陽性根因分析 — inbox nudge問題

## 日付
2026-05-27

## 発見
startup gateのスキル推薦precision 10% (8/81) ALERTを調査。

### 根因
- `inbox1` (inbox nudge) のsha256 = `19f9616863a1fba30374852021a25b613fbb11249e63b068cfdf039bfa3b1058`
- skill_recommend_logで86/155件(55%)が同一hash → 全てinbox nudge
- 家老67回+将軍17回+軍師2回
- nudgeがUserPromptSubmitフックを通りsemantic_searchにマッチ→偽推薦生成

### 2番目のhash
- `b4cc59c8...` = 12件(家老のみ)。正体未特定。影響規模は小さい

### 修正
- prompt_state_inject.sh L249に `[[ ! "$prompt_text" =~ ^inbox[0-9]+$ ]] || return 0` 追加
- 10文字下限フィルタは日本語短文(6文字)を弾くため撤回
- commit: 2e25cf50

### 効果見込み
- 推薦ログから86件除外 → precision ~10% → ~32%
- 正当プロンプト("inbox確認して"等)は完全一致regex不一致で通過

### セマンティック監査
- 6スクリプト×2カテゴリ(silent_failure+side_effect)
- P0=0件。全件FP/安全
- エージェント偽陽性1件: `[[ ! X =~ pattern ]] || return 0`の評価順序誤読

### CS WARN修正
- 9件のconsultationエントリにcs_checklist+operational_simulation遡及追記
- gate再確認: PASS(0件WARN)
