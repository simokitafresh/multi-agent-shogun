# 殿厳命 2026-08-18 22:23「至急再発しないように根治せよ。重要なバグだ。単にちゃんとgateclearして忍者を解放すればいいだけ」

## 事実(ログ現物)
- 21:41:14 deploy_task cmd_4355 → hanzo選定 → BLOCK(cmd_karo_hotfix_reflux_deploy_race_20260725): 未archive報告あり
- 以後22:23まで再配備なし。idle忍者4名(hanzo/saizo/kotaro/tobisaru)、IDLE-BACKLOG-ALERT 22:06。cmd_4356は配備試行の記録なし
- 真因: reflux/自動cmdの完了報告がGATE CLEAR(autopush diverge BLOCK)を待って未archiveのまま忍者を占有 → 忍者が解放されない → 殿直接cmdが配備できない

## 即時(今すぐ・順番厳守)
1. cmd_4355 と cmd_4356 をidle忍者2名へ配備(hanzoは22:23 CLEAR済で解放。他saizo/kotaro/tobisaru)。配備したらtask YAMLパスと時刻を掲示板1行(BULLETIN_NOTIFY=shogun)
2. 未archiveの完了報告を全部確認し(queue/reports/*_report_*.yamlでtask status=done)、GATE可能なものは即cmd_complete_gate→archive_completed、autopush BLOCKで通せないものは家老が `archive_completed.sh` 相当で報告を退避して忍者を解放(報告は消さない・退避先を掲示板へ)

## 根治(karo_direct hotfix・忍者1名・儀式なし・可逆)
title: cmd_karo_hotfix_release_ninja_on_done_unarchived_20260818
- AC1: scripts/deploy_task.sh の done|PASS 分岐で「未archive報告あり」の時にBLOCKせず、当該task YAMLを queue/archive/tasks/{ninja}_{parent_cmd}_{ts}.yaml へスナップショット退避(cmd_complete_gateが後で読めるパスをgateのtask解決へ追加)してから新cmdを配備する。ただしstatus=assigned/acknowledged/in_progress(GA-257)は従来通りBLOCK。ci_fix escapeは不要になるので同じ経路へ統合。選択実行 bash scripts/run_tests.sh file tests/unit/test_deploy_task_*.bats FAIL0/SKIP0
- AC2: cmd_complete_gate.sh のtask解決で「queue/tasks/{ninja}.yaml のparent_cmdが対象cmdでない場合はqueue/archive/tasks/{ninja}_{cmd}_*.yaml の最新を読む」を追加し、退避後もGATE CLEAR/archiveが従来どおり通ることを、実際に1件(退避→gate)で確認しcommit
- AC3: 選定順fallback: 配備先候補が上記でも配備不可なら次のidle忍者へ自動遷移(全員不可のときだけBLOCK)。ログに候補ごとの理由を1行ずつ
- 二値: 「done+未archive報告」の忍者へ新cmdを配備できる／既存GATEが退避task YAMLで通る／全忍者不可時のみBLOCK

## 教訓・還流
- 家老教訓(lesson_write_karo): 「殿直接cmdはhotfix/自走より優先。deploy BLOCK後は即別忍者へ再試行(意志依存禁止)」
- 完了後にshogunへ掲示板で: 配備時刻・hotfix commit・test結果
