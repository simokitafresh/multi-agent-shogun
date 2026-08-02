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

CDP操作の入口は共有foundationだけである。用途wrapperは下記と同じsession確立を内部実行し、`cdp_session_foundation`発行のreceiptがない接続をfail-closedで拒否する。

```bash
python3 scripts/cdp/cdp_session.py establish --consumer "$CONSUMER" --ports 9222,9223,9224 --receipt "$RECEIPT"
```

`CONSUMER`は`inspection`、`measurement`、`note`、`generic`のいずれか、`RECEIPT`は当該実行だけが読める一時ファイルとする。個別にブラウザ、daemon、port、credentialを準備してはならない。終了時はwrapperのtrapまたは `cdp_session.py cleanup --receipt "$RECEIPT"` に任せる。

## 用途写像

- DM-Signal検分: `inspection` receiptを消費する `scripts/cdp/cdp_*_probe.py` を選び、認証が必要なら `scripts/cdp/dm_signal_adapters.py` のauth/deploy adapterを使う。
- 性能計測: `measurement` receiptを内部で確立・消費する `bash scripts/cdp/cdp_measure.sh <cmd_id> ...` を使う。
- note下書き: `note` receiptを内部で確立・消費する `bash scripts/note_draft.sh <article.md>` を使う。
- 汎用操作: `generic` receiptを確立し、そのreceiptのendpointだけをnavigate/click/type/screenshot操作へ渡す。

## A7欠陥と実装保証

| A7 | 実装済み保証 | 一次正本 |
|---|---|---|
| 1. port占有時に復旧不能 | 9222→9223→9224の有限fallback、全候補失敗は明示FAIL | `scripts/cdp/cdp_session.py` |
| 2. admin 401分岐なし | admin失敗後、要求権限がviewerの場合だけviewerへfallback | `scripts/cdp/dm_signal_adapters.py` |
| 3. viewer認証が暗黙 | adapterがVIEWER_PASS読込とReact input eventを内包 | `scripts/cdp/dm_signal_adapters.py` |
| 4. 発火が字句依存 | 全用途をfoundation receiptの同一入口へ固定 | `docs/research/cdp-session-contract-v1.yaml` |
| 5. 推薦止まり | consumerがreceiptなしの接続を受理しない | `scripts/cdp/cdp_session.py`、各consumer wrapper |
| 6. 役割別に入口が自由 | inspection/measurement/note/genericの4 consumerを同じissuerへ固定 | `docs/research/cdp-session-contract-v1.yaml` |
| 7. 台帳破損で使用率不明 | receiptのconsumerとskill実行台帳で役割別計測 | `logs/skill_execution_log.yaml` |

foundationはWindows側Chromeを必ず隔離profileとremote-debugging設定で起動する。auth adapterはadmin専用要求をviewer成功で代替せず、非同値ならFAILする。cleanupはreceiptが`owned`と証明するPID/profileだけを閉じ、既存Chromeや通常profileには触れない。

## 完了条件

- receiptのissuer、consumer、有効期限、capabilityを確認する。
- 認証・deploy包含確認が必要な用途はadapter成功証跡を残す。
- 操作結果はDOM値またはスクリーンショットで二値確認する。
- SKIPを成功扱いせず、失敗段階とreceipt IDを報告する。
