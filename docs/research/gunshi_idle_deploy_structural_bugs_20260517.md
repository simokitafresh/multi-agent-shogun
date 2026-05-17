# deploy_task.sh 構造的バグ分析 — nudge未到達事故の裏
<!-- generated: 2026-05-17T21:20:00+09:00 by gunshi idle analysis -->

## 事故概要 (2026-05-17 20:34)

家老がdeploy_task.sh実行→report_template処理(63ファイル)で時間超過→nudge送信前にtimeout kill→GPT忍者3名にnudge未到達→CTX:0%プロンプト待ち→家老が「STALL」と誤診断→Sonnet切替。

## cmd_2827(archive overflow cap修正)で対処する範囲

report蓄積の構造的原因: 修行レポートがarchive.doneなし→overflow capスキップ→無限蓄積。
L948の`[ -z "$CMD_ID" ] || return 0`を撤去しGATE CLEARごとにcap発火。

## cmd_2827の裏に残る構造的バグ

### P0: nudge送信がdeploy_task.sh末尾

deploy_task_main()のフロー:
```
L6371: deploy_task_apply_task_mutations  ← 重い(gawk+report_template+lessons注入)
L6373: deploy_lock解放
L6378: safe_inbox_write (nudge送信)     ← ★ここに到達しないと配備不完全
L6402: "deployment complete" ログ
L6404: post-deploy pane verify
```

mutations完了≠配備完了。nudge送信が最後にあるため、途中kill/timeout/エラーでnudge未到達が無音で発生する。

**対策案**:
1. `trap EXIT` でnudge送信をクリーンアップハンドラに登録(mutations失敗してもnudge試行)
2. nudge送信をmutations前に移動(task YAMLは配備時点で完了しているため先に通知可能)
3. mutations完了フラグ+nudge送信フラグを分離し、片方でも欠落したらninja_monitorが検出

### P1: deploy_task.shにtimeout保護なし

内部ステップ(gawk/awk/python3)にtimeoutなし。semantic_search(L2471/2481)だけtimeout 5s。
外部のbash timeout(家老のClaude Code)に完全依存。

### P1: post-deploy verify形骸化

L6404-6413: 配備後に忍者paneをcapture-paneで確認。しかし結果はlog出力のみ。
忍者がプロンプト待ちでもリトライ/アラートがない。「確認した」だけで「対処しない」。

### P2: gawk全忍者分読み込み

L1603: `"$SCRIPT_DIR/queue/reports/"*_report_*.yaml` で全忍者の報告を読む。
hayate配備時にkagemaru/saizo等の報告も全件I/O。
対策: `"$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml` に限定(他忍者のstale検出はL1612で別途)。
ただしL1612の他忍者stale検出にはキャッシュが必要→設計要検討。

## 因果チェーン

```
修行サイクル → レポート蓄積(164件) → gawk全忍者分I/O(242件/634ms)
  → report_template preserve(63ファイル/忍者) → deploy全体時間増大
  → 家老bash timeout → nudge未送信(構造的弱点: 末尾配置)
  → GPT忍者3名プロンプト待ち → 家老「STALL」誤診断 → Sonnet切替
```

cmd_2827(archive cap)は蓄積を減らす(因果チェーンの上流)。
P0(nudge保証)は下流の構造的弱点(timeout時もnudge送信)。
両方必要。
