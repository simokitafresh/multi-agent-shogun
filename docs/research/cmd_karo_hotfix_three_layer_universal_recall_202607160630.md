# cmd_karo_hotfix_three_layer_universal_recall_202607160630

## 結論

target空欄の普遍knowledgeを、全agentの検索とClaude/Codexの自動prompt注入へ同一payloadで到達させた。単一CLIの環境変数による役割模倣は補助contractに降格し、実家老Codexと実軍師Claudeの独立取得一致を完了条件にした。

## 時系列と因果

1. 殿が「全ロール・全CLIが同じレベルと粒度で理解できるのが三層記憶」と指摘。
2. `memory_db_import.py`のtarget指定検索が`target=self OR document`で、target空欄の普遍knowledgeを除外していた。一方、prompt cache検索はtarget空欄を許可しており、検索意味論が分裂していた。
3. `scripts/memory_visibility.py`へ`target空/NULL OR target=self OR document`をSSOT化し、記憶DB検索とsemantic検索を収束した（commit `8dacb9fbf`）。
4. 初回修正は全agent検索9/9まで回復したが、knowledge writeからprompt cacheへの自動反映がなく、実CLI自動入口は0/2だった。テスト内の手動cache INSERTは本番経路の証明にならなかった。
5. `memory_db_knowledge_write.sh`成功後に主DBからprompt cacheを再構築し、flock・一時SQLite・`quick_check`・`os.replace`でatomic publishする経路を追加した（commit `c2e7352ee`）。
6. 殿が「単一CLIで全CLI到達を証明すること自体が洗脳。家老と軍師で独立確認すればよい」と指摘。以後、異CLI・異役割の独立取得一致を最終checkpointに固定した。

因果: `[[殿指摘20260716_単一CLI擬似全役は洗脳]] -> [[knowledge_write_to_atomic_prompt_cache]] -> [[家老Codex軍師Claude独立一致]]`

## 実装契約

| 契約 | 実装 |
|---|---|
| target指定visibility SSOT | `scripts/memory_visibility.py` |
| 主DBから普遍knowledgeを構造化 | `scripts/memory_db_import.py` |
| write直後のcache refresh | `scripts/memory_db_knowledge_write.sh` |
| Claude共通入口 | `scripts/hooks/prompt_state_inject.sh` |
| Codex adapter | `scripts/hooks/codex_user_prompt_submit.sh` → `prompt_state_inject.sh` |
| atomic publish | flock → temporary SQLite → `PRAGMA quick_check` → `os.replace` |

構造化summaryは`event_id`・`ts`・`concept`・`raw`・`origin`を保持する。directed knowledgeはprompt cacheへ収録せず、他agentへの漏洩を防ぐ。

## 二値計測

| 指標 | 修正前 | 修正後 |
|---|---:|---:|
| target空欄knowledgeの全agent検索 | 0/9 | 9/9 |
| 他agent宛private漏洩 | 0/8 | 0/8 |
| 実異CLI自動入口 | 0/2 | 2/2 |
| 実異CLI対象summary hash一致 | 未成立 | 2/2一致 |
| 並行reader瞬断 | 未計測 | 0/300（refresh 30回と並行） |
| memory tests | — | 60/60 PASS、SKIP 0 |
| semantic tests | — | 33/33 PASS、SKIP 0 |

独立checkpoint eventは`knowledge:d39dfb36cbf94766`。実家老Codexと実軍師Claudeが、marker `cross_cli_independent_checkpoint_20260716`から自roleのまま`prompt_state_inject.sh`系入口を実行し、対象summary SHA256 `54486b88764aabc3585271b40f18fe21fa7c31ac29290a80d0fd6f1fa9cff3cc`、field 5/5一致を確認した。

## 完了判定の恒久則

- 単一CLIのenv擬似ロール試験はentrypoint contractの補助証拠に限定する。
- 「全CLI同一理解」の完了には、異なる実CLI・異なる役割が同一問いを独立取得し、concept・原文timestamp・因果リンク・payload hashを突合する。
- 保存成功やDB検索成功で止めず、production write → atomic cache → actual prompt hookまでを1本の自動再利用経路として検証する。
