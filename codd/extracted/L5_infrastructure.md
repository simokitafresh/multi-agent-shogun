```markdown
---
id: L5_infrastructure
layer: L5
title: "Infrastructure / Config"
artifact_count: 68
---

# L5: Infrastructure / Config

## 概要

GitHub Actions CI/CD、Androidビルドシステム（Gradle/Kotlin DSL）、git hooks（lefthook）、シークレットスキャン（gitleaks）、Python依存管理、32のプロセスロックファイル、およびプロジェクトドキュメントで構成。

## 5.1 CI/CD (1 file)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `.github/workflows/test.yml` | — | GitHub Actions: unit-tests, build-check, shellcheck, e2e-tests, integration-tests |

ジョブ構成:
- **unit-tests**: bats-core による単体テスト（8並列）+ SKIP=FAIL ポリシー（FR-054）
- **build-check**: `scripts/build_instructions.sh` の同期確認
- **shellcheck**: `lib/` および `scripts/` のシェルスクリプトリント
- **e2e-tests**: tmux + inotify-tools によるE2Eテスト（unit-tests, shellcheck 後）
- **integration-tests**: Claude専用統合テスト（copilot/codex タグ除外）

## 5.2 Git設定 (3 files)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `.gitattributes` | 232 B | ファイル属性・改行コード設定 |
| `.gitignore` | 6,140 B | Git除外パターン |
| `.gitleaks.toml` | 4,181 B | シークレット検出ルール |

## 5.3 プロジェクト設定 (8 files)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `.codd_version` | 6 B | CoDD バージョンマーカー |
| `.shellcheckrc` | 39 B | ShellCheck 設定 |
| `lefthook-local.yml` | 81 B | ローカルgit hooks設定 |
| `lefthook.yml` | 89 B | git hooks設定 |
| `requirements.txt` | 109 B | Python依存（PyYAML, websocket-client） |
| `install.bat` | 5,464 B | Windowsインストーラー |
| `CLAUDE.md` | 42,968 B | Claude Code AI設定 |
| `CLAUDE.md.bak.jp.20260421` | 39,267 B | CLAUDE.md バックアップ |

## 5.4 プロジェクトドキュメント (5 files)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `LICENSE` | 1,064 B | ライセンス |
| `CONTRIBUTING.md` | 12,770 B | コントリビューションガイド |
| `README.md` | 60,405 B | プロジェクト説明（英語） |
| `README_ja.md` | 66,644 B | プロジェクト説明（日本語） |
| `SECURITY.md` | 9,534 B | セキュリティポリシー |

## 5.5 Androidビルドシステム (13 files)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `android/.gitignore` | 107 B | Android用Git除外 |
| `android/build.gradle.kts` | 260 B | ルートGradleビルド |
| `android/gradle.properties` | 190 B | Gradleプロパティ |
| `android/gradlew` | 6,190 B | Gradleラッパースクリプト |
| `android/local.properties` | 172 B | ローカルSDKパス |
| `android/settings.gradle.kts` | 400 B | Gradleモジュール設定 |
| `android/app/build.gradle.kts` | 2,728 B | アプリモジュールビルド |
| `android/app/proguard-rules.pro` | 214 B | ProGuard難読化ルール |
| `android/gradle/libs.versions.toml` | 3,267 B | バージョンカタログ |
| `android/gradle/wrapper/gradle-wrapper.jar` | 43,462 B | Gradleラッパーバイナリ |
| `android/gradle/wrapper/gradle-wrapper.properties` | 257 B | Gradleラッパー設定 |
| `android/README.md` | 4,455 B | Android README（英語） |
| `android/README_ja.md` | 4,756 B | Android README（日本語） |

## 5.6 ランタイムアーティファクト (5 files)

シェル実行時に生成されたアーティファクトファイル。

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `nohup.out` | 25,217 B | バックグラウンド実行ログ |
| `=1.6.0` | 1,024 B | pip構文エラーによるアーティファクト |
| `[]` | 0 B | シェル変数展開アーティファクト |
| `main` | 0 B | 空ファイル |
| `None` | 0 B | Python None出力アーティファクト |

## 5.7 ログ (1 file)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `archive/frozen/inbox_watcher_gunshi.log` | 2,505 B | gunshiインボックスウォッチャーのログ |

## 5.8 ロックファイル (32 files)

プロセス排他制御用のロックファイル。

| 対象 | ファイル数 |
|------|-----------|
| エージェントスクリプト | 9 (`hanzo.lock`, `hayate.lock`, `kagemaru.lock`, `kirimaru.lock`, `kotaro.lock`, `saizo.lock`, `sasuke.lock`, `tobisaru.lock`, `set.lock`) |
| データファイル | 3 (`$R.lock`, `$REPORT.lock`, `dashboard.md.lock`) |
| 初期化 | 1 (`initialize.lock`) |
| レポート | 19 (各 `*_report_cmd_*.lock`) |

合計: 32
```
