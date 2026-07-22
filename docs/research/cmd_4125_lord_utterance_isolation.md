# cmd_4125 AC3 — 殿発言自動注入経路のtarget隔離棚卸し

- 調査日時: 2026-07-23
- 調査scope: tracked `scripts/`, `scripts/hooks/`, `.claude/`, `.codex/`
- 探索契約: `scripts/code_locate.sh` で `lord_conversation`, `lord_ruling`, `events_fts`, `FROM events`, `additionalContext`, `prompt_state_inject` を全数検索
- 判定単位: 検索結果を自動的にCLI context/tool feedbackへ載せるproducer。retention/import/index生成だけのwriterは除外

## §1 結論

自動注入producerは4系統、非test callerは計5箇所。target隔離なしの経路は4件である。本任務はrecon/docs-onlyのためコード修正前後は **4→4**。本文だけでなく、他者イベント由来のtimestamp/count等メタデータもfilter無しとして数えた。

## §2 全数表

| # | 注入producer | 参照正本 | 注入内容 | target filter | filter無し経路 | 非test caller数 | 非test caller |
|---:|---|---|---|---|---:|---:|---|
| 1 | `scripts/hooks/prompt_state_inject.sh:299-312` | `queue/lord_conversation.jsonl` | prompt identity/replay fenceのみ | `direction=inbound AND detail=prompt AND target=agent_id` | 0 | 2 | `.claude/settings.json:86`, `scripts/hooks/codex_user_prompt_submit.sh:51` |
| 2 | `scripts/hooks/prompt_state_inject.sh:751-875` | `/tmp/lord_ruling_cache.db:lord_rulings` | 関連裁定summary最大3件 | 通常は `target='' OR target=agent_id`。ただしtarget列不在時にfilterを除去 | 1 | 2 | 同上（producer単位のcaller） |
| 3 | `scripts/hooks/prompt_state_inject.sh:887-936` | `events` | candidate state別全体count | なし | 1 | 2 | 同上（producer単位のcaller） |
| 4 | `scripts/hooks/three_layer_preflight.sh:50-72,180-199` | `events_fts JOIN events` | 一致有無・source・query・timestampをcitation scaffold経由で注入 | なし | 1 | 1 | `scripts/hooks/prompt_state_inject.sh:196-203` |
| 5 | `scripts/hooks/memory_db_fts5_preflight.py:86-157` | `events` / `events_fts` | cmd pre-write時のevent summary最大3件 | なし | 1 | 1 | `.claude/hooks/pre-write-edit-combined.sh:147` |
| 6 | `scripts/semantic_search.sh:242-264` → `scripts/semantic_index.py` | `events`/semantic index | semantic_knowledgeとしてpromptへ注入 | current agentをmode引数で渡す | 0 | 1 | `scripts/hooks/prompt_state_inject.sh:729-747,1223-1238` |

集計はproducer重複を除く4系統（prompt_state内の3 subpathは1 producer）。caller実ファイルの一意数は5: `.claude/settings.json`, `codex_user_prompt_submit.sh`, `prompt_state_inject.sh`, `pre-write-edit-combined.sh`, `semantic_search.sh`。表のcaller数は各経路への直接caller数である。

## §3 grep全数の除外分類

| 分類 | 該当 | 注入経路から除外する根拠 |
|---|---|---|
| writer/import | `log_terminal_input.sh`, `log_terminal_response.sh`, `memory_db_import.py`, `conversation_retention.sh`, `ntfy.sh` | 正本へ書くのみでCLI contextへ検索結果を返さない |
| 手動reader | `lord_conversation_read.sh`, `memory_db_query.sh` | 利用者の能動呼出し。自動注入ではない |
| startup/gate分析 | `gate_shogun_startup.sh`, `gate_karo_startup.sh`, `gate_gunshi_startup.sh`, `clear_prep_check.sh` | role固有startup診断。UserPromptSubmitの自動context producerではない |
| index/metric | `semantic_index.py`, `semantic_index_update.sh`, `semantic_stress_test.sh`, `lord_topic_index.py` | index・統計・テスト生成。単独では注入しない |

## §4 二値証跡

| check | result | evidence |
|---|---|---|
| `lord_conversation/lord_ruling/events`参照をtracked全数検索 | PASS | `code_locate.sh` 5 query、対象pathを§2/§3へ全分類 |
| 各経路のtarget filter確認 | PASS | §2のfile:line。本文だけでなくcount/timestampも対象 |
| 非test caller確認 | PASS | caller一意5ファイル、各経路の直接caller数を§2へ記録 |
| filter無し件数 | PASS | 修正前4、修正後4（recon/docs-onlyでscript変更なし） |
| 成果物非空 | PASS | `test -s docs/research/cmd_4125_lord_utterance_isolation.md` |
| context還流 | PASS | `context/infrastructure.md` §lord_conversationへ結論1行追加 |

## §5 盲点・境界

- `lord_rulings.target`列が存在する現行cacheでは本文漏洩を防ぐが、後方互換fallbackは列欠落時に全件検索へ戻る。
- `three_layer_preflight.sh` はsummary本文をcitationへ載せないが、他者event由来のtimestamp/query一致というメタデータは混入し得るためfilter無しに数えた。
- startup gateはUserPromptSubmit外として除外した。startup出力も「全注入」に含める別定義なら追加監査が必要であり、本表の母集団定義を変更して再集計する。

origin: `[[殿裁定_全ロールは自分宛のみ見える仕組み_20260723]] -> [[潜在経路memory_db_fts5_preflightの封鎖]] -> [[cmd_4125_AC3全数棚卸し]]`
