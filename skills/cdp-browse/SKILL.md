---
name: cdp-browse
argument-hint: "[url] [screenshot_path]"
description: |
  共有CDP session foundationを通してブラウザを操作するスキル。
  DM-Signal検分、性能計測、note下書き、汎用ブラウザ操作を同じreceipt契約で実行する。
  TRIGGER: /cdp-browse、CDPで確認、CDPで調査、ブラウザ確認、画面確認、スクリーンショット、note下書き、CDP性能計測
  DO NOT TRIGGER: ブラウザを使わないコード読解、DBだけの確認、既存画像ファイルの閲覧
allowed-tools:
  - Bash
  - Read
---

# /cdp-browse — CDP session単一契約

## 実行前の前提(必須・殿裁定2026-08-13「三層記憶をスキル実行前に確認することがそもそもの前提」)

**スキル実行前に三層記憶(記憶DB・セマンティック・Obsidian)を確認せよ。** CDPの落とし穴と正解は三層に蓄積済みであり、検索せずに実行すると既知の問題で必ず試行錯誤する(2026-08-13将軍が実証: 検索せず3欠陥全てを踏んだが、全て三層に答えが既在した)。

```bash
bash scripts/memory_db_query.sh "CDP <今回の目的>"   # 記憶DB(例: knowledge:776999ee=CDP正本)
bash scripts/semantic_search.sh "CDP"                # セマンティック(auth約5分等の運用知見)
# Obsidian: ヒットしたorigin [[リンク]]をたどる(例: LS098=powershell失敗≠CDP不可能)
```

既知の落とし穴(三層より。コード側にも内在化済み 2026-08-13):
1. **powershell.exe不可視**: sandbox shellはPATHにWindows dirがない。`cdp_helper.ps_run`が絶対パスfallbackを内蔵。それでも失敗する場合はLS098のchrome.exe直接起動が最終fallback。
2. **auth所要≈5分**: adapterのsubprocess timeoutは`CDP_AUTH_TIMEOUT_SEC`(既定360秒)。短縮するな。
3. **WSL/Windows境界**: endpoint生存判定(WSL側)とPowerShell経由アクセス(Windows側)は見える世界が異なる。片側の成功を全体の成功と判定するな。

CDP操作の入口は共有foundationだけである。用途wrapperは下記と同じsession確立を内部実行し、`cdp_session_foundation`発行のreceiptがない接続をfail-closedで拒否する。

```bash
python3 scripts/cdp/cdp_session.py establish --consumer "$CONSUMER" --ports 9222,9223,9224 --receipt "$RECEIPT"
```

`CONSUMER`は`inspection`、`measurement`、`note`、`generic`のいずれか、`RECEIPT`は当該実行だけが読める一時ファイルとする。個別にブラウザ、daemon、port、credentialを準備してはならない。終了時はwrapperのtrapまたは `cdp_session.py cleanup --receipt "$RECEIPT"` に任せる。

### Evidence state gate (必須)

foundation receiptの発行はtransportの成立だけを示し、作業成功ではない。全ての用途は共通判定器を段階ごとに通し、`transport_only` → `dom_observed` → `artifact_complete` を明示する。`transport_only` と `dom_observed` は継続状態であり、終了成功は `artifact_complete` のexit 0だけである。

```bash
STATUS=0
python3 scripts/cdp/cdp_evidence_status.py --receipt "$RECEIPT" || STATUS=$?
test "$STATUS" -eq 10  # transport_only: receiptのみ、処理を続行
# DOM実値を保存後:
STATUS=0
python3 scripts/cdp/cdp_evidence_status.py --receipt "$RECEIPT" \
  --dom-evidence "$DOM_EVIDENCE" || STATUS=$?
test "$STATUS" -eq 11  # dom_observed: artifact保存を続行
# artifactを保存後。ここだけexit 0で完了扱い:
python3 scripts/cdp/cdp_evidence_status.py --receipt "$RECEIPT" \
  --dom-evidence "$DOM_EVIDENCE" --artifact "$ARTIFACT"
```

判定器はfoundation receiptを検証し、DOM実値と読み取り可能な非空artifactを機械判定する。receiptだけ、またはDOMだけで後続処理を省略してはならない。

## 用途写像

- DM-Signal検分: `inspection` receiptを消費するカード=`scripts/cdp/cdp_card_probe.py`、contrast=`scripts/cdp/cdp_contrast_probe.py`、ED=`scripts/cdp/cdp_ed_probe.py`、font=`scripts/cdp/cdp_font_probe.py`、最大表示=`scripts/cdp/cdp_maxdisplay_probe.py`、tier=`scripts/cdp/cdp_tier_probe.py`から選び、認証が必要なら `scripts/cdp/dm_signal_adapters.py` のauth/deploy adapterを使う。
- 性能計測: `measurement` receiptを内部で確立・消費する `bash scripts/cdp/cdp_measure.sh <cmd_id> ...` を使う。
- note下書き: `note` receiptを内部で確立・消費する `bash scripts/note_draft.sh <article.md>` を使う。
- 汎用操作: `generic` receiptを確立し、そのreceiptのendpointだけをnavigate/click/type/screenshot操作へ渡す。

## A7欠陥と実装保証

| A7 | 実装済み保証 | 一次正本 |
|---|---|---|
| 1. port占有時に復旧不能 | 9222→9223→9224の有限fallback、全候補失敗は明示FAIL | `scripts/cdp/cdp_session.py` |
| 2. admin 401分岐なし | admin失敗後、要求権限がviewerの場合だけviewerへfallback | `scripts/cdp/dm_signal_adapters.py` |
| 3. viewer認証が暗黙 | adapterがVIEWER_PASS読込とReact input eventを内包し、password form消失かつ`tbody tr` 1行以上だけ成功（0行はFAIL） | `scripts/cdp/dm_signal_adapters.py` |
| 4. 発火が字句依存 | 全用途をfoundation receiptの同一入口へ固定 | `docs/research/cdp-session-contract-v1.yaml` |
| 5. 推薦止まり | consumerがreceiptなしの接続を受理しない | `scripts/cdp/cdp_session.py`、各consumer wrapper |
| 6. 役割別に入口が自由 | inspection/measurement/note/genericの4 consumerを同じissuerへ固定 | `docs/research/cdp-session-contract-v1.yaml` |
| 7. 台帳破損で使用率不明 | receiptのconsumerとskill実行台帳で役割別計測 | `logs/skill_execution_log.yaml` |

foundationはWindows側Chromeを必ず隔離profileとremote-debugging設定で起動する。auth adapterはadmin専用要求をviewer成功で代替せず、非同値ならFAILする。cleanupはreceiptが`owned`と証明するPID/profileだけを閉じ、既存Chromeや通常profileには触れない。

## 完了条件

- receiptのissuer、consumer、有効期限、capabilitiesを確認する。
- 認証・deploy包含確認が必要な用途はadapter成功証跡を残す。
- 操作結果はDOM値またはスクリーンショットで二値確認する。
- SKIPを成功扱いせず、失敗段階とreceipt IDを報告する。
