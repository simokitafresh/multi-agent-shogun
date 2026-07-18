# テストdefault-delete原則 — 全PJ・全リポジトリ共通ルール（殿裁定 2026-07-19 02:09-02:13）

正本。context索引→本書→実装(ci-test-elimination設計書・test_necessity契約)の順で参照。

## §1 ルール本文

**実装時テストは作成→PASS→即削除がデフォルト。永続化できるのは防御対象宣言（守る不変量）を持つ契約テストのみ。**

- 実装時テストの価値は「実装検証の瞬間」に消費され尽くす。以後は保守負債+FP源（殿原則: テスト=負債）
- 削除はgit履歴で可逆。防御空白が事故で露呈したら復活+契約テスト昇格
- 永続化条件 = 防御対象宣言: どの不変量（exactly-once / 安全境界D001-D009 / 本番パリティ / receipt終端契約 / 通知喪失0 等）を守るかを1行で明示できること
- 選別器 = test_necessity入口契約（配備契約の宣言欄+軍師レビュー観点、2026-07-18実装LGTM）

## §2 根拠（一次実測 2026-07-18〜19）

| 事実 | 数値 | 出典 |
|---|---|---|
| 30日FAIL実績で価値を示したテスト | 4,922件中487件 = **9.9%** | 家老全数監査 blt_20260719_015931 |
| 回帰検知の実績 | GA-291再発・L901 6重配備等、全て**契約テスト**が検知。実装詳細テストの回帰検知実績なし | knowledge:507a3ce9 ほか |
| CI肥大の帰結 | Unit 4,740件・493秒/run、FAIL→修正→push→8分の往復×5周/夜 | blt_20260719_001259 |
| 削減後push層 | 487件+契約、wall見積120-170秒（-79〜85%） | 同監査 |

## §3 既知の穴7件と二値手当（将軍3+軍師敵対検証4、全て承認済み）

| # | 穴 | 二値手当 |
|---|---|---|
| 1 | 宣言判断の属人性（契約テストを認識せず削除） | /ninja-commit削除はリストをdiff明示、軍師レビュー必須確認「削除一覧に契約テスト混入なし」 |
| 2 | 宣言インフレ（削除回避の形式宣言） | 新規テスト宣言率を受動計測、>30%でtest-hygiene lane自動発火 |
| 3 | 境界内側の回帰網喪失 | **意図した受容**。事故→教訓→契約テスト昇格ループが受け皿（初回事故コストは払う設計） |
| 4 | 既存テスト削除の判定盲点 | tests/パスが純減(-行>+行)ならdeletion_justification必須 |
| 5 | fixture共有の消失波及 | 削除時に`grep -rn 'source.*削除ファイル名' tests/`被参照数=0を確認 |
| 6 | 正当重複のescape hatch不在 | overlaps_existing=trueはregression_justification 1行でBLOCK免除 |
| 7 | 2忍者同時判定race | commit時に他commit由来のtests/削除を検出したら即停止 |

## §4 運用の3段構え（作らない・貯めない・掃除を人が覚えない）

1. **予防（入口）**: test_necessity契約 — 新規テストは防御対象宣言+重複なし確認。宣言なし=commit時自動削除
2. **削減（過去分）**: push層487件へ縮小。移送分は宣言可能なもののみ残す再監査、他は削除（30日観察キューは不要化）
3. **恒常掃除**: campaign-lane「test-hygiene」lane — push wall>170秒 / FAIL実績0比率>20% / 純増>50件/週 の計測値で棚卸しwaveが自動発火

## §5 適用範囲

全プロジェクト・全リポジトリ（multi-agent-shogun / DM-signal / 以後の新PJ）。CLAUDE.md Test Rules・instructions・ninja-commit SKILL・各projects/{id}.yamlへ反映（家老実施）。

## §6 三層貫通の記録

- 記憶DB: knowledge:cd27be893bac02f2（方針+穴1-3）、knowledge:88765bf5e302d20f（穴4-7）
- セマンティック: semantic-map「テスト品質統合フレームワーク」行へalias貫通（default-delete/防御対象宣言/deletion_justification等、commit bfc4d7c21）
- Obsidian: 下記因果リンク

## 因果リンク

`[[殿裁定_default_delete_test_20260719]] -> [[テスト=負債の純粋適用]] -> [[契約テストのみ永続]]`
`[[default_delete_policy]] -> [[adversarial_review_4穴]] -> [[deletion_justification+fixture_reach+escape_hatch+race]]`
`[[CI肥大4922件]] -> [[30日FAIL実績9.9%]] -> [[push層487+test-hygiene lane]]`

origin: [[殿裁定_default_delete_test_20260719]] -> [[将軍3穴+軍師4穴の二値手当]] -> [[全PJ共通ルール正本]]
