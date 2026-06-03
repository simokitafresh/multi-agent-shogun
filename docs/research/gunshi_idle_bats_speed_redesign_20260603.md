# Batsテスト実行時間改善設計書 v2（殿原則準拠）

<!-- generated: 2026-06-03T10:30:00+09:00 by gunshi -->
<!-- v2: 将軍レビュー3問題を修正 (計測環境定義/python3箇所数/12倍乖離根因) -->
<!-- 殿原則: 1.不要テスト削除/統合 → 2.元スクリプト速度改善 → 3.テスト側改善 -->

## 計測環境定義（問題1修正）

| 環境 | 現状 | 改善対象か |
|------|------|-----------|
| **CI (GitHub Actions)** | 3分31s〜4分11s | **否。既に4分以下** |
| **ローカル (WSL2 NTFS)** | **8分55秒** | **是。これが改善対象** |

**改善対象はローカルWSL2 NTFSのみ。** CIは既に3分台で問題なし。
ローカルが遅い根因はNTFS I/Oペナルティ(ext4比10-50倍)とpython3起動コスト。

## 現状（ローカル実測 2026-06-03）

| 指標 | ローカル | CI |
|------|---------|-----|
| 全量実行時間 | **8分55秒**（535s） | 3分31s〜4分11s |
| テストファイル数 | 162 | 同 |
| テスト件数 | 2,063 | 同 |

### 12倍乖離の根因（問題3解消）

warn_logging 82.9s vs tobisaru報告6.7sの乖離原因を**個別テスト計測で特定**:

| テスト | 時間 | 根因 |
|--------|------|------|
| AC1(bare WARN_COUNT grep) | **0.9s** | grepのみ。問題なし |
| AC2(WARN entry記録) | **90.3s** | `run_save`=cmd_save.sh(5,543行)フル実行×1回 |
| AC3(Session State grep) | **183.9s** | `run_save`×2回(履歴作成+2回目挙動) |

**根因: `run_save`がcmd_save.sh全体を毎回フル実行。** 5,543行のbashパース+94関数定義+26箇所のpython3呼出し+NTFS I/O。1回あたり約90秒。AC3は2回呼ぶので180秒。

tobisaru報告の6.7sは**FAST_METADATA=1で教育的表示をスキップした効果**だが、ローカルWSL2ではFAST_METADATAで省略されない処理(bashパース+関数定義+python3起動)がI/Oペナルティで支配的。

### ボトルネックTOP11（上位78%）

| ファイル | 時間 | テスト数 | 秒/件 | 元スクリプト行数 |
|---------|------|---------|-------|----------------|
| test_semantic_index_update | **103s** | 28 | 3.7 | 1,273行 |
| test_gate_shogun_startup | **98s** | 52 | 1.9 | 2,955行 |
| test_cmd_save | **54s** | 103 | 0.5 | 5,543行 |
| test_deploy_task_ac_handling | 34s | 36 | 0.9 | 7,534行 |
| test_deploy_task_ac_version | 29s | 27 | 1.1 | 7,534行(同一) |
| test_cmd_complete_gate | 25s | 120 | 0.2 | 7,102行 |
| test_memory_db | 24s | ? | ? | - |
| test_deploy_task_lifecycle | 19s | ? | ? | 7,534行(同一) |
| test_ninja_monitor_stall | 11s | ? | ? | - |
| test_skill_feedback_loop | 10s | ? | ? | - |
| test_ninja_monitor_clear_guard | 10s | ? | ? | - |
| **合計** | **417s** | - | - | **78%** |
| 残り151ファイル | 118s | - | - | 22% |

### python3箇所数（問題2修正: 実測値）

| スクリプト | python3行数(grep -c) | 設計書v1の値 | 乖離 |
|-----------|---------------------|------------|------|
| gate_shogun_startup.sh | **24箇所** | 9箇所 | 2.7倍過小 |
| cmd_save.sh | **26箇所** | 164回(テスト内) | 計測方法混同 |

## Phase 1: 不要テストの削除・統合

### 1-1. cmd_save run_save呼出しの構造問題
warn_logging 5テスト中3テストがrun_save(=cmd_save.shフル実行)を1-2回呼ぶ。
**問いかけ**: これらのテストは本当にcmd_save.sh全体を実行する必要があるか？
- AC1(grep)はスクリプト実行不要。OK
- AC2(WARN entry記録)は`record_warn_reason`関数だけテストすればよいのでは？
- AC3(Session State)は`show_lord_conversation_matches`関数だけで済むのでは？

テスト対象を**関数単位**に限定できれば:
- 90s/回 → source 0.3s + 関数実行数秒 ≈ 数秒/回
- warn_logging合計: 275s → 数秒

### 1-2. 重複テスト検出
```bash
for f in tests/unit/test_cmd_save*.bats; do
  grep '@test' "$f" | sed 's/@test "\(.*\)".*/\1/'
done | sort | uniq -d
```

## Phase 2: 元スクリプトの実行速度改善

### 2-1. cmd_save.sh (5,543行, python3: 26箇所)
**最大のボトルネック**: テストがcmd_save.shフル実行を繰り返す。
- フル実行1回≈90s(ローカル)
- python3 26箇所 × 53ms起動 = 1.4s(起動のみ。処理時間別)
- **改善案**: python3 heredoc統合(26→数回)。ただし起動コストは1.4sで支配的ではない。処理自体の速度(YAML parse, grep走査)が本体

### 2-2. gate_shogun_startup.sh (2,955行, python3: 24箇所)
- テスト52件×python3起動24箇所の一部 = 数百回のpython3起動
- **改善案**: python3統合(24→数回)。L703で3→1統合の実績あり

### 2-3. semantic_index_update.sh (1,273行)
- 103s/28件。各テストがpython3処理を含む
- cmd_3145でDB参照除外済み

## Phase 3: テスト側の改善

Phase 1-2で解決しない残りのみ。

## 実行計画

| 順序 | 内容 | 予測効果 | 根拠 |
|------|------|---------|------|
| 1 | **warn_logging run_saveを関数単位testに変更** | **275s→数秒** | AC2/3/3b/4がcmd_save.shフル実行不要 |
| 2 | 他のtest_cmd_save_*.batsで同様のフル実行パターンを検出・修正 | 要計測 | 24ファイル走査 |
| 3 | gate_shogun python3統合(24→数回) | 要プロファイル | 実測なし |
| 4 | 重複テスト検出・削除 | 要計測 | 1-2の結果次第 |

**目標**: ローカル8分55秒 → **5分以下**

## 因果リンク

- → [[殿指摘_Bats時間バグ]] 殿の直接指摘
- → [[殿原則_テスト改善順序]] 削除→スクリプト→テストの順序
- → [[将軍レビュー_3問題]] 計測環境定義/python3箇所/12倍乖離
- → [[run_save_full_execution]] 根因=cmd_save.shフル実行×毎テスト
