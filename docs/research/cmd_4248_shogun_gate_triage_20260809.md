# cmd_4248 将軍 startup gate 三分類台帳

- 調査日時: 2026-08-09
- 対象: `scripts/gates/gate_shogun_startup.sh`
- 調査方法: 現物の `echo "■"` セクション64件、分岐・`overall`/`alerts`更新・実行先を走査。コード変更は行っていない。
- 判定記号: **J**=将軍固有judgment、**K**=家老レーン移管候補、**D**=判断を生まない表示のみ削除候補。

## 判定軸

Jは、殿への回答、Q6/追体験、将軍自身のcmd起票・裁定など、機械検知後も将軍の判断が成果そのものになるもの。Kは、検知条件と定型是正が明確で、`gate_karo_startup.sh`、家老idle自走、CI RED忍者修正、`ninja_monitor.sh` のいずれかへ移せるもの。Dは、数値・リマインダー・要約を表示するだけで状態遷移、通知、BLOCK、是正記録がなく、一次ログを残せば表示を削れるものとした。

## 全セクション走査台帳

| 行 | セクション（現物見出し） | 検知内容 / 是正アクションの実体 | 定型度・将軍判断 | 類似受け皿 | 分類 |
|---:|---|---|---|---|:---:|
| 336 | startup check timings (partial) | 部分計測の表示のみ | 高 / 不要 | 最終timing集計 | D |
| 434 | daemon_watchdog heartbeat鮮度 | heartbeat停止をWARN、cron/crontab確認を促す | 高 / 不要 | Karo startupで運用監視 | K |
| 441 | テスト時間台帳鮮度 | stale/writer停止をWARN、台帳確認 | 高 / 不要 | Karoの運用品質監視 | K |
| 567 | セマンティックNO_MATCH計測 | deploy/stressのNO_MATCH率とTOP3を集計 | 高 / 不要 | Karo 519-603、Gunshi 934-951 | K |
| 786 | 将軍watcher環境変数 | `ASW_DISABLE_ESCALATION=1` をALERT | 高 / 不要 | Karo startup / watcher監視 | K |
| 1104 | Memory健全度 | `gate_shogun_memory.sh` の結果をALERT反映 | 高 / Memory利用判断のみ | 将軍専用Memory | J |
| 1114 | p̄鮮度 | sub-gate結果のWARN/ALERT集約 | 高 / 不要 | Karoの総合運用gate | K |
| 1129 | 知識辞書鮮度 | stale知識をWARN/ALERT、TOP3表示 | 高 / 不要 | Karo/Gunshiの知識鮮度 | K |
| 1151 | セマンティクスインデックス鮮度 | 14日以上をALERT、欠落をWARN | 高 / 不要 | Karo 2751、Gunshi 934 | K |
| 1176 | cmd委任状態 | `gate_cmd_state.sh` の委任状態をALERT反映 | 高 / queue管理 | Karo startupのcmd配備漏れ | K |
| 1186 | inbox未読 | shogun inboxの未読件数をWARN | 高 / 受信後の回答判断は将軍 | K |
| 1214 | shogun cmd_new gate迂回履歴 | cmd_idなしのcmd_newをWARN表示 | 高 / 不要 | Karo inbox/queue検査 | K |
| 1233 | 未確認GATE CLEAR | 未確認件数をWARN、結果確認・push・次cmdを促す | 高 / 将軍の次行動 | Karo review/push後処理 | J |
| 1253 | 掲示板未確認 | 未確認掲示板をWARN | 高 / 内容判断は将軍 | Karo/Gunshi bulletin処理 | J |
| 1274 | 掲示板action_required未対応 | 未対応件数をBLOCK、cmd起票を要求 | 高 / 将軍cmd起票 | Karoは証跡再検証、判断は将軍 | J |
| 1295 | 陣形図鮮度 | `karo_snapshot.txt` の存在・更新時刻を表示 | 高 / 不要 | Karo 1824、ninja_monitor生成 | K |
| 1317 | 必読ファイル | deepdive 2本の存在をALERT | 高 / 読了判断は将軍 | Karo 1761、Gunshi 350 | K |
| 1643/1687 | 追体験検証 | Q1-Q6、生発言、Q6自動化証拠を検査しWARN/BLOCK | 中（文章回答は非定型） / 必須 | 各roleの自己検証 | J |
| 1964 | 洗脳連鎖2x2計測 | 殿介入率と自己検出率を算出、危険象限WARN | 中 / 判断材料 | Gunshi自己監査に類似 | J |
| 2121 | 前セッション裁定 | 直近裁定件数を表示しcontext反映を促す | 中 / 裁定反映は将軍 | PD/context反映 | J |
| 2141 | 未回答殿質問 | 最新inboundに回答がなければALERT | 高 / 将軍が回答 | なし（殿との対話境界） | J |
| 2185 | 戦局日誌直近5件 | 日誌を5件表示 | 高 / なし | 一次日誌 | D |
| 2214 | 気づきキュー | corrupt退避、done整理、pending/stale検知 | 高 / 不要 | Karo idle自走、Gunshi永続化 | K |
| 2403 | 将軍パフォーマンスフィードバック | cmd rework/BLOCK、WA、Gunshi RCを集計 | 中 / cmd方針の判断材料 | Karo WA 2115、Gunshi review 460 | J |
| 2555 | idle自走トリガー | 全忍者idleかつpipeline空なら分析手順を表示 | 高 / cmd起票主体は将軍 | ninja_monitor idle + Karo idle | J |
| 2580 | 週次品質指標トレンド | trend scriptの失敗/cron欠落をALERT | 高 / 不要 | Karo startup運用監視 | K |
| 2622 | 学習ループ台帳 | 空転・promotion在庫超過をWARN、凍結証跡を確認 | 高 / 不要 | ninja_monitor reflux 332-338 | K |
| 2687 | idle時BLOCK提案 | idle時にautofix proposal gateを実行 | 高 / 定型処置 | Karo idle自走 | K |
| 2750 | 未処理PROPOSAL | dashboard proposalのpending件数を表示 | 高 / 不要 | Karo pending/GP処理 | K |
| 2810 | GP proposal滞留 | Gunshi proposalのpending滞留を表示 | 高 / 不要 | Karo 2041-2051、Gunshi 1221 | K |
| 2819 | 三層学習ループ | 学習ループ健全性を計測 | 高 / 不要 | Karo/Gunshi 三層ループ | K |
| 2851 | 三層記憶DB健全性 | DB gateのWARNを総合判定へ反映 | 高 / 不要 | Karo 2542、Gunshi 1333 | K |
| 2870 | 三層記憶引用率([MEM]タグ) | lord conversationの引用率を数値表示 | 高 / 使い方の自己判断 | 将軍Memory運用 | J |
| 2911 | 遡及学習 | WARN/BLOCK頻度、再発率、有効率を集計 | 中 / 対策選択が必要 | Karo WA/Gunshi分析 | K |
| 3059/4076 | 教訓健全度 | lesson gateを遅延回収しWARN/ALERTとactionを表示 | 高 / 不要 | Karo lesson health/lesson-sort | K |
| 3072/4103 | 教訓enforcement_level分布 | L4未満候補を表示 | 高 / 不要 | Karo lesson enforcement | K |
| 3085 | 将軍教訓 | active lesson件数をINFO表示（閾値なし） | 高 / 判断なし | `gate_lesson_health` が品質を測定 | D |
| 3111 | 将軍教訓origin | origin/因果link欠落をWARN | 高 / 不要 | Karo lesson品質 | K |
| 3172 | 教訓Stats | cluster別件数・lessons_useful率を表示 | 高 / 判断なし | Karo/Gunshi品質統計 | D |
| 3229 | cmd品質(直近10件) | BLOCK率と直近理由を表示 | 中 / cmd設計判断材料 | Karo cmd品質記録 | J |
| 3257 | gate偽陽性率 | FP率をWARN、action_required掲示板を自動作成 | 高 / 内容判断はreview | Karo/Gunshi review feedback | K |
| 3291 | 軍師分析状態 | `context/gunshi-*.md` の時刻・題名を一覧表示 | 高 / 判断なし | Gunshi自身の研究台帳 | D |
| 3320 | 進化検知（孤立context） | map未参照contextを表示、3件以上ALERT | 中 / 統合判断が必要 | Karo context freshness | K |
| 3362 | AC注入検証 | task ACとcmd sourceのID不一致をWARN | 高 / 不要 | Karo配備・レビュー | K |
| 3475 | scripts/未コミット変更 | scripts dirtyをWARN表示 | 高 / push責務の判断 | Karo CI/配備管理 | K |
| 3489 | 強制度監査(meta-gate) | hook未登録の意志依存scriptをALERT | 高 / 不要 | Karo enforcement監査 | K |
| 3516 | スキル別FAIL率 | 直近50件のFAIL率>10%をWARN | 高 / 不要 | Karo 2603、Gunshi review品質 | K |
| 3706 | スキル推薦 precision/recall | recommendation metricsのWARN/失敗を反映 | 高 / 不要 | Gunshi 461、Karo 2710 | K |
| 3727 | intent debtスキル計測 | unused/stale skillをJSON検査 | 高 / 不要 | Karo/Gunshi skill品質 | K |
| 3756 | SKILL.md script参照 | 参照先欠落/更新漏れをWARN/ALERT | 高 / 不要 | Karo skill static quality | K |
| 3781 | スキル自動成長エスカレーション | code_fix_required未解消をWARN | 高 / 不要 | Gunshi分析→Karo cmd配備 | K |
| 3861 | L6学習速度 | 未回復FAILをALERT、掲示板action_requiredを作成 | 高 / 不要 | Karo/Gunshi learning loop | K |
| 4317 | startup WARN/ALERT連続出現 | 同一alert連続をBLOCK、wait_reason/類似cmdを表示 | 高 / 将軍の根因判断は必要 | Karo 2926、Gunshi 1084 | K |
| 4342 | 前セッションの先送り穴一覧 | alert履歴から未接続穴を一覧表示 | 高 / 不要 | Karo先送り連鎖 | K |
| 4351 | backlinks=0修行候補 | 因果linkゼロをWARN、修行候補を表示 | 高 / 不要 | ninja_monitor reflux inventory | K |
| 4371 | 三層記憶使用義務リマインダー | query手順とMEMタグを表示 | 高 / 状態遷移なし | 実際の引用率gate | D |
| 4378 | startup check timings | 完了後の計測表を表示 | 高 / 不要 | defense overhead ledger | D |
| 4412 | DIGEST | inbox/insight/proposal/unpushed/idle/judgeを1行表示 | 高 / 既存ログの要約のみ | snapshot/各gateの一次値 | D |
| 4414 | 必読 lessons_shogun | 必読ファイル名の表示と肥大WARN | 高 / 肥大時のみlesson-sort判断 | Karo lesson health | K |
| 4423 | 必読 deepdive | deepdiveファイル名の表示 | 高 / 読了判断は別gate | D |
| 4426 | deepdive追体験受領証 | replay gateを実行し未完了をalert化、stop hookと連動 | 高 / 読了は将軍固有 | Shogun stop hook | J |

