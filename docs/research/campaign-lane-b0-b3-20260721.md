# Campaign Lane B0→B3 実行証跡（2026-07-21）

- source: Gist `fb70493ecbfe05959056a18fff597850`
- outcome: 品質合格成果数/壁時計時間
- status: `F1_IN_PROGRESS`

## B0 — 自然cohort最大律速

`logs/deploy_task.log` の2026-07-21 00:00:55〜00:34:52 JSTに自然発生した成功deploy receipt直近10件を採用した。専用計測runは追加していない。

| metric | result |
|---|---:|
| N | 10 |
| success | 10/10 |
| terminal loss | 0 |
| receipt SKIP | 0 |
| wall p50 | 48.090s |
| wall p95 | 60.336s |
| max phase | `task_mutations` 10/10 |
| max phase range | 14.772〜38.164s |

結論: B0 CLEAR。単一最大律速は `task_mutations`。B3閾値 `p50<30s / p95<60s` は未達のためF1へ進む。

補助baseline: affected-test routingは全量unit `2032/2032, 350.507s` からdocs/scoped checkpoint `43/43, 30.892s` へ短縮（-91.2%）。両経路FAIL 0 / SKIP 0。

## F1 — 単一律速への集中wave

既知の独立実験を実装へ移す。再計測だけのtaskは作らない。

| item | before | proven candidate | state |
|---|---:|---:|---|
| memory hit0 | 427.549ms | FTS existence guard 2.329ms、missing/extra 0 | implemented at `5edaa6be7`; post-commit campaign measurement in progress |
| related lessons | 2,967ms | batch 2,772ms、byte/semantic/lesson差分0 | queued after independent owner availability |
| report publication | 1,579ms isolated / 4.5〜6.1s live | no-op再発行除去・既存atomic publication活用 | queued after independent owner availability |

## S1 / B3

F1成果をID順に統合し、scope外diff 0・固定SHA required CI GREEN後、同一定義の自然cohort N≥10で再計測する。最終PASSはbefore比品質合格成果/時 `>1.20x`、p50 `<30s`、p95 `<60s`、FAIL/SKIP/terminal loss 0のAND。

### 固定SHA CI証跡

- fixed SHA: `c74e8e31ef8677943d16a3d2192698c7439d3909`
- GitHub Actions run: `29799273099`
- conclusion: `success`
- Unit Tests / zero-SKIP verification / Shell lint / Build Instructions / CoDD / Integration / E2E: 全job成功

### 未完了監査（2026-07-21 12:48 JST）

- F1 manifest 6項目中、現worktreeに実装+contract testが存在するのは `related-lessons` / `report-publication` / `semantic-context` の3項目。
- `preflight` / `cold-memory` / `post-delivery` はmanifestのowned pathが固定SHAに存在せず、materialize不能。報告YAMLだけのPASSは統合済みコードの証拠として採用しない。
- S1の6/6統合、およびB3自然cohort N≥10の再計測は未実施。従って最終性能基準は未達扱いを維持する。

## Delivery invariant repaired during F1

CLI respawn後、task inboxが既読済みだと `acknowledged|in_progress` taskを再配送しない欠陥を修繕した。`2f1ed20f1` はactive task fingerprintをCLI generationへ結び、未読0でも現世代へexactly-onceで復帰通知する。unitは修正前18件から修正後19/19 PASS、FAIL 0 / SKIP 0。live respawn cohortは対象5/5がtaskを再取得し、配送重複0。
