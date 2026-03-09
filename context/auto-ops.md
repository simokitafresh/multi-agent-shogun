# Auto-Ops Context
<!-- last_updated: 2026-03-08 -->

## 概要

CDP(Chrome DevTools Protocol) + Google Workspace CLI によるデスクトップ・ブラウザ自動化基盤。

- repo: https://github.com/simokitafresh/auto-ops (private)
- path: `/mnt/c/Python_app/auto-ops`

## 技術スタック

### CDP (Chrome DevTools Protocol)
- WSL2 → PowerShell → Edge/Chrome CDP(port 9223)でDOM直接操作
- Computer Useの2倍速・裏動作・トークン安
- B64エンコードで4重クォート回避
- 参考: https://zenn.dev/shio_shoppaize/articles/wsl2-edge-cdp-automation

### Google Workspace CLI (gws)
- `npm i -g @googleworkspace/cli`
- Gmail, Drive, Calendar, Sheets, Docs, Chat, Admin対応
- MCP標準搭載 + 40以上のAgent Skills
- Rust製、Apache 2.0

## 設計方針

- CDP: ブラウザでしかできない操作（ログイン・DOM操作・PDF取得）
- gws: Google API操作（メール検索・Drive保存・改名）
- 外部ライブラリ依存最小（標準ライブラリ優先）

## ユースケース候補

- Gmail領収書メール → リンク先ログイン → PDF取得 → Drive保存+改名
- ブラウザ体感速度計測（DM-signal等のフロントエンド検証）
- Google Workspace定型業務自動化
