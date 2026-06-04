# events.state定義の不整合 — memory_db_live_insert.py vs obsidian_promote_candidate.sh

## 分析日時
2026-06-03T22:20+09:00

## 発見経緯
セマンティック監査Step 7(implicit_assumption カテゴリ)で検出。
直近変更(cmd_3153 state追加 + cmd_3161 obsidian_promote追加)の相互作用。

## 問題
events.stateの有効値セットが2箇所で別々に定義されている:

| ファイル | 変数/定数 | 値セット |
|---------|----------|---------|
| memory_db_live_insert.py | VALID_EVENT_STATES | {raw, contradiction_candidate, duplicate_candidate} |
| obsidian_promote_candidate.sh | NORMAL_STATES | (raw, verified) |
| obsidian_promote_candidate.sh | SQL UPDATE | "obsidian_candidate" |
| context/memory-db-schema.md | ドキュメント | raw, verified, obsidian_candidate (設計書に記載) |

## 不整合の詳細
1. `obsidian_candidate` — schema.mdに記載あり、promote_candidate.shで使用、VALID_EVENT_STATESに不在
2. `verified` — promote_candidate.shのNORMAL_STATESに含まれる、VALID_EVENT_STATESに不在
3. promote_candidate.shはSQL直接UPDATE(append_event経由ではない)のためVALID_EVENT_STATES検証をバイパス

## 現時点の影響
- **動作には問題なし**: promote_candidate.shはSQL直接UPDATEでVALID_EVENT_STATES検証を通らない
- **将来リスク**: append_eventでstate="obsidian_candidate"を指定するコードが追加された場合にValueError

## 対策案
1. **SSOT化**: events.stateの全有効値を1箇所(memory_db_live_insert.pyまたは共通モジュール)で定義し、他スクリプトからimport/参照
2. **最小修正**: VALID_EVENT_STATESに`obsidian_candidate`と`verified`を追加

## 優先度
P2(中優先) — 現時点で動作問題なし。ただしstate管理が分散すると将来の拡張でバグが発生する。

## セルフレビュー
1. 数値: 2ファイル、3定数/変数、5つのstate値(raw/verified/contradiction_candidate/duplicate_candidate/obsidian_candidate)
2. 前提: memory_db_live_insert.py L24/L479、obsidian_promote_candidate.sh L86/L193をgrep確認
3. 事前検死: 最小修正(VALID_EVENT_STATES拡張)はリスク低。SSOT化はモジュール構造変更が必要で規模大
