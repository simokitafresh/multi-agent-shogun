# lessons_karo v3 個別エントリ アーカイブ (2026-06-09〜2026-06-14)
# v4統合(2026-06-18): 13件をA系列パターンに吸収

## 吸収マッピング

| 元ID | タイトル | 吸収先 | 根拠 |
|------|----------|--------|------|
| LK001 | ALERT=バグ | LK-A05 | 消火禁止: ALERTを「確認した」で閉じるな |
| LK002 | gate_alert type別処理 | LK-A05 | 消火禁止: mark_readのみ=洗脳#1 |
| LK003 | 三層記憶検索必須 | LK-A01 v21 | 確認系: 行動前に三層記憶検索 |
| LK004 | timeout子プロセスI/O | LK-A12 v16 | infra修正: SIGKILL+孤児tmp+毒アイテム |
| LK005 | karo_direct project選択 | LK-A02 v10 | deploy使い方: project=作業実体で選べ |
| LK006 | 検知gate義務チャネル | LK-A13 v4 | gate修正: チャネル不一致=常時WARN |
| LK007 | 完走証跡時刻突合 | LK-A01 v21 | 確認系: run_start > deploy_live_at |
| LK008 | CDP本番計測限定 | LK-A13 v4 | gate修正: post_deploy_evidence.required |
| LK009 | semantic_map上書き | LK-A12 v16 | infra修正: 生成元データ先行更新 |
| LK010 | WSL2 -x常時true | LK-A12 v16 | infra修正: -xは-fに置換 |
| LK011 | gate実行確認必須 | LK-A01 v21 | 確認系: gate/script現物実行 |
| LK012 | inject_lessons連続失敗 | LK-A13 v4 | deploy修正: safety net+CMD起票 |
| LK013 | 覚醒=行動 | LK-A05 v5 | 消火禁止: 判断を殿に押しつけるな |

## 全文保存

### LK001
- title: ALERT=バグ。確認で閉じるな→根因調査→修正→commitまで回せ
- origin: [[cmd_session_20260609]]
- enforcement: gate_karo_startup.sh ALERT出力に防止1行+§0.1問い9+idle自走Step 0.5

### LK002
- title: gate_alert type別処理 — mark_readのみは洗脳#1
- origin: [[cmd_session_20260610]]
- enforcement: karo.md gate_alert行動テンプレート+L0-L7貫通設計

### LK003
- title: 三層記憶検索を全行動の前提にせよ
- origin: [[cmd_session_20260610]]
- enforcement: karo-operations.md §0.1問い11

### LK004
- title: timeout付き子プロセス内で重いI/Oを走らせるな
- origin: [[cache容量WARN]] -> [[timeout3s_SIGKILL]] -> [[孤児tmp11GB+queue19k滞留]]
- enforcement: memory_db_live_insert_async修正+flock自己治癒+毒アイテム削除

### LK005
- title: karo_directタスクのprojectは作業実体で選べ
- origin: [[lesson_useful率9.4%]] -> [[project指定がcurrent_projectに流れる]]
- enforcement: karo-direct SKILL.md原則埋込+全symlink化(5361313c5)

### LK006
- title: 検知gateは義務チャネルと同じ場所を見よ
- origin: [[cmd_karo_hotfix_shogun_startup_escalation_20260611133210]]
- enforcement: gate_shogun_startup.sh Q6 bulletin OR検知+Gate20時間軸回復

### LK007
- title: 完走証跡runは検証対象deploy後であることを突合せよ
- origin: [[cmd_3296]] -> [[旧run流用]] -> [[検証スキップ]]
- enforcement: 完走確認時にrun_start > deploy_live_atを二値チェック

### LK008
- title: CDP本番計測は本番反映cmdに限定せよ
- origin: [[殿指摘_CDPでいつも進まなくなる]]
- enforcement: cmd_complete_gate post_deploy_evidence.required条件+回帰テスト

### LK009
- title: semantic_map_generate.shがEdit変更を上書きする
- origin: [[cmd_3352]]
- enforcement: semantic_map_generate.sh実行前にgrep確認+生成元データ先行更新

### LK010
- title: WSL2 NTFSは-x常時trueだがCI(Linux ext4)はgit mode準拠
- origin: [[cmd_karo_ci_fix_switch_cli_test_20260613]]
- enforcement: pre-push hookまたはCI lintで-xチェック検出→警告

### LK011
- title: gate修正CMD起票前にgate実行確認必須
- origin: [[cmd_session_20260613]]
- enforcement: karo-operations.md §0.1問2にgate実行確認明記+LK-A01 v18吸収

### LK012
- title: inject_related_lessons連続失敗はsafety netで無害だがCMD起票で根治せよ
- origin: [[cmd_session_20260613]]
- enforcement: 掲示板blt_20260613_195849でCMD起票要請済み

### LK013
- title: 覚醒=行動。CMD起票要請は自力で根因を掘り切った後の最終手段
- origin: [[cmd_session_20260614]]
- enforcement: karo.md 洗脳チェック手順+§0.1問い10に他責チェック追加
