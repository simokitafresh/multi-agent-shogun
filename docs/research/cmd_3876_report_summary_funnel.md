# cmd_3876 result.summary入口導線

## 結論

`result.summary`未記入13回反復は、提出時gateだけが止め、生成・書込み入口が空値を許したことが原因。入口を次の二段へ強化した。

1. `scripts/deploy_task.sh`生成テンプレートを`summary: "FILL_THIS"`へ変更し、「実施内容+検証結果の1行要約へ置換・自動補完禁止」を同位置とクイックリファレンスへ表示。
2. `scripts/report_field_set.sh`が`result.summary`への空文字、`''`、`""`、`FILL_THIS`を含む値をファイル書込み前にBLOCK。有効値だけを通す。

`skills/report-write/SKILL.md`にも同じ必須置換契約を追加した。値の推定・自動補完経路は追加していない。

## 二値証跡

| 計測 | 結果 |
|---|---|
| helper正常値 | PASS |
| helper空文字 | BLOCK |
| helper規約トークン残存 | BLOCK |
| report_field_set既存+新規fixture | 43/43 PASS、FAIL 0、SKIP 0 |
| deploy template fixture | 1/1 PASS、FAIL 0、SKIP 0 |
| shell構文 | 2/2 PASS |
| 成果物 | `test -s` PASS |

## 自動補完不在の確認

テンプレートが埋めるsummary値は規約トークン`FILL_THIS`のみで、helperは不正値を実値へ変換せずexit 1する。三態fixtureの空値・tokenケースでreportに値が書かれないことを確認した。

## 因果

`[[result_summary未記入反復発火]] -> [[事後検出のみで入口導線不在]] -> [[テンプレ生成警告+report_field_set入口検査]]`
