```markdown
---
id: L3_ui_pages
layer: L3
title: "UI Pages"
artifact_count: 12
---

# L3: UI Pages

## 概要

Androidアプリ「Shogun」がモバイルUIを提供。マルチエージェントシステムのターミナル操作、エージェントグリッド表示、ダッシュボード、設定、レート制限の5画面構成。

## Source Traceability

UI entry and routing evidence starts at [[AndroidManifest.xml]], whose activity and service declarations define the mobile app shell. Visual state evidence is represented by screenshot artifacts such as [[01_shogun_terminal.png]], and resource naming/theme evidence is rooted in Android resources such as [[strings.xml]].

## 3.1 画面定義 (1 file)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `android/app/src/main/AndroidManifest.xml` | 2,027 B | アクティビティ・パーミッション・画面ルーティング定義 |

注: `android/app/src/main/java/` および `android/app/src/main/res/` ディレクトリは存在するが、内部ファイルはスキャン範囲外。

## 3.2 APKビルド成果物 (6 files)

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `shogun-v5.5.apk` | 17,875,151 B | リリースビルド v5.5 |
| `shogun-v5.6.apk` | 17,871,171 B | リリースビルド v5.6 |
| `android/release/multi-agent-shogun.apk` | 12,869,163 B | マルチエージェントリリース |
| `android/release/shogun-v5.8-debug.apk` | 18,366,130 B | デバッグビルド v5.8 |
| `android/release/shogun-v5.9-debug.apk` | 18,366,130 B | デバッグビルド v5.9 |
| `android/release/shogun-v6.2-debug.apk` | 18,849,543 B | デバッグビルド v6.2 |

## 3.3 UIスクリーンショット (5 files)

| ファイル | 画面名 |
|---------|--------|
| `android/screenshots/01_shogun_terminal.png` | ターミナル画面 |
| `android/screenshots/02_agents_grid.png` | エージェントグリッド画面 |
| `android/screenshots/03_dashboard.png` | ダッシュボード画面 |
| `android/screenshots/04_settings.png` | 設定画面 |
| `android/screenshots/05_ratelimit.png` | レート制限画面 |

## 関連レイヤーとコンテキスト

- [[L1_data_models]] — L1: Data Models。インボックスYAML/レポートYAMLがUIの状態ソース
- [[L2_api_endpoints]] — L2: API Endpoints。CLIベースのためHTTP API不在
- [[L4_business_logic]] — L4: Business Logic (layer: L4)
- [[L5_infrastructure]] — L5: Infrastructure / Config (layer: L5)
- [[L6_tests]] — L6: Tests (layer: L6)
- [[infrastructure]] — §Android App (line 579): "v6.4(versionCode 15)、SSH経由でtmuxを操作し、Dashboard/Agents/ShogunScreen/Settings/GistIndex/Usage を提供する"
```
