# deploy task AC handling test speed

## 改善候補

| 優先 | 対象 | 根拠 |
|---|---|---|
| 1 | [[test_deploy_task_ac_handling.bats]] の`SCRIPT_DIR`状態 | AC整合性用の一時rootが全47テストへ漏れ、後続39件中34件が誤ったtaskパスを参照してFAILしていた。 |
| 2 | [[deploy_task_scaffold.bash]] のproject複製 | 全testが同一template treeを`cp -rP`し、WSL2上の反復I/Oになる。 |
| 3 | [[deploy_task.sh]] の関数load | 約10,000行の本体関数群をtest processごとにparseする。 |

最高インパクト候補1を実装した。`verify_ac_consistency`だけが引数task path由来のrootを局所変数として使い、後続deploy testの`SCRIPT_DIR`を汚染しない。

設計照合: [[deploy_task.sh]] の`verify_ac_consistency()`定義はtask fileを引数に取る。対象taskの`queue/tasks`より前をrootとして導出することで、fixtureの物理配置と一致させる。
