# task/report 共通契約案

作成: 2026-09-06 21:25 JST。下知: fail_rate_decision / fail_rate_decision_rev、cmd_4485。状態: 軍師レビュー前、運用schemaへの適用前。

## 主経路

1. ACは配備時点の忍者権限で完結させる。本番書込・DDL・本番deploy・共有root適用など権限外の実行は、承認後の別段へ切り出す。調査ACは観測と証拠提出で閉じ、問題解消を暗黙に要求しない。
2. 殿21:23訂正: 可逆な隔離DB/worktree/非main branch作成・push・反復実験は忍者裁量。監査付き本番readonly取得はlauncherとnonceを必須とし、回数制限を置かない。readonlyであっても書込へ昇格しない。秘密値は出力しない。cmd_4485の旧「1回だけ」は撤廃。

## 配備snapshotを正本にする境界

| 契約 | 固定する内容 | 消費者 |
|---|---|---|
| task identity | task_id、parent_cmd、契約version、発行時刻 | 全段 |
| acceptance | AC ID、対象母集団・期間・入力coverage、測定方法、権限 | 忍者・軍師・完了gate |
| ownership | source/test/artifactの所有path、変更禁止path、commit要否と理由 | writer・receipt・manifest・precheck |
| evidence | input世代/hash、実装commitまたはno-code tree、試験receipt/hash | 再提出判定・レビュー・完了gate |
| lesson set | 配備時idsとmode | writer・feedback・precheck |

worker再配備後のlive taskで過去reportの契約を書き換えない。契約変更は新revisionとして保存し旧snapshotを維持。no-codeは明示契約＋運用pathのみ＋前後tree不変＋同task receiptのtree一致を検証し、架空commitを要求しない。path追加は正規契約revisionで全consumerへ同時反映する。

## AC判定と進行状態

ACのyes/noは独立した事実として保持する。進行状態は作業中・レビュー待ち・完了と例外的な承認待ちを表現する。新状態名は本案だけで追加しない。

例外的な承認待ちは殿裁定が必要な本番操作に限る。owner、求める裁定、証拠path、再開条件を必須とし、承認待ちをFAILから消去しない。通常のreadonly取得や隔離実験を家老入力待ちへ送らない。内部不具合は承認待ちと分類しない。

## 同一世代の再提出

判定keyはtask契約revision・入力世代・source commit/no-code tree・実証evidence hash・実質的な報告内容から導く。report_id再発行やtimestamp変更だけでは新たな実証世代にならない。ただし報告の実質修正は新しいreview対象として認識し、誤った契約欄修正を永久BLOCKしない。

同一keyの二重通知/レビュー要求は一度だけ処理する。未完了の初回要求は再送可能にし、受付済みと処理済みを混同しない。新入力・新commit・新証拠・実質修正があれば再提出可能。固定回数の停止は禁止。旧FAILと新結果は履歴として両方保持する。

## 計測

raw report FAIL数/判定数、FAIL発生unique task数/全task数、同一判定keyの重複件数、実質修正版の再提出件数、例外的承認待ち時間を併記する。fingerprint不在の過去行は重複未分類とし、taskが同じというだけで重複と断定しない。判定時刻・集計窓・ログ反映期限・未反映件数を表示する。

既存35 report/16 FAILは20:34までの保存済み記録。6はFAIL発生task数、10は二taskの初回を除く追加判定数であり、同一fingerprint重複の実測値ではない。翌日比較前に同条件のbaselineを再構成する。

## 受入・移行

- 軍師が権限内AC、例外待ち、unknown保持、同一世代再試行の境界をレビューする。
- task/report/monitor/archiveの各consumerを列挙し、旧契約は明示versionで読めることを試験する。部分導入で既存taskを強制移行しない。
- 正負対照: 同じ通知二重配送、新timestampだけ、新入力、実質報告修正、別task、初回途中障害後の再送、no-code tree一致/不一致、承認待ちと内部不具合の分離。
- 実装担当はinfra忍者、最終検証は家老・軍師。現行reportの未確認事項やFAIL履歴を修正しない。

origin: [[殿裁定_20260906_2123_忍者権限内AC]] -> [[task_snapshot共通契約]] -> [[再提出増幅の抑止と計測]]

## 将軍 APPROVE(2026-09-06 21:30、条件付き。三者合意)
- 軍師条件を採用: 再提出の判定 key は report fingerprint(SHA256: task 契約 revision+入力世代+source commit/no-code tree+evidence hash+実質内容の正規化)で機械判定に固定、主観判定なし。
- 殿 21:23/21:25 の前提を契約の判定基準に置く: **導入は 1 task の総時間(起票→配備→作業→review→CLEAR→解放)と一発 CLEAR 率を悪化させない**こと。配備時の契約チェックは自動(deploy_task 内、追加の人手確認なし)で 1 秒未満。契約導入前後で総時間の baseline を同条件で計測し、悪化なら戻す。
- 例外的承認待ちは殿裁定を要する本番操作のみ(通常の readonly 取得・隔離実験は忍者裁量、家老入力待ちへ送らない)。
- 実装順: F-19(main 包含 WAIT の解消)→fingerprint 重複判定(infra 忍者)→計測 5 指標の日次表→契約 version 付き schema。移行は部分導入、既存 task は強制移行しない。
