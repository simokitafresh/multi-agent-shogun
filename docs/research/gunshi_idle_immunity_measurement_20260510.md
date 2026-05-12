# 免疫系効果計測 — 2026-05-10

## gate偽陽性修正効果
- 修正前(~15:57): FAIL率28.5%(39/137)。AC self-verification 51%が偽陽性
- 修正後(16:00~): FAIL 0件 / PASS 21件 = FAIL率 0%
- 根因: 中間状態FAIL記録(hanzo 4f47f4b4) + ACカウントバグ(4e4f0bb0)

## skill品質スコア補正
- 補正前: 82.7%(467/565)
- 補正後: 85.5%(467/548, 偽陽性19件FALSE_POSITIVEマーク)
- 直近10件: 全PASS

## WA率推移(月次)
| 月 | WA:true | total | WA率 |
|----|---------|-------|------|
| 3月 | 26 | 51 | 51.0% |
| 4月 | 78 | 683 | 11.4% |
| 5月(10日時点) | 1 | 2 | — (N<10) |
| **直近37件** | **0** | **37** | **0.0%** |

## cmd_save WARN推移
- 累積TOP: research_tool(35), q11(28), parity_ac(26), ac_phase(26)
- Level5化済み: 7件(前セッション+本セッションD0)
- 直近10cmd: WARN 0件
- 未対処3種(gunshi_ref/ac_param/q8_compound): Level2が最適。累積減少傾向

## Sonnet FAIL率
- 全期間: GPT平均21.2% vs Sonnet平均44.0%(2倍差)
- 直近500件: GPT 15.5% vs Sonnet 32.5%
- 根因: テンプレート遵守率低(hanzo assumption_invalidation 34件, tobisaru bc MISSING 79件)
- 対策: cmd_2662(instructions Level5化) + cmd_2665(テンプレートprefill)
- 効果計測: 次回Sonnet忍者配備後に追跡

## insight dedup効果
- 修正前: セッション平均10+件の自動生成insight → 手動resolve連鎖
- 修正後: dedup check追加(02c57247)。同一payload_labelのpending存在時はスキップ