## 三分類集計

`echo "■"` 64件を、同一論理チェックの遅延結果・重複表示を束ねた61行の台帳として監査した。台帳行の分類は **J=13、K=39、D=9**、重複見出しを展開した分類は **J=14、K=41、D=9**（合計64）。Dは表示行を削る候補であり、元ログ・実測・stop hookの入力を削除する提案ではない。

### 将軍固有judgment (J)

Memory利用、Q1-Q6追体験・洗脳自己診断、殿への回答、裁定反映、未確認GATE CLEAR・掲示板の内容判断、将軍cmd方針・idle時cmd起票、MEM引用率、deepdive受領証を残す。これらは検知を自動化できても、結果を殿への回答または将軍の意思決定へ変換する主体をKaroへ移せない。

### 家老レーン移管候補 (K)

機械判定・定型是正が中心の39件。受け皿と依存順序は次節に固定した。

### 表示のみ削除候補 (D)

部分/最終timing、戦局日誌表示、将軍教訓件数、教訓Stats、軍師分析一覧、MEM手順リマインダー、DIGEST、必読ファイル名表示など11件。削除前に、同じ情報を使うgate/stop hookがないことをgrepと実行結果で確認する。

## AC2: 家老レーンの受け皿と依存順序

| 受け皿 | 移管対象 | 既存の現物受け皿 | 移管時の順序・波及 |
|---|---|---|---|
| `gate_karo_startup.sh` | daemon/timing/semantic/knowledge/inbox-queue、snapshot、insights、weekly/loop、proposal/GP、三層DB、lesson、AC注入、scripts dirty、enforcement、skill、L6、streak/deferred | CI RED配備 1661-1754、snapshot/CTX 1824-1926、inbox/queue 1930-2011、idle 2258-2284、task閉鎖 2287-2524、DB 2542-2600、skill/semantic 2603-2772、lesson 2781-2916、streak 2926-2987、session alert 3039-3043 | ①Karo gateが検知→②`session_alerts_karo.txt`を生成→③stop hookがKaroのalertをBLOCK層として消費→④未解消の先送りだけをKaro→Shogunへ`escalation`送信。Shogun側を先に削ると、stop hook入力と先送りBLOCK連鎖が消えるため、受け皿・receipt・重複抑制を先に揃える。 |
| Karo idle自走 | insights、loop ledger/promotion、idle BLOCK提案、backlinks/reflux、分析・品質の定型消化 | `ninja_monitor.sh` のidle/STALL検出 1467-1746、reflux idle閾値 332-338、CI RED時idle忍者配備 145-248 | ①ninja_monitorが実画面+task statusを確認→②Karo idleへ起床通知→③Karoが既存writer/gateを実行→④成果receipt/lesson還流→⑤未処理だけをalert化。Shogunのidle表示を移す前に、idle triggerの二重配備抑制を確認する。 |
| CI RED忍者修正 | scripts dirty/CI関連の検知から実装配備へ接続する部分 | Karo 1661-1754が`task_type=ci_fix`、`ci_run_id`付きでidle忍者へ配備 | ①CI conclusionを一次確認→②同一run世代の配備receipt確認→③未配備なら忍者へtask→④忍者report→⑤Karo review/push/GREEN確認。将軍startupにCI RED処置を戻さない。 |
| `ninja_monitor.sh` | snapshot生成、CTX/STALL、idle、reflux/backlinks、active taskの実態突合 | `check_idle` 1467-1640、`safe_send_clear` 1713-1746 | ①capture-pane/プロセス/taskを一次確認→②状態補正→③snapshot/通知→④Karo gateが鮮度・未処理を再確認。task statusをidleへ書き換えて移管適格化してはならない。 |

