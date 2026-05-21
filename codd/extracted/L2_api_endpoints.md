---
id: L2_api_endpoints
layer: L2
title: "API Endpoints"
artifact_count: 0
---

# L2: API Endpoints

## 概要

提供されたコンテキスト内にAPIエンドポイントの実装ファイルは存在しない。

## 備考

- `requirements.txt` に `websocket-client>=1.6.0` の依存が記載されており、CDP（Chrome DevTools Protocol）デーモンモード用の `cdp_server.py` が言及されているが、当該ファイルはスキャン範囲外。
- 本システムはCLIベースのアーキテクチャであり、HTTP APIではなくファイルシステムとtmuxセッションを介したエージェント間通信を採用している。

## 関連ファイル

- [[L1_data_models]] — ファイルベースのデータアーキテクチャとインボックスYAML永続化を定義する。
- [[inbox_write_requirements]] — agent-to-agent communicationの実質API境界。引数、routing、YAML永続化、nudge順序を要求として定義する。
- [[inbox_write_design]] — mailbox writeの実装フローと副作用境界を説明する。
- [[L5_infrastructure]] — `requirements.txt` のPyYAML/websocket-client依存とCI/tmux/inotify系インフラを分類する。
- [[requirements.txt]] — CDP daemon mode用 `websocket-client` 依存の正本。

## Interface Boundary

HTTP API endpointは存在しないが、運用上のAPI境界は `scripts/inbox_write.sh <target_agent> <content> [type] [from] [action]` と `queue/inbox/{agent}.yaml` である。外部呼び出し側はHTTP routeではなく、CLI引数・YAML mailbox・tmux nudgeの順序契約に依存する。

[[inbox_write.sh]] がこのCLI API境界の実装正本であり、usage行で `<target_agent> <content> [type] [from] [action]` を定義する。[[test_inbox_write.bats]] はrouting・persistence・report gate side-effectの回帰検証を担う。
[[inbox_watcher.sh]] は永続化後のwake-up delivery側境界であり、inbox YAMLを監視して短い起動シグナルだけをtmuxへ送る。

CDPはWebSocket依存を持つ補助経路であり、このL2ではHTTP endpointとして数えない。CDP関連の実装・依存はインフラ層で扱う。
