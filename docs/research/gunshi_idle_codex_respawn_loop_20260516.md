# Codex忍者 respawn無限ループ — なぜなぜ7回

## 現象
本日(2026-05-16)だけで99回CODEX-RESPAWN。3忍者均等(hayate35/kagemaru36/saizo37)。10分間隔で繰返し。

## なぜなぜ
1. なぜ108回respawn？ → ninja_monitorがidle Codex忍者をAUTO-CLEAR→respawn-pane -k
2. なぜ今日だけ99回？ → 修行完了後に全3忍者がidle化→10分デバウンスごとに発火
3. なぜrespawnが必要？ → Codex CLIに`/clear`がない→respawn-pane -kが唯一の手段(L732-744)
4. なぜrespawn後にまた発火？ → GP-222: Codex CLIはCTX=0%でもスキップしない(CTXパース不確実性対策)
5. なぜCTX=0%スキップしない？ → Codex CLIのCTX表示がバー形式から"Context N% used"テキストに変わり、未検出時に0%と区別できない
6. なぜ未検出=スキップ不可？ → CTX=0(未検出)の忍者を放置するとCTX 90%超でも/clearされないリスク
7. 根因: **GP-222(Codex CTX=0%非スキップ)と600秒デバウンスの組合せが、idle+タスクなし+respawn直後の忍者に無限ループを生む**

## 影響
- 108回のrespawn = CLI再起動108回 = 毎回セッション初期化
- Codex CLIプロセスの無駄な起動/終了(node.js起動コスト)
- ninja_monitorのCPU/IO消費(10分ごとに3忍者分のrespawn処理)
- ログ汚染(108行のCODEX-RESPAWN + 付随ログ)
- ※機能的損害は限定的（idle忍者なので作業中断はない）

## 修正案
### A: respawn後フラグ
respawn実行後に`/tmp/shogun_codex_respawned_{name}`を作成。AUTO-CLEARでフラグ存在時はスキップ。タスク配備時にフラグ削除。

### B: デバウンス延長
Codex忍者のidle+タスクなし時はclear_debounceを3600秒(1時間)に延長。タスク到着で即/clear可能。

### C: GP-222見直し
respawn直後(=CTX確実に0%)の場合のみCTX=0%スキップを許可。前回clear時刻が60秒以内ならスキップ。

推奨: **C**（GP-222の精緻化。根本原因に最も近い）

## 因果鎖
修行完了→全Codex忍者idle→AUTO-CLEAR(600s)→GP-222(CTX=0非スキップ)→respawn→再idle→600s後に再発動→無限ループ。respawn直後スキップ→ループ断絶=正の複利
