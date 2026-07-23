# cmd_4127 表フォント14px統一結果

- 検証日: 2026-07-23
- CDP実測正本: `docs/research/cmd_font_unify_14px_cdp_measured_20260723.md`
- 実装範囲: 本番CDPで特定した逸脱6表
- canonical: 本体14px、数値`ui-monospace` + `tabular-nums`、文字Inter、ヘッダ14px
- deterioration方向矢印: アイコン役割のため`text-lg` 18pxを意図的に維持（cmd_4119のcaption等役割除外と同型）

| 区分 | 修正前 | コード修正後 | 根拠 |
|---|---:|---:|---|
| 数値等幅漏れ | 125セル（48+26+28+11+12） | 0 | 対象数値classを`font-mono text-sm tabular-nums`へ統一 |
| 12pxヘッダ | 18セル（9+9） | 0 | annual/monthly returnsの列見出しを`text-sm`化 |
| 12pxカテゴリ | 8セル | 0 | deterioration typeセルを`text-sm`化 |
| 18px方向矢印 | 8セル | 8（意図的除外） | 色付き矢印は数値・文字ではなく方向アイコン |

ローカル検証: `npx tsc --noEmit` exit 0、対象class contract test 2/2 PASS、frontend `npm test` 354/354 PASS・SKIP0。本番デプロイ後の`getComputedStyle`全数再計測は将軍担当。

origin: `[[殿裁定_14px統一_20260723]] -> [[逸脱6表確定]] -> [[cmd_4127_表フォントcanonical化]]`
