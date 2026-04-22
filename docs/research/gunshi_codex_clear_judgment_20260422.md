# Codex /clear判定外れ根因分析

## 問題
Codex(gpt-5.4)がidle+CTX4%でもninja_monitorの/clear判定が外れる。

## 根因
_handle_auto_clear() L1194: `ctx_now <= 0 → CLEAR-SKIP`

get_context_pct()がCodexで0を返す条件:
1. Source 1: @context_pct tmux変数が古い0%のまま(Codexはhookなし→自動更新されない)
2. Source 2: capture-pane -S -30の範囲にCTX行(`Context XX% used`)が含まれない
   - Codexの大量出力後にCTX表示が-30行より前に押出される
   - Claude Codeは`CTX:XX%`をステータスラインに常時表示するため-30行範囲内に常にある

結果: ctx_now=0 → 「既にクリア済み」と誤判定 → /clearスキップ

## CTXパターンマッチ自体は正常
cli_profiles.yaml: `Context [0-9]+%` → 実測`Context 18% used`にマッチ。
パターンの問題ではなく、**表示範囲の問題**(capture-pane -S -30の射程外)。

## 修正案
1. _handle_auto_clear: CTX=0時にcli_typeがcodexなら「未検出」扱い(CLEAR-SKIPしない)
2. ninja_monitorメインループでCodex忍者の@context_pctを定期更新(pane_varの強制更新)
3. capture-pane -S -30 → -S -50に拡大(ただし根本対処ではない)

推奨: 案1(1箇所変更、D0対応可能)

## 波及
監視系全体がOpus/Claude CodeのCTX表示(ステータスライン常時表示)に暗黙依存。
Codexはステータスラインなし→capture-paneのCTX検出が不安定。
