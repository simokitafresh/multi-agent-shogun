# verdict_override WA パターン分析
<!-- gunshi idle analysis 2026-04-11 -->

## 結論

verdict_override WA 5件。2カテゴリ: (A)commit一律注入3件、(B)進行中月パリティ時差2件。
カテゴリA: GP-172/173で頻度低下。カテゴリB: L586登録+DC提出済みだが構造的再発(10回→10回override)。
殿裁定(当月除外可否)待ち。直近clean cmdでは0件だがパリティcmdでは100%再発。

## 分析

| # | cmd | 根因 | 対策 |
|---|-----|------|------|
| 1 | cmd_karo_fix_flock | AC推奨/必須混在 | GP-173(WARN)実装済み |
| 2 | cmd_root_dashboard_auto | gitignore対象 | GP-172(scout省略)で部分解決 |
| 3 | cmd_1817 | ゴールデンデータ日差 | L586登録済み |
| 4 | cmd_1821 | 研究cmd出力 | **未対策** |
| 5 | cmd_1855 | 進行中月パリティ時差(2日差diff=0.0172) | L586パターン2件目。DC提出済み |

## 因果鎖

```
deploy_task.shがcommit binary_checkを全cmd一律注入
  → 研究cmd/gitignoreにも適用
  → commitする成果物なし
  → check=no
  → GATE BLOCK
  → 家老verdict_override
  → WA
```

10回繰り返したら10回override = 負の複利。

## GP候補1: 研究cmd commit check制御

cmd_save.shのq_typeがresearch/analysis/experimentの場合、commit binary_checkをoptionalまたは注入しない。

- impact予測: verdict_override 1/5件(20%)の防止
- 発生頻度: 直近30件中1件(3.3%)。直近8件中0件
- 優先度: 低(頻度低下中+既存対策機能中)
- 判定: **保留。次の研究cmd verdict_overrideが発生したらGP化**

## GP候補2: パリティcmd進行中月除外

パリティcmdのAC設計時に「完了月のみ比較」を自動注記する。

- impact予測: verdict_override 2/5件(40%)の防止
- 発生頻度: パリティcmd実行時に毎回(cmd_1817,cmd_1855で2/2)
- 根因: AC設計に進行中月のデータ時差が考慮されていない
- 因果鎖: GS CSV作成日≠本番recalculate日→進行中月差異→AC "全期間"→binary_check no→BLOCK→override
- 殿裁定待ち: ninja decision_candidate(cmd_1855)で提出済み。当月除外は殿の設計判断
- 判定: **殿裁定後に対策決定。裁定=当月除外なら cmd_save.shにパリティcmd当月除外注記WARNをGP化**

## 既存対策の効果

- GP-172(2026-04-09): scout cmd commit check省略 → gitignore偽陽性根絶
- GP-173(2026-04-08): 推奨/SHOULD/optional混在WARN → 推奨混入防止
- L586(2026-04-09): ゴールデンデータ日差パターン教訓登録
- 直近8件WA率0%: 対策の効果を示唆(パリティcmd除く)
