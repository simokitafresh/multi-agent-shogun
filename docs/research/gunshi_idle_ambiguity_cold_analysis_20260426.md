# Ambiguity観点 Zero-Streak根因分析

## 日時
2026-04-26T14:55:00+09:00 (gunshi idle自走)

## 事象
gate_gunshi_startup.sh Adaptive Gating: ambiguity zero_streak=7/10

## 根因分析

### 定量事実
- 直近10件のfinding_categoriesでambiguity記録: 1件(7連続ゼロ)
- 直近10件のcmd: Vercel圧縮(2295/2296)・context整備(2294)・CDP計測(2291)・hook実装(2293)
- cmd_save.shのq8_scope_expression + q_ambiguityチェックが上流で曖昧性を除去

### 因果鎖（3段）
1. cmd_save.shがq8(縮小表現)とq_ambiguity(明示的曖昧性記入)を強制 → 将軍が曖昧な表現をcmd設計段階で除去
2. 除去済みcmdが軍師レビューに到達 → blatant ambiguityがゼロ
3. 軍師がambiguity finding=0で記録 → zero_streak増加

**構造的帰結**: cmd_save gateの成功 = 軍師ambiguity検出の減少。免疫系Phase 5の正常動作。

### gate検出不能な残留ambiguity（verdict_override分析）

karo_workaroundsのverdict_override 11件の根因分析から5パターン特定:

| # | パターン | 例 | gate検出可能性 |
|---|---------|-----|--------------|
| 1 | 推奨 vs 必須の混同 | ACに推奨事項が必須化 | 不可(意味解析必要) |
| 2 | 固定値の時間依存 | AC2=118固定→並行cmdで変動 | 不可(並行cmd状態必要) |
| 3 | データ鮮度の暗黙前提 | ゴールデンデータ取得日差 | 不可(ドメイン知識必要) |
| 4 | commit不要ファイルへのcommit AC | gitignore対象にcommit要求 | 一部可能(gitignore照合) |
| 5 | 研究cmd output取扱い | commit対象外なのにcommit check | 一部可能(scope_mode照合) |

パターン1-3は**ドメイン知識・文脈・並行状態**がないと検出不能 → **軍師ambiguityチェックの固有付加価値**。

### 冷え判定

- **盲点ではない**: 上流gateが捕捉しているため軍師到達時にはゼロが正常
- **改善余地あり**: 残留パターン1-3は上流gate非対応。軍師が唯一の検出点
- **対策**: ambiguity checkを「表現の曖昧性」から「解釈の曖昧性」にシフト

## 提案

### 観点シフト: 表現 → 解釈

現在: 「cmdの指示が曖昧な箇所」を探す → 上流gateと重複
改善: 「忍者が異なる解釈をしうる箇所」を探す → 上流gateが非対応の領域

具体的チェックポイント:
1. **ACの数値は固定か可変か**: 並行cmd/時間経過で変わる数値がACに固定値で入っていないか
2. **推奨と必須の分離**: 「〜すべき」「〜が望ましい」がACに含まれていないか（推奨はnotesへ）
3. **暗黙のデータ前提**: 参照データの取得タイミング・鮮度が明示されているか

### 適用条件

全てのdraft reviewで適用(Vercel圧縮等の機械的cmdも例外なし)。ただし「解釈ambiguity検出」として記録。finding_categories に `ambiguity` を積極的に記録する。

## 複利の問い

この観点シフトを10回繰り返したら: 正の複利。AC固定値問題(verdict_override 2件)、推奨/必須混同(verdict_override 1件)が事前検出可能に → workaround削減 → 家老CTX節約。
