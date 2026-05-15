```markdown
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
```
