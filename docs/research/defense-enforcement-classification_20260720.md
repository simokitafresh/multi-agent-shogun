# 防御強制方式の全量分類 — 2026-07-20

## 結論

BLOCK。一次走査で対象候補は `scripts/gates/*` 59件、`scripts/hooks/*` 24件、`scripts/ninja_monitor.sh` 1件、`scripts/inbox_write.sh` 1件の計85ファイルと確定したが、「各防御」の抽出単位をファイル・関数・分岐のどれにするか未定義である。実例として `scripts/inbox_write.sh` だけでも複数の独立したBLOCK、自動記録、自動状態遷移を含むため、85ファイルを85防御とみなすと対象縮小になる。全量一致とsource path:lineを捏造せず満たせないため分類値は公開しない。

さらに、taskへ注入された三層記憶には2026-07-20 03:02:41の殿裁定として「分類台帳を作れの指示は撤回」と記録されている一方、本taskは03:08:47発行で同じ分類台帳を命じている。どちらを正本とするかは忍者の裁量外であり、decision BLOCKとする。

## 一次走査

| 計測 | 値 | 一次証跡 |
|---|---:|---|
| gatesファイル | 59 | `find scripts/gates -maxdepth 1 -type f \| sort \| wc -l` |
| hooksファイル | 24 | `find scripts/hooks -maxdepth 1 -type f \| sort \| wc -l` |
| monitor/inbox | 2 | `scripts/ninja_monitor.sh`, `scripts/inbox_write.sh` |
| ファイル母集団 | 85 | 59 + 24 + 2 |
| 表示型 | 未確定 | 防御抽出単位が未定義 |
| 構造型 | 未確定 | 同上 |
| 未分類 | 85ファイル以上 | 1ファイルに複数防御があるため防御件数の上限も未確定 |

再集計コマンドを2回実行してファイル母集団85は一致させる。これは防御件数の一致を意味しない。

## E1 / E4の一次証跡

| ID | 現状 | source | 発火ログ | 人手秒 | 二値基準 |
|---|---|---|---|---|---|
| E1 | 構造型。CI RED・idle忍者・未配備cmdの条件成立時に `deploy_task.sh` を直接実行し、結果をgate logへ記録する | `scripts/ninja_monitor.sh:66`, `scripts/ninja_monitor.sh:131`, `scripts/ninja_monitor.sh:169`, `scripts/ninja_monitor.sh:173` | `logs/gate_fire_log.yaml`。本走査では該当run件数未集計 | 自動処理のため0秒（人手操作なし） | 条件成立runで `auto_deploy=1` が1件、duplicate=0、deploy失敗=0ならyes |
| E4 | 構造型の実例候補。報告完了時のtask status/done_at/completed_atを自動更新する | `scripts/inbox_write.sh:2396`, `scripts/inbox_write.sh:2469`, `scripts/inbox_write.sh:2478` | 専用E4識別子の一次ログを確認できず | 自動処理のため0秒（人手操作なし） | 完了通知1件につきtask status=doneかつ時刻2項目が非空ならyes |

E1の発火回数とE4の専用ログ件数は未計測であり、AC2はno。E4という識別子自体がsourceにないため、上記対応が設計意図どおりかも家老確認が必要である。

## 品質計測

| 指標 | 値 | 判定 |
|---|---:|---|
| false_positive | 0件を主張しない | 全防御母集団が未確定のため分母なし |
| detector_fp_rate | 算出不能 | 分母となる分類件数が未確定 |
| gate_fire_log | BLOCK | 母集団不一致リスク、source粒度未定義、E1/E4発火回数欠落 |
| 既存コード変更 | 0ファイル | 本文書のみ追加 |

## 解消条件

1. 「各防御」の単位を、独立した発火条件と作用の組として機械抽出できる定義に固定する。
2. 殿の撤回記録と03:08:47再発行の優先関係を家老が確認する。
3. E1/E4の識別子とログqueryを指定し、発火回数を一次ログから集計する。

origin: `[[殿裁定_分類台帳撤回_20260720]] -> [[task再発行の前提矛盾]] -> [[全量分類BLOCK]]`
