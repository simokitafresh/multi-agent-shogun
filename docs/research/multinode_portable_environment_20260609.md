# マルチノード環境ポータビリティ構想 — 2026-06-09

> **ステータス: 温め中（殿裁定 2026-06-09）**
> google-classroom 011.md/012.md の議論から発展。Classroom専用mini PCが最初の1台。

## 殿の構想

「MacやWindowsなどのPCを様々な場所に置いておき、いつでもどこでも同じ環境で作業ができるようにしたい」

## 背景（2026-06-09対話から）

- Classroomの手動デプロイ煩雑→自動化検討→ローカルPC依存が根本問題
- Classroom API不可（学校Workspace管理者制限）→Playwrightスクレイピング必須→ブラウザセッション依存
- 専用mini PC(012.md)でClassroom自動化→「将軍システムごとMacに移せないか」→マルチノード構想に発展
- 殿: 「ローカルのDBもクラウド経由で同期すればいいだろ？」

## 同期レイヤー設計

| レイヤー | 現状 | マルチノード化 |
|---------|------|--------------|
| コード | GitHub | そのまま。git pull/pushで同期済み |
| 三層記憶DB | SQLiteローカルファイル(`data/multi_agent_shogun_memory.db`) | クラウド同期(Syncthing/Dropbox/Google Drive)。SQLite=単一ファイル |
| queue/状態 | ローカルYAML | クラウド同期。書込み競合対策(flock/advisory lock)が必要 |
| .env/secrets | ローカル | 各PC個別管理 or 暗号化同期 |
| browser_data/ | ローカル(PC固有セッション) | 各PCで個別維持。CDPで操作 |
| settings.yaml | ローカル | 同期。ただしPC固有設定(ペインID等)は分離が必要 |

## OS非依存化の課題

- 将軍システムのscriptsに`/mnt/c`参照が124箇所（WSL2固有パス）
- hooks: 6箇所がWSL2/Windows固有
- PowerShellスクリプト: Mac非対応
- `first_setup.sh`はUbuntu/WSL/Mac対応済み（2026-05-17確認）

## 段階的アプローチ

| Phase | 内容 | 前提 |
|-------|------|------|
| 0 | 012.md: Classroom専用mini PC(N100 or Mac mini)でClassroom自動化 | ハードウェア購入 |
| 1 | google_classroomリポジトリのLinux/Mac動作確認+cron登録 | Phase 0のPC上で |
| 2 | 将軍システムの`/mnt/c`依存を環境変数化(`$PROJECT_ROOT`等) | cmd発令で段階的移行 |
| 3 | 三層記憶DB+queue/のクラウド同期設定(Syncthing推奨: P2P、サーバー不要) | Phase 2完了 |
| 4 | 2台目のPC(Mac)で将軍システム起動→同一環境確認 | Phase 2+3 |

## 技術選定メモ

### 同期ツール候補

| ツール | 方式 | 利点 | 欠点 |
|--------|------|------|------|
| **Syncthing** | P2P | サーバー不要、無料、リアルタイム、`.stignore`で除外制御 | 両PC起動時のみ同期 |
| Dropbox/Google Drive | クラウド | 片方オフラインでも同期 | 月額コスト、SQLite同時書込み問題 |
| rsync + cron | バッチ | シンプル | リアルタイムではない |

Syncthing推奨。P2Pで直接同期、サーバー費用ゼロ、`.stignore`でnode_modules等除外可能。

### SQLite同期の注意

- SQLiteは同時書込みに弱い。2台のPCから同時に将軍システムが記憶DBに書込むと壊れる
- 対策: アクティブな将軍は1台のみ。他のPCはread-onlyまたは待機
- WALモード(既に有効)で読込みは並行可能

### Mac上でのCDP

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=browser_profiles/lord/
```

macOSで確認済み(Web検索 2026-06-09)。Windowsと同じCDPプロトコル。

## 関連ドキュメント

- `/mnt/c/Python_app/google_classroom/docs/future/011.md` — 自動デプロイ+Gmail統合
- `/mnt/c/Python_app/google_classroom/docs/future/012.md` — 専用mini PC設計
- `context/infrastructure.md` — 将軍システムインフラ
- `first_setup.sh` — Mac対応済み初回セットアップ

## 因果リンク

- ← [[google_classroom]] Classroomの手動デプロイ問題が発端
- → [[infrastructure]] 将軍システムOS非依存化
- → [[仙人構想]] 将来的にマルチノードの将軍が分散稼働する可能性
