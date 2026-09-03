# 家老 強くてニューゲーム復帰点 追補 — 2026-09-03 17:03 JST

## 0. 正本宣言

- role: `karo`
- created_at: `2026-09-03T17:03:00+09:00`
- predecessor: `docs/research/karo-strong-new-game-checkpoint-20260903-1652.md`（先に全文を読む）
- source: 将軍下知 `msg_20260903_165603_2323789_7e492f7e`（X API production proof開始）
- origin: `[[x_api_oauth_done]] -> [[cmd_4472_production_proof]] -> [[X投稿1本]] -> [[karo_checkpoint_20260903_1703]]`

## 1. 追加された最優先状態

- X API認可完了。`config/x_api.env`存在、必要credential keyは非空3件、値は出力していない。
- `GET /2/users/me`は将軍実測でHTTP 200、account=`TokyoJibika`。
- 許可されたproduction postはslot A「デュアルモメンタム完全ガイド・定義」1本のみ。
- ledger key: `n171daa7f92a1`。
- 実行開始: `bash scripts/x_ops/x_post.sh draft A n171daa7f92a1`。
- unified exec session: `9807`。
- shell PID: `2338079`、child `claude --print` PID: `2338153`。
- 17:02時点: shell=`Ss/do_wait`、Claude=`Sl/do_epoll_wait`、draft file未生成。約5分38秒経過。agentがmanual killしてはならない。
- 進行証跡: memory DB `knowledge:9cec2df655e6fc34`、bulletin `blt_20260903_170021_b641dc`。

## 2. 復帰時の二値分岐

1. `queue/x_drafts/2026-09-03_A.txt` が非空で存在するか確認する。
2. 存在する:
   - `bash scripts/x_ops/x_post.sh gate 2026-09-03_A A`。
   - PASS後、`bash scripts/x_ops/x_post.sh approve 2026-09-03_A`で本文全文+pathをntfy送信。
   - 将軍が`queue/x_drafts/2026-09-03_A.approved`を置くまで待つ。
3. 存在しない:
   - PID 2338153の存在と状態を確認する。
   - 生存中なら重複draftを起動せず、既存処理の終端を確認する。
   - 消滅かつdraftなしなら同じ1コマンドを再実行する。
4. post直前:
   - access tokenのrefreshが実行され、新token値を出力しないことを確認する。
   - AC1 gate規則7〜12が未着地なら現行6規則PASSを記録し、AC1着地後に再gateする。
5. 承認後のpostは1回だけ実行する。重複防止に`.posted` markerを先に確認する。
6. 成功後、HTTP 201と投稿URLを掲示板へ記録する。token/secret値は記録しない。

## 3. 投稿コマンド境界

```bash
bash scripts/x_ops/x_post.sh gate 2026-09-03_A A
bash scripts/x_ops/x_post.sh approve 2026-09-03_A
bash scripts/x_ops/x_post.sh post 2026-09-03_A
```

- media添付は今回の1本で将軍から明示指定されていないため、`--media`を勝手に付けない。
- `approve`は最大300秒のmarker待ち。timeoutしてもpostしない。
- approved marker不在、creds不在、token空、HTTP 401はfail-close。post成功として扱わない。

## 4. 16:52本体からの変更

- U11 unknown reason source `78ce1d7ff...` は軍師LGTM・家老ACCEPT済み、GATE publication待ち。
- 新規最優先としてX production proofを追加。
- それ以外の順序配備（worktree既定化→rc31 origin ancestor）は本体記載どおり。

## 5. 禁則

- Xへの投稿は殿承認marker後の1本のみ。
- secret/token値をshell出力・報告・掲示板・checkpointへ書かない。
- draft生成が遅いことを理由に同一draftを並列起動しない。
- agentがprocessをmanual killしない。
- 過去checkpointを修正せず、本追補を新しい時系列正本として扱う。
