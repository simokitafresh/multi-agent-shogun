# Idle S8: Workaround+Review Trend分析 (2026-04-02)

## WA直近10件分析

| cmd | ninja | category | WA | 根因 |
|-----|-------|----------|-----|------|
| cmd_1637 | kagemaru | bc_incomplete | false | GP-133未実装 |
| cmd_1641 | tobisaru | bc_incomplete | false | GP-133未実装 |
| cmd_training_L4_R10 | kotaro | ci_red_block | false | 先行commitがCI破壊 |
| cmd_1671 | hayate | scout_gate_bypass | true | scout_exempt未設定 |
| cmd_1672 | kagemaru | scout_gate_bypass | true | scout_exempt未設定 |
| cmd_1671 | hayate | uncategorized | true | WAデータ品質不良(detail:'false') |
| cmd_1674 | hayate | clean | false | - |
| cmd_1675 | kagemaru | clean | false | - |
| cmd_1676 | kotaro | clean | false | - |
| karo_direct | hanzo | karo | true | bats全量OOM 4.3GB |

## 因果推論

### bats OOM (最重要)
```
テスト範囲指示なし → 忍者がbats tests/unit/全量実行 → 4.3GBメモリ消費 → OOM Kill
→ 家老が直接commit → workaround
```
**行動**: draft review SG3でテスト範囲が明示的か確認。「関連テストのみ」の指示がACにあるか。

### scout_gate_bypass (2件)
```
training/karo_direct配備 → deploy_task.shのscout_gate → scout_exempt未設定 → BLOCK
→ 家老がbash cat手動配備 → workaround
```
**行動**: GP-134(AWKバグ修正)で部分解消。追加でtraining/karo_direct配備時のscout_exempt自動設定が必要。

### BC不完全 (2件, 同根GP-133)
```
BCテンプレートがcommitのみ → 忍者がAC自己検証をスキップ → WA/FAIL
```
**行動**: GP-133(BCテンプレート拡張)の実装推進を家老に提案。

## review log傾向

- 総エントリ: 463件(本ファイルの600件はstats含む)
- 直近FAIL: cmd_1631系(BC不完全), cmd_1677(draft RC: Codex instruction前提崩壊)
- accuracy: 100%(228/228 CLEAR)。但し66件GATE未確認
- WA率推移: post-LG006:0%(N=5)→bats OOMで1件発生

## 未自動化教訓

- LG012(チェックリスト隣接Step制約転写)がSG10追加予定だが未実装。自動化候補。
