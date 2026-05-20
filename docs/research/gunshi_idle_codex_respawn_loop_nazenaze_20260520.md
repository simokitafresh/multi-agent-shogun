# Codex CLI idle無限respawnループ — なぜなぜ7回

- 発見日: 2026-05-20
- 発見者: 軍師(idle自走Step 7)
- データソース: ninja_monitor.log, deploy_task.log, ntfy.log

## 現象

hayate/kagemaru/saizoが10分間隔で無限respawn。2026-05-20の1日で198回。

```
CODEX-RESPAWN: hayate respawn-pane (task in progress workaround)
CODEX-RESPAWN: kagemaru respawn-pane (task in progress workaround)
CODEX-RESPAWN: saizo respawn-pane (task in progress workaround)
```

3忍者×約66回/忍者。06:04:58から現在まで継続中。

## なぜなぜ7回

| Why | 問い | 回答 | 根拠 |
|-----|------|------|------|
| 1 | なぜ3忍者がrespawnされ続けるか | ninja_monitorがidle判定→safe_send_clear→Codex分岐でrespawn-pane -k | ninja_monitor.sh L754-764 |
| 2 | なぜこのコードパスに到達するか | idle判定通過(task status=idle)+clear_debounce 600秒経過 | cli_profiles.yaml codex.clear_debounce=600 |
| 3 | なぜrespawn後にまた到達するか | respawn→CLI再起動→idle→flag再作成→600秒後にまた到達 | task YAML status=idle(変わらない) |
| 4 | なぜidleなのにrespawnが必要か | **不要**。idle時は/newで十分。respawn-pane -kはtask in progress時のworkaround | L752コメント: /newはtask in progress中に無視される |
| 5 | なぜ無条件でrespawn-pane -kか | Codex CLI分岐がtask statusを確認せずに常にrespawn-pane -k | L754: `if cli_type = codex` のみで分岐、task status未参照 |
| 6 | なぜClaude CLIでは問題にならないか | /clearは軽量(同プロセス内リセット)。respawn-pane -kは重い(プロセス殺→再起動) | Claude: コマンド送信のみ。Codex: tmux respawn-pane -k |
| 7 | **根因** | **safe_send_clear()のCodex分岐がtask statusを確認せずに無条件respawn-pane -k** | 修正: idle時→/new送信、in_progress時のみ→respawn-pane -k |

## 影響

- CPU/メモリ: Codex CLI起動×198回。Node.jsプロセス生成→API接続→待機のオーバーヘッド
- ログ汚染: 198行/日のノイズ
- 潜在リスク: API rate limitに寄与する可能性(接続確立時のhandshake)

## 修正案

```bash
# ninja_monitor.sh L754付近
if [ "$(cli_type "$agent_name")" = "codex" ]; then
    # task statusがin_progressの場合のみrespawn-pane -k
    local _task_status
    _task_status=$(grep 'status:' "$SCRIPT_DIR/queue/tasks/${agent_name}.yaml" | head -1 | awk '{print $2}')
    if [ "$_task_status" = "in_progress" ] || [ "$_task_status" = "acknowledged" ]; then
        # task in progress → /newが効かない → respawn-pane -k
        log "CODEX-RESPAWN: $agent_name respawn-pane (task in progress)"
        tmux respawn-pane -k ...
    else
        # idle/done/completed → /newで十分
        log "CODEX-NEW: $agent_name sending /new (idle)"
        safe_send_keys_atomic "$pane" "/new" 0.3
    fi
fi
```

## 関連バグ

### P1: shogun_to_karo.yaml YAML構文エラー(AC上書き失敗28件)

deploy_task.shがshogun_to_karo.yamlを読む際にYAML構文エラー(`while scanning a double-quoted scalar`)。cmd_2901/2902等で発生。cmdテキスト内の未エスケープ二重引用符が原因。忍者に最新ACが届かない(既存ACで配備)。

### P2: pre-push hook timeout 60s不足

テスト選定32ファイル時にtimeout 60sで完走不可→pre-push FAIL→retry→再FAIL→hook_failure ALERT連発。timeout動的計算が必要。

## cmd_2904修正後の穴(なぜなぜ7回 Phase 2)

cmd_2904は_handle_auto_clearの即returnでrespawnループを根絶したが、/new送信経路も塞いだ。

### 実測(19:21時点)
- hayate CTX:36% / kagemaru CTX:57% / saizo CTX:44% — CTX蓄積中
- CODEX-IDLE-NO-TASK-SKIP: 19:16〜19:21で18回発火。/newゼロ回

### 正しい修正(2箇所)
1. _handle_auto_clear L1639-1641: 即return分岐を削除
2. safe_send_clear L754: Codex分岐にreason条件追加
   - reason含む"STALL" → respawn-pane -k(in_progress用。/newが無視されるため)
   - それ以外 → Codex分岐スキップ → L768 clear_cmd=/new経路にフォールスルー

### reasonで分岐可能な根拠
- DEPLOY-STALL-CLEARのみがin_progress時の呼出元(grep実証: 1箇所)
- AUTO-CLEAR/AUTO-VOID/KARO-CLEARはidle/done時
- YAMLアクセス不要(17ms節約)

### post_clear_cmd=/fast
safe_send_clear成功→L1694 POST_CLEAR_PENDING→次サイクルで/fast送信。修正後自然に動く。

## 因果リンク

- → [[ninja_monitor]] respawnループの発生源
- → [[cli_profiles]] clear_debounce=600がループ間隔を決定
- → [[GP-222]] cmd_2806で修正したrespawnループ(99回)とは別根因だが同類
- → [[cmd_2904]] 過剰抑止(idle時/new経路も塞いだ)

## 殿裁定(2026-05-20) — 最終解決

cmd_2904→2906→2907の3cmd連鎖で確定。

**殿裁定: respawn-pane -k は idle時も含めて正しい設計。**

理由:
- /newはCodex CLI内部状態が「task in progress」だと拒否される
- ninja_monitor側のtask statusがidleでも、CLI内部状態は別(CLIプロセス内部は外部から制御不能)
- respawn-pane -kはCLI内部状態に**関係なく**確実にリセットする唯一の手段
- 一見乱暴だが理由がある設計。修正前にgit logで設計意図を確認せよ(CLAUDE.mdに明記)

最終実装(cmd_2907 GATE CLEAR):
```bash
# ninja_monitor.sh safe_send_clear()
# Codex CLIは常にrespawn-pane -kでリセット。task statusに関係なく。
if [ "$(cli_type "$agent_name")" = "codex" ]; then
    tmux respawn-pane -k -t "$pane" "PATH=... bash -c 'exec $launch_cmd'"
fi
```

**上記§修正案(line 40-54)の「idle→/new」分岐案は殿裁定で否定された。**
このなぜなぜ7回自体がL7の学習材料: 「仕組みを作る前に設計意図を確認せよ」。

## CLAUDE.md反映

CLAUDE.md infra節に明記済み:
> Codex idle時もrespawn-pane -k必須(殿裁定2026-05-20)
