# report publication 二重ループ実験

- 実施日: 2026-07-20
- 固定base: `bde28d2595808ee01fd94292624d68d47d1747a5`
- 環境: repo内isolated shared clone `.tobisaru-publication.j10Rqn/clone`
- fixture: 同一terminal report schemaを候補ごとに10件生成。配送stubはflock下で全文identityをdedupeし、呼出総数と一意publish数を別計測した。
- 計測: `report_field_set.sh --batch` 呼出前後のwall clock。deferred候補は呼出元解放までを計測し、全background完走後に成果物を検査した。

## 実測

| 候補 | N | median_ms | max_ms | publish呼出 | 一意publish | report欠落 | report重複 | delivery identity不一致 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 現行（二重publish: reconciler + sync） | 10 | 347 | 395 | 20 | 10 | 0 | 0 | 0 |
| single publish（syncのみ） | 10 | 408 | 499 | 10 | 10 | 0 | 0 | 0 |
| deferred安全分離 | 10 | **4** | **8** | 10 | 10 | 0 | 0 | 0 |
| ext4 staging + single publish | 10 | 467 | 2700 | 10 | 10 | 0 | 0 | 0 |

## 結論

最速はdeferred安全分離（median 4ms、現行比 -98.8%）。terminal reportのatomic永続化を同期成功境界とし、deliveryをbackgroundへ分離する候補を採用する。全10件のbackground完走後にreport欠落0、重複0、delivery identity不一致0、一意publish 10/10を確認した。

single publishは二重呼出を20→10へ削減したがwall中央値は347→408msで速度改善なし。ext4 stagingも中央値467msかつ最大2700msで不採用。現行二重publishはdedupe後の一意配送こそ10/10だが、呼出自体は20回である。

注意: 本偵察はisolated clone内の可逆fixture実験のみ。本体・gate・hookは未変更。deferred採用時は、terminal bytesをdurable outboxとして後続reconcilerが必ず回収する既存設計意図を維持し、同期deliveryを除去する実装検証が別途必要。