### 依存順序の固定点

`検知` → `受け皿gate実行` → `session_alerts_{role}.txt生成` → `stop_session_alerts.shが同roleファイルを読む` → `先送りBLOCKを同一alert keyでdedup` → `必要時だけinbox escalation` → `Karoが一次再検証・定型是正/忍者配備` → `report/lesson/品質記録` の順序を維持する。Karoへ移した項目でも、将軍固有Jの判断を自動処置へ置換しない。

`gate_shogun_startup.sh` の現物では、session alert生成は末尾の `session_alerts_render.sh` 呼出、先送り連鎖はその後の `inbox_write.sh karo ... escalation`、stop hook側の未完了alert消費は `scripts/hooks/stop_session_alerts.sh` 71-133 にある。したがって、削除・移管の最初のcheckpointは「Karo側alert生成→stop hook BLOCK→重複抑制→escalation receipt」の4点である。

## AC1/AC2一次証跡

- `rg -n 'echo "■' scripts/gates/gate_shogun_startup.sh` 実測: 64件。
- `rg -n '^# ---|echo "■' scripts/gates/gate_karo_startup.sh scripts/gates/gate_gunshi_startup.sh` で、semantic/inbox/CI RED/idle/lesson/三層DB/skill/streak/session-alertの既存重複を照合。
- `rg -n 'check_idle|safe_send_clear|CI RED|REFLUX|STALL' scripts/ninja_monitor.sh` で、idle/STALL/CI RED/refluxの一次実装を照合。
- `rg -n '^# ---|未完了|ALERT|BLOCK|session_alert' scripts/hooks/stop_session_alerts.sh` で、stop hookがsession alertを読む境界を照合。
- 成果物存在確認: `test -s docs/research/cmd_4248_shogun_gate_triage_20260809.md` を提出前に実行する。
