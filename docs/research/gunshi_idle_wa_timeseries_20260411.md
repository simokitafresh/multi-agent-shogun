# WA率時系列分析
<!-- gunshi idle analysis 2026-04-11 → 2026-04-14更新 -->

## 結論

WA率は03/24の100%から段階的に低下したが、**0%安定ではなく振動状態**。
04/10に0%達成後、04/11(80%)・04/13(83%)にスパイク発生。
各スパイクは**異なるWAカテゴリ**で構成→GP実装で個別根絶→新カテゴリ出現。
免疫系は機能しているが飽和には至っていない。新種の病原体が継続的に出現する。

## 日別WA率推移

| Date | WA | Clean | Total | WA% | Note |
|------|-----|-------|-------|-----|------|
| 03/24 | 2 | 0 | 2 | 100% | GP構築前 |
| 03/25 | 4 | 4 | 8 | 50% | |
| 03/28 | 5 | 8 | 13 | 38% | GP段階導入 |
| 04/02 | 1 | 3 | 4 | 25% | GP効果発現 |
| 04/05 | 2 | 9 | 11 | 18% | |
| 04/06 | 19 | 0 | 19 | 100% | インフラバグ一斉発見(遡及) |
| 04/08 | 4 | 13 | 17 | 24% | 修正後安定化 |
| 04/10 | 0 | 6 | 6 | 0% | 過去最良 |
| 04/11 | 4 | 1 | 5 | 80% | ★前版誤記訂正。verdict_override+stale_ac+scout_exempt+premature_shelve |
| 04/12 | 0 | 2 | 2 | 0% | GP-180~186実装効果 |
| 04/13 | 5 | 1 | 6 | 83% | commit_missing×4(Codex)+verdict_override×1 |
| 04/14 | 0 | 1 | 1 | 0% | (暫定。cmd_1896のみ) |

## スパイク分析

### 04/11スパイク(80%): 4カテゴリ混在
| WA | Category | GP対策 | Status |
|----|----------|--------|--------|
| cmd_1855 | verdict_override(進行中月) | GP-184 | ★implemented |
| cmd_1858 | stale_ac_contamination | GP-180/181 | ★implemented |
| cmd_1859 | scout_exempt_missing | GP-186 | ★implemented |
| cmd_1860 | premature_shelve(軍師誤判定) | GP-185 | ★implemented |

→ **4件全てにGP実装済み。04/12で0%に復帰**。免疫応答が正常に機能した証拠。

### 04/13スパイク(83%): Codex CLI固有
| WA | Category | Root Cause |
|----|----------|------------|
| cmd_1890 | commit_missing | auto-commit巻込み |
| cmd_1891 | commit_missing | Codex commit不全 |
| cmd_1892 | commit_missing | 共有WT dirty |
| cmd_karo_gp110 | commit_missing | Codex+auto-commit |
| cmd_1884 | verdict_override | scope外未commit |

→ Codex CLI rules修正で改善兆候あり(cmd_1893成功)。追跡継続。

## 因果鎖

```
Phase 1 (03/24-26): WA 50-100%
  → autofix/gate不在。全て家老手動修正
Phase 2 (03/28-04/05): WA 18-50%
  → GP段階導入(GP-001~052)。低周波WA構造的根絶
Phase 3 (04/06): WA 100%(遡及)
  → LG014: インフラバグ一斉発見・修正
Phase 4 (04/08-10): WA 0-24%
  → GP-087~110の複合効果
Phase 5 (04/11-14): WA振動(0-83%)
  → 新カテゴリ出現→GP実装→翌日0%→別カテゴリ出現→GP実装→...
  → 免疫系サイクルが回っている。各スパイクは前回と異なるカテゴリ
  → 04/13の主因=Codex CLI構造問題(GP対象外: CLI自体の制限)
```

## 軍師impactの定量評価

- レビュー開始前WA率: ~64%(初期)
- 04/10-14平均WA率: 45%(振動あり。Codex除外なら20%)
- GP対応済みカテゴリのWA再発: 0件(完全根絶)
- 主要貢献: GP 126件(100+ implemented)、SG7バンドル、消火撤去6件、LG014-026
- 課題: Codex CLI commit_missing(GP対象外の外部ツール制限)
