# report-write batch採用 CoDD Spec

## 問題

`scripts/report_field_set.sh`には50フィールドを1 process・1 flock・1 atomic replaceで更新する`--batch` laneが存在するが、`skills/report-write/SKILL.md`の正規手順は12項目以上の逐次CLI呼出しを列挙している。このため実装済みの高速laneが忍者の通常報告フローへ届かず、報告整形が品質合格スループットを支配する。

## 定量プロファイル（2026-07-18実測）

| 経路 | 対象 | 壁時計 | 品質結果 |
|---|---:|---:|---|
| 現行実務の逐次記入 | 半蔵ledger hotfix報告（gate修正往復込み） | 80秒 | 最終PASS |
| 既存batch fixture | 50フィールド | 94ms | 1/1 PASS、FAIL0、SKIP0、atomic_publish=1 |

期待改善幅は`80,000ms → 94ms`相当（-99.88%）。80秒にはgate修正往復を含むため純粋なsetter差分とは分離するが、50フィールド94msはbatch laneの実測上限として採用する。

## 根因

1. `skills/report-write/SKILL.md` Step 2が逐次`report_field_set.sh`呼出しを正解として提示している。
2. `--batch`はコードと専用テストには存在するが、通常報告の消費者契約へ接続されていない。
3. batch使用を強制する静的契約テストがなく、今後も逐次例へ回帰できる。

## リファクタリング対象

### R1: report-writeの既定経路をbatchへ変更

- 初回報告完成は全フィールドをYAML mappingへ集約し、`bash scripts/report_field_set.sh --batch "$REPORT"`を1回だけ実行する。
- `status`は全必須値・binary checks・commit hashを同一payloadへ入れ、部分公開を禁止する。
- 既存completed報告の修正は`status: revision_requested`を含む単一batchでunlock→更新→terminal再公開する。
- 単一フィールドCLIは診断後の非terminal局所補正だけに限定し、通常Step 2から除外する。

### R2: skill契約テスト

- `skills/report-write/SKILL.md`が`--batch`を既定手順として含むこと。
- Step 2に逐次`bash scripts/report_field_set.sh "$REPORT" <field>`列挙が残らないこと。
- 50フィールドbatchが1000ms未満、FAIL0、SKIP0、atomic publish 1回であること。
- invalid binary result、terminal readiness不足、completed直接変更は全てBLOCKかつbyte不変であること。

### R3: 計測と回帰防止

- Beforeは実務80秒、Afterは同等の完成payload 50フィールド壁時計を記録する。
- false positiveはvalid fixture BLOCK件数0、false negativeはinvalid fixture通過件数0。
- report gate最終判定を維持し、batch成功をgate成功の代替にしない。

## 実施順序

1. 現行batch laneと専用テストを凍結基準として読む。
2. `report-write` Step 2をbatch payload 1回へ変更する。
3. skill契約テストを追加して逐次例の再導入をBLOCKする。
4. 専用batchテスト、skill契約テスト、report gate関連テストを実行する。
5. 50フィールドのAfter壁時計を再計測し、Before/Afterを記録する。
6. after設計書と`context/infrastructure.md`索引を追加する。

## 制約

- `report_field_set.sh --batch`の型検証、flock、atomic replace、terminal readiness、completed immutabilityを弱めない。
- `verdict`手動入力禁止。binary checksからの自動導出を維持する。
- `gate_report_format.sh`は最終checkpointとして必ず実行する。
- 既存の単一フィールドCLI APIは互換維持する。
- 現在の`skills/report-write/SKILL.md`未commit差分（自動防止ログ追記）を保持する。
- FAILまたはSKIPが1件でもあれば完了扱いにしない。

## 二値完了基準

- [ ] 通常報告のsetter process数がN回から1回になる。
- [ ] 50フィールドAfterが1000ms未満。
- [ ] valid fixtureのfalse positive 0件、invalid fixtureのfalse negative 0件。
- [ ] 対象テストFAIL0、SKIP0。
- [ ] after設計書とcontext索引が存在する。

## 因果リンク

- ← [[report_field_set_batch]] 既存batch laneがスキル手順から未到達
- ← [[品質合格スループット]] 報告整形がスループットを支配する構造
- → [[report-write]] スキル正規手順への反映先

