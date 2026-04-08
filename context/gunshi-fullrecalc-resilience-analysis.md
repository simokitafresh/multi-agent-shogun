<!-- last_updated: 2026-04-09 -->
# fullrecalculate構造的脆弱性分析 — 速度分析補遺 (軍師)
# 2026-03-28T22:10 | 前回速度分析の発展。cmd_1461/cmd_1456知見の統合

## 発端

速度分析(4提案)をkaro経由で送達後、2つの気づき:
1. cmd_1456飛猿偵察: Ward 626s→実は42s(リソース競合anomaly)。Tier 3 #6の前提崩壊
2. cmd_1461将軍起票: zero-signal=23件→0件解消。仮説「速度改善=完走=解消」

→ **速度改善が正確性問題(zero-signal)を構造的に解消した**。これは重要な因果。
→ しかし「速度改善で解消」は「逆に言えば遅くなれば再発」を意味する

## なぜなぜ分析

### Q1: なぜzero-signal FoFは解消したか？
→ cmd_1460のfullrecalculate(260s)が全Phase完走。FoF=Phase5(最終)も処理された

### Q2: なぜ以前は23件あったか？
→ 将軍仮説(cmd_1461): pre-OPT(7285s=~2h)でRenderタイムアウト→Phase5未到達

### Q3: タイムアウトだけが原因か？
→ **否。kill vectorは少なくとも5つ**:

| Kill Vector | 発動条件 | 頻度 |
|---|---|---|
| Worker timeout | 処理時間 > uvicorn/gunicorn timeout | pre-OPT:高、post-OPT:低 |
| Render deploy | git push→自動デプロイ→プロセス再起動 | push毎(日に数回) |
| Health check failure | /healthz応答不能(worker busy) | 不明 |
| OOM | メモリ使用量超過 | 低(要確認) |
| Render infra event | プラットフォームメンテナンス | 稀 |

### Q4: 中断したら何が起きるか？
→ **Phase 0で全データ削除済みのため、DBは不整合状態**

```
Phase 0: cleanup → 全signals/MR/precompute削除
Phase 1-3.7: 前処理+signal事前計算
Phase 4: Standard PF日次ループ → signals生成
Phase 4.5: Standard PF monthly_returns_gen
Phase 5: FoF処理(topological sort順)
Phase 5b: precompute(trade_perf, metrics等)

★ Phase 0後かつPhase 5完了前に中断 → FoFデータ消失 = zero-signal再発
★ Phase 5完了後かつPhase 5b完了前に中断 → trade_perf等のprecompute欠損
```

### Q5: 現在のプロセスは中断を検知できるか？
→ **できない**。以下3点:

1. **recalc_status.py**: インメモリのみ(L17 module-level dict)。プロセス再起動で`running=False`にリセット。「前回中断した」という情報は消失
2. **lifespan handler**: shutdown時に`end_recalculation()`呼出しなし(main.py L89-91)。SIGTERMを受けてもrecalc_statusは更新されない
3. **finally block**: `_recalculate_sync_background`のfinally(etl_trigger.py L412-414)はSIGTERM時に実行される可能性があるが、SIGKILL(Render強制終了)では実行されない

### Q6: 260sなら安全か？
→ **現在はほぼ安全だが保証はない**:
- Worker timeout: `render.yaml`に明示設定なし。uvicorn default=なし。Render Free plan=timeout あり、Pro plan=timeout 明示不要（ただし確認必要）
- **しかし**: デプロイ中に誰かがpushすればプロセス再起動。260sの間にpushが来る確率は低いが非ゼロ
- PF追加で処理時間は増加する。124 PF→150 PFで260s→~315s(線形仮定)

## 速度分析の訂正

### Tier 3 #6: Ward scipy最適化 → **取り下げ**
cmd_1456偵察結果: pipeline_exec 626s=リソース競合anomaly。正常時42s。
Ward FoF=1体のみ。キャッシュ効果=0%(cross-FoF:Ward 1体/same-FoF:月窓異)。
Ward計算自体は~280ms/call。投資対効果なし。

### 更新後の改善提案(ROI順、Tier 1-2は据え置き)

| # | 改善 | 推定効果 | 備考 |
|---|---|---|---|
| 1 | FoF N+1 query一括化 | L3から5-15s | 据え置き |
| 2 | fof_signals dead code除去 | L3から1-3s | 据え置き |
| 3 | monthly_returns_gen バッチ化 | L2から20-40s | 据え置き(最大ボトルネック) |
| 4 | Standard PF日次ループ月中集約 | L2から10-30s | 据え置き |
| ~~6~~ | ~~Ward scipy最適化~~ | ~~数秒~~ | **取り下げ**(cmd_1456) |

## 新規提案: crash-safety改善(Tier 0)

速度改善の前に、**中断耐性**の構造的脆弱性を解消すべき。
理由: 速度改善が正確性を保証している現在の構造は、中断=データ消失のリスクを抱えている。

### 段階案(軽量→重厚)

| Level | 内容 | 効果 | 工数 |
|---|---|---|---|
| 0a | lifespan shutdownで警告ログ+ntfy通知 | 中断を**検知**できる | 極小(main.py 3行) |
| 0b | recalc_statusをDB永続化 | 再起動後に「前回中断」を**検知**できる | 小(テーブル1つ+status更新) |
| 0c | Phase 0のcleanupをPhase完了後に移動(shadow processing) | 中断しても**旧データが残る** | 中(cleanup戦略変更) |
| 0d | Phase別チェックポイント+resume | 中断後に途中から**再開**できる | 大(状態管理全体設計) |

### 推奨: Level 0a + 0b → **cmd_1463で実装済み**

- 0a: ✅ lifespan shutdownで`is_recalculating()`チェック → WARNINGログ (main.py L101-106, commit cbf347ba)
- 0b: ✅ `recalculation_status`テーブル永続化。start/end/status/mode/error_message。起動時check_interrupted_recalculations()でstale running→interrupted更新+WARNING (commit cf90126a)
- 0b+: ✅ pg_advisory_lock排他制御 (cmd_1465, commit 457dd72d)。threading.Lock(プロセス内)+pg_try_advisory_lock(プロセス間)の2層排他。fail-open設計。SIGKILL時はPostgreSQLセッション切断で自動解放
- 0c/0d: 未着手。効果は大きいがcleanup戦略の根本変更。偵察先行推奨

### cmd_1461との関係

将軍のcmd_1461 AC1(タイムアウト設定確認)は上記Q3の1つのvector。
本分析はcmd_1461の結果を待たずに起票可能な防御策(0a/0b)を提示。
cmd_1461の結果と統合すれば、zero-signal問題の完全な根因理解+再発防止が得られる。

## 未確認事項

- Render Pro planのworker timeout具体値(render.yamlに明示なし。cmd_1461 AC1で判明予定)
- uvicorn workers=2のうち1 workerがrecalculate実行中に、もう1 workerがhealth checkに応答できるか
- recalculate中のメモリピーク値(OOMリスク評価)
