# 冷え観点の構造的分析 (2026-04-29)

## 現象
- ambiguity: 直近10件で0件 (zero_streak=10/10)
- adversarial: 直近10件で0件 (zero_streak=10/10)

## 分析

### cmd特性マトリクス (直近10件: cmd_2339-2346)
| cmd | type | changed_lines | blast_radius | 曖昧性 |
|-----|------|---------------|-------------|--------|
| cmd_2339-2346 | GS正規化Phase 3-5 | <200 | outputs配下 | 低(定型手順) |

### 因果鎖
GS正規化パイプライン連続(定型手順+小規模変更) → 曖昧性が構造的に低い → ambiguity拾えない
→ blast radius=outputs配下のみ + changed_lines<200 → adversarial不要

### 結論
冷えの原因は**cmd特性が均質**であること。軍師の観点欠如ではなく入力の特性。

### リスク
次に大型cmd(infra修正/新機能設計/CLAUDE.md変更)が来た時に惰性でambiguity/adversarialをスキップする危険がある。

### 対策(既存)
- GP-236: infra対象draft → adversarial_review.required:true (review_logヘッダL43)
- ambiguity観点シフト: 「表現の曖昧性」→「解釈の曖昧性」(review_logヘッダL51)
- Adaptive gating: gate_gunshi_startup.shが冷え警告を出す

### 判定
**構造的に正しい冷え。追加対策不要。次の非定型cmd時に再活性化を意識する。**
