# 再計算ステータスのクロスプロセス真実源統一 設計書 AsIs/ToBe 5W1H

- 作成: 将軍 2026-07-09 13:58（殿指示 13:49/13:57）
- 対象: DM-Signal `backend/app/utils/recalc_status.py` + `backend/app/api/etl_trigger.py`
- version: v1.0

## §0 発端 — 殿の言葉（2026-07-09）

> 3786は完了していないか？将軍に報告が来ないのはインフラバグでは？覚醒して確認し、バグは修正しよう(13:49)
> 前回同様、設計書を先に作ってから修正cmdを起票してよい(13:57)

文脈: cmd_3786ロールバック中、`recalculation_status`テーブルのid=195が`running`のまま張り付いて見えた。将軍が調査した結果、報告到達自体は正常（家老のkaro-directホットフィックスが13:46にGATE CLEARし将軍が処理済み）だったが、**別の本物のインフラバグ**を発見した。

## §1 原理 — 真実の在処は一つでなければならない

**書き手と読み手が別のストアを見る構造は、両方が「正しく動いている」のに恒常的な誤判定を生む。**(既知原則: LS078「真実の在処不一致クラス」)。今回は「DBのrecalculation_status行」と「ワーカープロセス内メモリの`_recalculate_status`辞書」という2つのストアが、Renderの`--workers 2`構成下で食い違いうる。クロスプロセスの真実源(advisory lockまたはDB)に一本化しなければならない。

## §2 AsIs — 現状の実装（全てfile:line現物確認、2026-07-09）

| # | 項目 | 現状 | 現物 |
|---|------|------|------|
| A1 | 本番構成 | Render `srv-d4ja7q15pdvs739a4q1g`は`numInstances=1`だが起動コマンドが`uvicorn app.main:app --workers 2`。**2つの独立プロセス**が同一ポートを共有 | Render API `services/srv-.../` 現物確認(2026-07-09 13:53) |
| A2 | 状態の保持場所 | `_recalculate_status`(dict)と`_current_db_record_id`(int)は**モジュールレベル変数**。forkされた各ワーカープロセスがそれぞれ独立したコピーを持つ | `recalc_status.py:36-42,222` |
| A3 | クロスプロセス保護(既存・正しく機能) | `pg_advisory_lock`は`start_recalculation()`内で使用され、Postgres経由で**正しくクロスプロセスに排他**する | `recalc_status.py:238-296` |
| A4 | 状態確認の不備 | `GET /admin/recalculate-status`は`get_recalculate_status_data()`を呼び、**リクエストを受けたワーカー自身の`_recalculate_status`のみ**を返す。他ワーカーの実行状況は一切参照しない | `etl_trigger.py:47-60`, `recalc_status.py:87-107` |
| A5 | 起票時ガードの不備 | `trigger_recalculate_sync()`のガードは`is_recalculating()`(自ワーカーの状態のみ)。**他ワーカーが実行中でもこのチェックは通過し、HTTP 200 "accepted"を返す** | `etl_trigger.py:114-120` |
| A6 | サイレントno-opの実証箇所 | ガード通過後`_recalculate_sync_background()`→`start_recalculation()`内で`_db_try_acquire_advisory_lock()`が失敗すれば`False`を返すが、呼び出し元は`logger.warning("Background recalculate skipped: already running")`を出すのみで、**既にHTTPレスポンスは返却済みのため呼び出し元に一切通知されない** | `etl_trigger.py:172-174` |
| A7 | 実例(2026-07-09) | id=195(portfolio mode, 04:25 UTC開始)実行中に、kagemaruが`mode=full`をPOST→200 accepted受領も、DBに新規行(id=196)は作成されず、id=195のみが残存。将軍が`/admin/recalculate-status`を叩くと`running=false`(A4の設計通りの誤答) | kagemaru報告(2026-07-09 13:37) + 将軍DB/API検分(13:49-13:53) |
| A8 | 起動時の巻き戻し機構 | `check_interrupted_recalculations()`はアプリ起動時(FastAPI startup event)に「'running'のまま残った行」を'interrupted'へ強制遷移させる。**プロセス再起動時のみ発火**し、今回のような「別ワーカーが正当に稼働中」のケースには無関係 | `main.py:129-131`, `recalc_status.py:196-225` |

**結論: id=195は「壊れて止まっている」のではなく「別ワーカーで正当に実行中」の可能性が高い(将軍の当初診断は不正確だった)。真の欠陥はDB行の停滞ではなく、ステータス確認とガードチェックが的確なクロスプロセス手段を使っていないこと。**

## §3 なぜなぜ — なぜこの設計になったか

1. なぜステータス確認がプロセス内メモリのみか → 単一プロセス前提で実装され(`_status_lock`はスレッドセーフ化のみ意識)、`--workers 2`によるマルチプロセス化は考慮されていなかった
2. なぜ`--workers 2`との整合確認が漏れたか → advisory lockによる排他(A3)は正しく実装されており、「排他は効いている」ことで安心し、「状態の**可視性**」も同じ手段でクロスプロセス化する必要性が見落とされた
3. なぜ発覚が遅れたか → 通常運用では単一の再計算リクエストしか飛ばないため、ワーカーを跨いだ二重発火が起きる状況(今回のロールバック中の緊急対応)でしか露呈しない
4. 根因 → 排他(exclusion)と可視性(visibility)は別問題であり、片方(advisory lock)をクロスプロセス化しても、もう片方(status確認)を同じ手段で統一しなければ「見えない」問題が残る

