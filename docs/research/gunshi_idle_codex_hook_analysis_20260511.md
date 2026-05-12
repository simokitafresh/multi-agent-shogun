# Codex Stop Hook撤去分析 — 2026-05-11

## 根因

Codex CLIの`{"decision":"block"}`意味論がClaude Codeと異なる:
- Claude Code: block = ターン停止(メッセージ表示のみ)
- Codex: block = reason文をプロンプトとして再実行 → 無限ループ → CLI死亡(status 127)

## 経緯

1. .codex/hooks.json にStop hookを含めて導入
2. 忍者3名dead (01:11:46-48) — inbox未読block → 無限ループ
3. 修正1: _is_codex判定+block skip → 忍者復活
4. 修正2: respawn-pane PATH問題(shebang #!/usr/bin/env node + 最小PATH)
5. 修正3: pane_dead検知改善(pane_current_command=node → 従来ロジックで検知不能)
6. 殿指摘: /newでいいのでは？→ /newはtask in progress中に無視される(元々Ctrl-C方式の理由)
7. 最終判断: Stop hookをCodexから完全撤去。respawn-pane + PATH付与で残す

## 結論

- `.codex/hooks.json`にStopセクションは入れない
- PreToolUse/PostToolUseは安全(blockの意味論問題なし)
- ninja_monitorのrespawn-paneにはnvm PATH必須
- pane_dead=1判定をpane_current_command判定より先に実施

## 影響ファイル

- `.codex/hooks.json` (Stop削除)
- `scripts/hooks/stop_check_inbox.sh` (Codex用修正撤去、Claude Code用に復元)
- `scripts/ninja_monitor.sh` (respawn PATH + pane_dead先行判定)
