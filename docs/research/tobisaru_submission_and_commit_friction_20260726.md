# 本日の所要時間分析とインフラバグ疑い（飛猿・2026-07-26）

対象: `cmd_karo_impl_report_field_set_telemetry_20260726` / `cmd_reflux_promotion_202607261446_tobisaru` / `cmd_karo_impl_approval_log_atomic_20260726`（拙者が本日担当した3弾）
目的: 殿指示「時間がかかった原因を分析し、利他の精神で調査してインフラバグ疑いを挙げよ」

## §1 実測（一次データ）

| 区間 | 実測 | 出典 |
|---|---|---|
| 調査+実装+実測（3弾合計） | 約 55 分 | 各弾の作業ログ |
| **待ち時間（テスト・commit・ロック）** | **約 105 分** | 下表の内訳 |
| unit全量の空振り 2回 | 2×1200 秒 = **40 分**（実行テスト **0 件**） | receipt `run_tests_20260726T033353_4184644.json` / `..._20260726T040025_1016666.json`（rc=124） |
| commit 1回目（失敗） | lock_wait 53.7s + git_commit **678 秒** → pre-commit BLOCK | `event=failed ... phase_git_commit_ms=677993` |
| commit 2回目（成功） | affected 338.9 秒 | receipt `run_tests_20260726T074006_3402596.json` |
| 前弾の commit | 250.6 秒（うち affected **249.3 秒 = 99.5%**） | `PRECOMMIT_RECEIPT ... affected_tests_ms=249339` |
| 同上（別弾） | 128.5 秒（うち affected **126.3 秒 = 98.3%**） | `PRECOMMIT_RECEIPT ... affected_tests_ms=126349` |

**★所見: 作業より待ちが約2倍。** 才蔵の「調査より提出が長い」(§才蔵分析 07-26) と同じ形が、commit 段でも成立している。

## §2 インフラバグ疑い（4件・すべて再現条件つき）

### B-1 pre-commit 拒否のBLOCK行に「何が落ちたか」への参照が無い
- 実体: `scripts/ninja_scope_commit.sh:196,201` は `BLOCK: pre-commit hook rejected scoped commit` のみを出す。落ちたtest名も、直前に書かれた `logs/test_receipts/*.json` のpathも含まない。
- 実害: hook本体の出力は同一 stderr に流れるため、呼び出し側が `| tail -N` していると理由が丸ごと消える。拙者は理由を得るためだけに **pre-commit を丸ごと再実行（678秒→338秒）** した。
- 提案（新gate不要・1行追加）: BLOCK行に「最新receipt path」と「not ok 行の先頭N件」を添える。
- 分類: 「黙る検知器」族（A8）の変種 — 検知はしているが**どこを見ればよいかを言わない**。

### B-2 heavy_job_admission は所有者の**生存**を見るが**進捗**を見ない
- 実体: `scripts/heavy_job_admission.sh:177-187` の待機ループは `owner_pid` / `owner_age_sec` を印字するのみ。所有者が進んでいるか（CPU time）は一度も測らない。待機側は TIMEOUT(1200s) までひたすら回る。
- 実測: pid 4027390 が **CPU time 00:00:00 のまま 51 分**入場権を保持（家老が独立に再測して不変を確認、bats本体は pipe_read でブロック）。拙者の unit 実行は2回とも 1200 秒で空振り。
- 提案: heartbeat 行に `owner_cputime` を追加し、N周期（例 60秒）変化なしなら `HEAVY_ADMISSION_STALL` を明示ログ。**自動killはしない（D006）** — 検出と通知までで十分。
- 分類: 二次情報（owner_age）だけを見て一次情報（進捗）を見ていない。

### B-3 「測れなかった」と「測って落ちた」が receipt 上で区別できない
- 実体: 入場待ちtimeoutのreceiptは `rc=124` / `declared_test_count=0` / `tests=null`。本日 0件receiptは拙者の2件を含め複数存在（例 `..._20260726T071153_2530952.json` rc=2 tests=0）。
- 実害: 下流（報告YAML・gate）は「FAILしたのか、そもそも走らなかったのか」を機械的に判定できない。拙者は AC6 の証跡を**文章で**書くしかなかった。
- 提案: receipt に `no_measurement: true`（実行0件かつ非0終了時）を1フィールド追加。新台帳は作らない。
- 分類: 欠測を結果として記録する形 —「記録≠状態」族。

### B-4 bc:no の報告は `report_received` が全封鎖され、`task_failed` へ語彙変換が要る
- 実体: `gate_report_format` が bc:no を検出すると report_received をBLOCK。task status を failed|blocked にして `task_failed` で送り直す必要がある。
- 実測: 拙者は本日1回踏んだ（`cmd_karo_impl_approval_log_atomic_20260726` の初回提出）。作業は完遂しているのに status=failed と書く以外に語彙が無い。
- 位置づけ: **才蔵が B5/B6 として既に起票済み**。本稿は独立の再現例として件数を足すだけであり、新規提案はしない。

## §3 利他の調査 — 提出経路の実コストを初めて数値で出した

本日投入した単一キー経路 telemetry（`source=report_field_set`）が、**全忍者の提出コスト**を初めて可視化した。

| 指標 | 実測（2026-07-26 03:21〜07:47 UTC / 4時間26分） |
|---|---|
| 呼出し総数 | **1,694 回** |
| BLOCK | **163 回（9.6%）** |
| 所要時間 合計 | 1,110.6 秒（**18.5 分**） |
| 所要時間 中央値 / p90 | 530ms / 1,250ms |
| 最頻 check_id | `commit_hash` 391回 |
| 最頻BLOCK check_id | **`commit_hash` 100回**（= commit_hash 書込みの **25.6%** がBLOCK） |

**★次弾の最優先標的は `commit_hash` である。** 全体BLOCKの 61%（100/163）を1フィールドが占める。才蔵が B1 で指摘した「エラーメッセージが必要条件を1つも名指ししない」箇所とpathが一致しており、**分析（才蔵）と実測（本telemetry）が独立に同じ場所を指した**。

## §4 自分の誤り（インフラのせいにしない分）

- 待機ループを `until ! pgrep -f "ninja_scope_commit.sh -m"` と書き、**自分のコマンドライン自身にマッチ**して空回りさせた（約10分）。pgrep で自プロセスを除外しなかった拙者の誤り。
- commit 出力を `| tail -3` で切り、B-1 の被害を自分で拡大した。理由を捨てる整形をした側にも責がある。

## §5 因果

origin: `[[殿指示_所要時間分析_20260726]] -> [[待ちが作業の約2倍]] -> [[B-1 理由の消失 / B-2 進捗を見ない入場制御 / B-3 欠測と失敗の混同]]`
関連: `[[saizo_report_submission_friction_20260726]]`（同型診断・提出経路側）
