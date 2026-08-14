# deploy_task制御面再高速化 CoDD Spec（2026-07-23）

## 問題

`scripts/deploy_task.sh`は過去に局所高速化済みだが、現行本番配備では再び制御面が支配している。直近20成功runは28.158〜161.014秒。4並列hotfix配備は101.405/114.683/146.273/161.014秒で、忍者が実装を始める前に最大161秒を消費した。

## 定量プロファイル（既存telemetry再利用）

| 対象 | 実測 |
|---|---:|
| 4並列wall | 101.405〜161.014秒 |
| preflight | 26.849/35.598/71.611/76.835秒 |
| task_mutations | 61.136/63.055/62.059/67.894秒 |
| 直近最速単発 | 28.158秒 |
| `field_get`参照 | 151箇所 |
| `yaml_field_set`参照 | 100箇所 |
| report publication（代表） | 15〜17秒 |

一次証跡は`logs/deploy_task.log`の`DEPLOY_WALL_PHASE`と`DEPLOY_RECEIPT`。専用計測runは作らない。

## リファクタリング対象

### R1: preflight入力snapshot共有

同一waveの4配備がproject/task/report/historyを個別走査し、並列時preflightが26秒から76秒へ悪化する。wave generation単位のread-only snapshotを一度生成し、各ninjaは同一snapshotからsame-cmd、collision、recent historyを判定する。安全判定の最終write直前だけ現物を再確認する。

### R2: task mutationの単一transaction化

151箇所の`field_get`と100箇所の`yaml_field_set`から、同一task YAMLの逐次read/writeを排除する。既存fast helperへmutation candidateを集約し、最後にparse検証付きatomic publishを1回行う。lesson/semantic/report identityの意味論は凍結する。

### R3: report publicationのwave共有cache

同一project・同一task schema generationで変わらないprotected report inventory、lessons catalog、semantic metadataをwave cacheへ移す。report identityと個別AC/binary checksはtask別生成を維持する。

### R4: phase予算とfail-fast

単発P95と4並列P95を別々に記録し、preflight 15秒、task mutation 25秒を超えたら最遅subphaseをreceiptへ必須出力する。timeoutで安全判定をskipしない。

## 実施順序

1. R1を実装し既存deploy fixtureをPASS。
2. 正規deploy telemetryでbefore/afterを比較。
3. R2を実装し構文・atomicity・並列fixtureをPASS。
4. R3、R4を順に適用。
5. 通常runnerの14列台帳と`DEPLOY_RECEIPT`で再計測する。

## 制約

- `--yaml`、`--direct`、通常cmd配備CLIを変更しない。
- task/reportの原子公開、stale reset、collision、lesson injection、nudge、post-deploy captureを削らない。
- 安全判定をcacheだけで確定せず、write直前に世代または現物を照合する。
- report identity、AC hash、lesson ranking、semantic matchingのロジックは凍結する。
- テストSKIPはFAIL。途中の可逆実験は軽量に回し、最終checkpointで全契約を検証する。

## 二値目標

- 4並列deploy wall P95: 161.014秒 → 60秒以下。
- 単発deploy P95: 77.041秒 → 30秒以下。
- preflight P95: 76.835秒 → 15秒以下。
- task mutation P95: 67.894秒 → 25秒以下。
- task/report公開欠落0、誤nudge0、collision見逃し0。
