# retro遅延分析プロンプト無制限張り付きバグ — As-Is/To-Be 5W1H

- date: 2026-07-21T12:47+09:00
- author: shogun (殿指示 12:44「忍者paneに無制限に速度遅延分析プロンプトが張り付く。状況確認し家老・軍師と掲示板協議。asis/tobe 5W1Hをまとめよ。慌てて修正実装するな」)
- status: 協議用ドラフト（実装前）。修正は家老・軍師協議後に設計→cmd化

## 現象（一次証拠）

- `tmux capture-pane -t shogun:2.6`(saizo): 同一プロンプト「この作業で時間がかかった原因を分析し、利他の精神で調査を行いインフラバグの疑いとして家老に報告せよ」が**入力行に多重スタック**（5〜12行に反復）。
- `logs/retro_pane_prompt.tsv`: 同一event(`saizo task_failed:rpt-66ca28b9…` / `hayate report_received:msg_20260721_120800…` / `kotaro task_failed:rpt-f0d60d68…`)を**毎monitorサイクル再配送**(12:16→12:21→12:27→12:34→12:37→12:40→12:43→12:46…、~3-6分間隔)、全て`failed_prompt_unseen`。
- 集計: delivered 26 / failed_prompt_unseen 19 / deduplicated 8 / failed_busy 3。

## 真因（コード確定）

`scripts/lib/retro_pane_prompt.sh` の `retro_pane_prompt_deliver`:
1. dedupは`mkdir "$key.claimed"`（key=sha256(target,event_id)）で1回性を担保。
2. **send-keys `-l` でプロンプト投入 + Enter は毎回成功**（paneに文字が入る）。
3. 最終`retro_pane_prompt_seen`が `capture-pane -p -J -S -30 | grep -Fq -- "$RETRO_PANE_PROMPT"`（全文1行マッチ）で検証。
4. **paneは長い日本語プロンプトを複数行に折返し表示するため`grep -Fq`(全文連続一致)が成立せず→常に`unseen`判定**。
5. unseen時に `rmdir "$claim"`で**dedup権利を解放**し return 1。eventは`verbatim_pending/`に残留（`awaiting_answer`へ移らない）。
6. 次サイクルで同一eventを再配送 → 2に戻る → **無限反復＝paneに無制限スタック**。

副次: Codex CLIではsend-keys Enterが送信確定しない可能性があり、テキストが入力バッファに滞留してさらに視認上のスタックを増幅。

関連既知障害（家老inbox 2026-07-21）: 「review済みでもpending終端せず再送する現役障害」「retro false-negative 16回再発」＝同一のpending非終端ループ。

## 5W1H

### As-Is
- **What**: 完了/失敗した1タスクにつき1回だけ提示すべきretro遅延分析プロンプトが、検証失敗判定→claim解放→pending残留のループで毎サイクル再送され、忍者paneに無制限に蓄積。
- **Why(害)**: (1)忍者の入力行が汚染され次タスク受領・作業が阻害 (2)monitorサイクル毎に無駄なsend-keys/capture-pane (3)retro回答が一度も終端しない＝二重ループの「別タスクとしてのretro」設計([MEM: memory_db ts=2026-07-20T20:50:28 knowledge:98f775fd])が機能不全。
- **Who**: ninja_monitor.sh STEP(verbatim_pending走査, L8467-)→retro_pane_prompt.sh deliver。対象=idle忍者(saizo/hayate/kotaro実測)。
- **When**: 毎monitorサイクル(~3-6分)。task status∈{failed,blocked,idle,done}かつpane idleの間、無期限。
- **Where**: `scripts/lib/retro_pane_prompt.sh`(seen判定+claim解放), `scripts/ninja_monitor.sh` L8467-8503(pending走査/awaiting_answer遷移), `queue/retro/verbatim_pending/*.event`。
- **How(発生機序)**: 上記「真因」1-6。核心=**verify失敗を"未配送"と誤分類しdedup解放→再送**。実際にはsend自体は成功(過剰配送)している。

### To-Be（協議で確定させる方向性・未実装）
- **What**: 1event=最大1回のpane投入を保証。verify失敗でも**投入事実は記録し再send-keysしない**（"送ったが未確認"と"未送信"を分離）。
- **Why**: send成功＝pane汚染は既に発生。再送はリスクのみでゼロ利得。二重ループのretroは「別タスクとして1回提示」が仕様。
- **How(候補・協議対象、いずれも要検証)**:
  - (a) send-keys実行後は`sent`状態を永続化し、claim解放しない。verify失敗は`delivered_unverified`で終端（再send禁止、監視のみ）。
  - (b) seen判定を折返し耐性化: 全文1行grepをやめ、プロンプト先頭N文字＋末尾N文字の2アンカー一致、または`capture-pane -J`の空白除去正規化後にマッチ。
  - (c) per-target「outstanding retro最大1件」上限: 同一忍者に未回答retroがある間は新eventをenqueueしない/古いものをsupersede。
  - (d) Codex送信確定の一次確認（Enterが効かないなら送信方式を是正）。
  - **殿原則との整合**: 表示型gate追加ではなく、既存配送ロジックの誤分類是正（構造修正）。慌てて実装せず、家老・軍師で(a)-(d)の優先度と副作用を協議。
- **When/Who**: 協議合意後にcmd化→忍者実装→軍師レビュー（正本突合+境界fixture両方義務[MEM: memory_db 殿15:14 hook/gate品質2原則]）。

## 即時の応急（協議前・可逆・低リスク、殿承認事項）
- 選択肢: `verbatim_pending/*.event`の該当3件を一時退避すれば再送は即止まる（可逆＝戻せば再開）。ただし**根治ではない**ため、退避するか否かも含め協議で決める。慌てて実装しない殿指示に従い、本ドラフト提示を先行。
