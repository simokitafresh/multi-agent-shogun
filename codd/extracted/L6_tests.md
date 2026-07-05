```markdown
---
id: L6_tests
layer: L6
title: "Tests"
artifact_count: 0
---

# L6: Tests

## 概要

テストファイルは提供されたスキャン範囲に含まれていない。ただし、CI設定（`.github/workflows/test.yml`）から以下のテストインフラが存在することが確認できる。

## CIから判明するテスト構成

| テスト種別 | パス | 実行方法 |
|-----------|------|---------|
| ルートレベルテスト | `tests/*.bats` | bats, 8並列 |
| 単体テスト | `tests/unit/*.bats` | bats, 8並列 |
| E2Eテスト | `tests/e2e/*.bats` | bats, 1並列（tmux + inotify-tools） |
| 統合テスト | `tests/integration/*.bats` | bats, `--filter-tags '!copilot,!codex'` |
| テストユーティリティ | `scripts/count_bats_skips.sh` | SKIPカウント検証 |
| Androidテスト | `android/app/src/test/java/` | ディレクトリ存在、ファイル不明 |

## テストポリシー

- **SKIP=FAIL ポリシー (FR-054)**: スキップされたテストは失敗扱い。CI上で `count_bats_skips.sh` により0スキップを強制。
- **テストフレームワーク**: bats-core + bats-support + bats-assert
- **E2E依存**: tmux, inotify-tools, python3-yaml
- **統合テスト**: Claude専用（copilot/codexタグは除外）

## 改善候補

1. **L5との双方向リンク不足**: `[[L5_infrastructure]]` 5.1節がCI/CDジョブから本ファイルへリンクしている一方、本ファイルからCI/CD定義層への戻りリンクがなかった。テスト構成はCIジョブに従属するため、変更影響を追えるようCross-Referencesで明示する。
2. **artifact_count=0の理由が弱い**: テストファイルがスキャン範囲外だったことは書かれているが、`.github/workflows/test.yml` が参照する実テストパスの存在有無までは整理していない。次回は `tests/*.bats` / `tests/unit/*.bats` / `tests/e2e/*.bats` / `tests/integration/*.bats` の実ファイル数を追記する。
3. **SKIP=FAILの検証経路が抽象的**: `scripts/count_bats_skips.sh` の役割はあるが、CIの該当ステップやローカル検証コマンドへの参照が不足している。次回はCI行とローカル実行例を接続する。
```

---

**サマリー:**

| レイヤー | 名称 | ファイル数 |
|---------|------|-----------|
| L1 | Data Models | 384 |
| L2 | API Endpoints | 0 |
| L3 | UI Pages | 12 |
| L4 | Business Logic | 17 |
| L5 | Infrastructure / Config | 68 |
| L6 | Tests | 0 |
| **合計** | | **481** |

L1が圧倒的に多いのは、エージェント10体分の日次YAMLインボックスメッセージ（325件）がデータストアとして蓄積されているためです。L2とL6が0なのは、APIサーバー実装とテストファイルが提供されたスキャン範囲に含まれていないことによります。

## Cross-References

- [[L5_infrastructure]] — L5のCI/CDパイプラインが本L6のテストスイートを実行する。`L5_infrastructure.md` 5.1節では `unit-tests`、`e2e-tests`、`integration-tests` とSKIP=FAILポリシーがCIジョブとして整理されている。
