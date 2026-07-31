# Archive review reapproval path audit (2026-08-01)

## 結論

archive済みreportの再承認経路を6段で一次走査した。修正前の残存非対称は1件（notifyのみlive直下固定）、修正後は0件。`cmd_4200`の現況はterminal manifest logical identity 6/6、物理approval YAML 0/6、個別通知marker 6/6、完了通知marker 1/1である。

## 6段監査表

| 段 | writer | reader / boundary | archive入力 | cmd_4200実測 | 修正後判定 |
|---|---|---|---|---|---|
| generate | `scripts/review_bundle.py generate` → `queue/gates/<cmd>/sg7_bundle.json` | `_resolve_report`: lexical direct parent + realpath direct parent + `parent_cmd` + fingerprint | `--allow-archived`時のみ許可 | bundle実在1/1 | 対称 |
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
| archive missing | 1 | block | PASS |
| bundle cmd mismatch | 1 | block | PASS |
| 正式CLI archive generate→notify | 1 | 通知1・重複0・logical key一致 | PASS |

`tests/unit/test_review_bundle.py`は上記の具体的不変量を宣言したcontract testで、6/6 PASS・SKIP 0。任務帰属テストは43/43 PASS・SKIP 0。

## 残存障壁の全数

- 修正前: 1件。`notify()`が`queue/reports`直下だけを許可し、`generate --allow-archived`が保存したarchive logical keyを拒否した。
- 修正後: 0件。generate/notifyが共通`_resolve_report`を使用し、live/archiveとも同一のdirect-parent・realpath・存在境界を共有する。
- 前提差異: AC1記載の「自動notify未完了」は監査時点で`notify_karo.done` 1/1へ変化していた。修正要否の根拠はmarkerの古い想定ではなく、修正前コードのnotify境界非対称とisolated再現である。

origin: `[[cmd_4200]] -> [[archive_notify_boundary_asymmetry]] -> [[automatic_review_notification_gap]]`