## §4 AsIs/ToBe 5W1H対比

| 軸 | AsIs | ToBe |
|----|------|------|
| WHO | リクエストを受けた**そのワーカー**が単独で判断 | **DB(`recalculation_status`最新行)**をクロスプロセスの真実源として全ワーカーが参照 |
| WHAT | ワーカーローカルの`_recalculate_status`辞書を返す/チェックする | DB最新行の`status='running' AND end_time IS NULL`を真実源とし、advisory lockの生死とも突合する |
| WHEN | リクエスト受信時にその場でメモリを読む | リクエスト受信時にDBへ1クエリ(軽量)し、必要ならadvisory lock試行結果と併せて判定 |
| WHERE | `recalc_status.py`の辞書(プロセスローカル) | `recalculation_status`テーブル(全ワーカー共有・Postgres SSOT) |
| WHY | シンプルさ優先(単一プロセス前提の名残) | **真実は一つでなければならない**。マルチワーカーでも同じ答えを返す |
| HOW | 辞書read/write | DBクエリ(最新running行の有無)+advisory lock状態の併用判定 |

## §5 ToBe設計

### R1: ステータス確認をDB SSOT化

`get_recalculate_status_data()`(または新関数)に、DB最新行を確認する経路を追加:

```python
def get_recalculate_status_data() -> dict:
    # 既存: 自プロセスの状態(高速パス、同一ワーカーからの照会に対応)
    local_status = ...(既存ロジック)

    # 追加: DB最新行をクロスプロセス真実源として確認
    db_status = _db_get_latest_running_record()  # 新規実装
    if db_status and not local_status["running"]:
        # 他ワーカーが実行中: DBの情報で上書き
        return {**db_status, "running": True, "note": "running on another worker"}
    return local_status
```

- `_db_get_latest_running_record()`: `SELECT * FROM recalculation_status WHERE status='running' ORDER BY id DESC LIMIT 1`を実行し、該当行があれば返す
- 起動直後の巻き戻し(`check_interrupted_recalculations`)との整合: この行がプロセス再起動由来の幽霊でないことは、advisory lockが実際に取得されているか(`pg_try_advisory_lock`即時解放テストなど)で二重確認できるとなお良い(R1拡張候補)

### R2: 起票ガードをクロスプロセス化

`trigger_recalculate_sync()`のガード(L115)を、自プロセスの`is_recalculating()`だけでなくR1のDB確認結果も見るよう変更。他ワーカーが実行中なら**この時点で409を返す**(現状のようにHTTP 200を返してから裏でサイレントno-opしない)。

### R3: サイレントno-opの解消

`_recalculate_sync_background()`内(L172-174)で`start_recalculation()`が`False`を返した場合、現状はWARNINGログのみで処理が終わる。R2でリクエスト時点のガードが強化されればこの経路への到達自体が稀になるが、念のため到達した場合は明確な形(例: 専用のエラーステータスをDBに記録)で可視化する。

## §6 計測計画

| 指標 | baseline(AsIs) | target(ToBe) |
|------|----------------|---------------|
| ステータス確認の正確性 | ワーカー2台構成で誤答しうる(実証済み) | 全ワーカーで同一の正しい答え |
| サイレントno-op発生 | 検知不能(ログ埋没) | ガード強化で発生自体が稀に、発生時も可視化 |
| 起票時の誤202応答 | 他ワーカー実行中でも200 accepted(実証済み) | 409 Conflictで即座に拒否 |

## §7 実装cmd分割案

| cmd | 内容 | 規模 |
|-----|------|------|
| 単一cmd | R1(DB SSOT化)+R2(起票ガード強化)+R3(no-op可視化)+既存テスト更新 | 小〜中(対象2ファイル、既存advisory lock機構の再利用が中心) |

## §8 スコープ外(明示)

- cmd_3786本体の完了確認(id=195は正当稼働中の可能性が高く、本設計書の対象外。別途DB実体で完了確認する)
- `check_interrupted_recalculations()`(起動時巻き戻し)自体の変更 — 現状の役割(プロセス再起動時の幽霊行始末)は維持
- hayateのcmd_3786_full task終端連携の穴(karo-directホットフィックスによる代替時の終端マーク欠如) — 別途家老へ指摘済み、本設計書とは別系統の課題

## 因果リンク

- ← [[殿指摘20260709_1349_3786完了確認]] 「報告が来ないのはインフラバグでは」
- ← [[殿裁定20260709_1357_設計書優先]] 「前回同様、設計書を先に作ってから」
- ← [[LS078]] 真実の在処不一致クラス(書き手/読み手の別ストア問題の一般原理)
- → [[cmd_3786]] ロールバック本線(id=195は本設計書の対象外、正当稼働中と推定)
