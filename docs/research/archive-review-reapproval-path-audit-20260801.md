# Archive review reapproval path audit (2026-08-01)

## 結論

archive済みreportの再承認経路を6段で一次走査した。旧resolverはsame-directory symlink alias 0件受理（AC想定との差1）だが、canonical/dot-segment/absolute probeのdot-segment 1/3を誤受理した。修正後はlexical canonical一致と既存`review_resolve_reports`＋`review_report_logical_path`の(realpath, logical identity) allowlistだけを受理し、残存非対称0件。追加契約の通常failed reportとspec-less failed reportはいずれもcompleted/PASSを要求せずFAIL bundleを正規生成する。

## 6段監査表

| 段 | writer | reader / boundary | archive入力 | cmd_4200実測 | 修正後判定 |
|---|---|---|---|---|---|
| generate | `scripts/review_bundle.py generate` → `queue/gates/<cmd>/sg7_bundle.json` | `_resolve_report`: shared registryの(realpath, logical identity)完全一致 + fingerprint | `--allow-archived`時のみ許可 | APPROVE/FAIL bundle各1/1 | 対称 |
| review | `scripts/review_approval.sh` → logical approval/terminal manifest | archive logical keyを`review_resolve_reports`とfingerprintで照合。Gunshi LGTM時はarchiveなら`--allow-archived`をgenerateへ渡す | 許可 | manifest LGTM 6/6・Karo ACCEPT 6/6 | 対称 |
| notify | `scripts/review_bundle.py notify` → `inbox_write.sh` | bundleのlogical report keyを同じ`_resolve_report`で検証しfingerprint・two-phase readyを照合 | bundle keyがarchive直下の時のみ許可 | 個別通知marker 6/6 | 対称（修正前はlive直下固定の1障壁） |
| SG7 | generateのatomic JSON writer | `review_bundle.py consume` / `cmd_complete.sh` / `cmd_complete_gate.sh`がcmd・verdict・specを検証 | report実体を再解決せずbundleを消費 | `sg7_bundle.json` 1/1 | 対称 |
| marker | `review_approval.sh` → `gunshi_report_review_notify_<worker>.done`、terminal manifest | logical path + report_id + content SHA +両approvalを読む | logical identityで保持 | logical 6/6、physical approval YAML 0/6、notify marker 6/6 | 対称 |
| complete | `cmd_complete_gate.sh` / `archive_completed.sh` → `archive.done`、`cmd_complete.sh` → `notify_karo.done` | SG7 consume + terminal review manifest + CLEAR証跡 | archive後もbundle/manifestを読む | `archive.done` 1/1、`notify_karo.done` 1/1 | 対称 |

## 境界・反例corpus

| 分類 | 件数 | 期待 | 実測 |
|---|---:|---|---|
| live direct | 1 | allow | PASS |
| archive direct | 1 | allow | PASS |
| archive nested | 1 | block | PASS |
| archive symlink escape | 1 | block | PASS |
| archive内symlink alias | 1 | block | PASS |
| live内symlink alias | 1 | block | PASS |
| symlink chain | 1 | block | PASS |
| archive missing | 1 | block | PASS |
| dot-segment traversal | 1 | block | PASS |
| bundle cmd mismatch | 1 | block | PASS |
| 正式CLI archive generate→notify | 1 | 通知1・重複0・logical key一致 | PASS |
| failed archive report→FAIL bundle | 1 | completed/PASS不要・FAIL reason保持 | PASS |
| spec-less failed report→FAIL bundle | 1 | immutable snapshot採用・failed/FAIL保持 | PASS |

`tests/unit/test_review_bundle.py`の既存corpus 13件は上記の具体的不変量を宣言したcontract testで、13/13 PASS・SKIP 0。alias種別ではなくlexical canonical/共有registry identity不一致として一律fail-closeする。

## Review verdict × report verdict 追加8セル

`review verdict`と`report verdict`は独立軸である。reviewer FAILは報告者の証跡を書き換えずcompleted/PASSを棄却でき、failed/FAILも継続して受理する。

| Spec | Review | Report | Expected |
|---|---|---|---|
| present | APPROVE | completed/PASS | success |
| present | APPROVE | failed/FAIL | nonzero |
| present | FAIL | completed/PASS | success |
| present | FAIL | failed/FAIL | success |
| absent | APPROVE | completed/PASS | success |
| absent | APPROVE | failed/FAIL | nonzero |
| absent | FAIL | completed/PASS | success |
| absent | FAIL | failed/FAIL | success |

追加fixtureは期待成功6/6、期待非0 2/2、合計8/8一致。既存13件と合わせた対象直接contractは21/21 PASS・SKIP 0、false positive 0、false negative 0。正式CLI archive generate→notify corpusは通知1・重複0を維持する。

## test provenance

- 対象直接: `python3 -m pytest -q tests/unit/test_review_bundle.py` → 21/21 PASS、SKIP 0（既存corpus 13 + 追加8セル）。
- task runner receipt: 43/43 PASS・SKIP 0だが、対象path直接選択は0件（`direct=0`）。dependency mapによるsemantic test 1ファイルのみのため、本修正の合格根拠には数えない。
- 通知重複: 正式CLI contractの`report_review_result`呼出しは1回、duplicate 0。

## 残存障壁の全数

- 修正前: 1件。`notify()`が`queue/reports`直下だけを許可し、`generate --allow-archived`が保存したarchive logical keyを拒否した。
- 修正後: 0件。generate/notifyが共通`_resolve_report`を使用し、live/archiveともshell SSOTのcanonical identity集合だけを共有する。Python独自台帳は0件。
- 前提差異: AC1記載の「自動notify未完了」は監査時点で`notify_karo.done` 1/1へ変化していた。修正要否の根拠はmarkerの古い想定ではなく、修正前コードのnotify境界非対称とisolated再現である。

origin: `[[cmd_4200]] -> [[archive_notify_boundary_asymmetry]] -> [[automatic_review_notification_gap]]`
