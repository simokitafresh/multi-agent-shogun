# Google Classroom Dashboard — Context Index
<!-- last_updated: 2026-06-20 -->

> Playwright headlessでGoogle Classroomをスクレイピング→ダッシュボード+試験対策まとめ生成。
> PJ復帰: 2026-03-23殿裁定。CDP統合せず別PJ。
> repo: `github.com/simokitafresh/google_classroom` | path: `/mnt/c/Python_app/google_classroom`

## §0 現在状態

- `config/projects.yaml` 上の project id は `google-classroom`
- path: `/mnt/c/Python_app/google_classroom`、repo: `https://github.com/simokitafresh/google_classroom`
- priority: `high`、status: `active`
- `current_project` は `dm-signal`。Google Classroom は active だが現在フォーカスPJではない
- **運用形態(2026-06-19)**: 殿が別ノートPCで1日4回スクレイピング自動実行(012.md Phase 0相当を実現)。メインPC依存排除済み
- **Android/WebView(2026-06-20)**: v5.6系でサイドバー2行表示の根因を `height:100vh`/padding/display復元に特定し、`build_dashboard.py` と生成HTMLへ反映。`SyncManager` は404耐性追加済み
- **学年**: 8年ふじ組(2026年度)。build_dashboard.pyのCOURSE_NAME_MAPに8年コース追加済み
- **スクリプト19本**: build_dashboard.py(2017行), scrape_classroom.py(1034行), auto_update.py, download_attachment_images.py, capture_form_images.py, refresh_session.py等
- **堅牢化**: scrape失敗時full update fail(20fea50), ダッシュボード縮小ガード(37de46b), 日付処理改善(最終編集時刻補完)
- **auto-update**: 4時間間隔でauto-commit+push(git log: 01:25, 05:25, 09:25, 13:25, 17:25, 21:25)
- 開発履歴の正本: `/mnt/c/Python_app/google_classroom/docs/dev-history.md`(008.md設計)
- 計画文書: `/mnt/c/Python_app/google_classroom/docs/future/` (008: dev-history, 009: NotebookLM連携, 010: 学習サポート自動化, 011: マルチノード環境, 012: mini PC無人運用)

## §1 スクレイピング/セレクタ

Google Classroom DOMは頻繁に変化する。セレクタ選定と検証が品質の要。

- L003: CSSセレクタ変更は実DOM検証なしに行ってはならない。headlessで0件ヒットのregression原因（cmd_1055検証）
- L004: DOM属性安定性ランク: `data-stream-item-id` > `ol li[jsaction]` > `li.tfGBod`。想定と実態が異なった（006.md検証）
- L005: classwork展開判定は`data-controller-loaded="false"`を使う。`aria-expanded`は`<li>`に付かない（006.md検証）
- L006: 当日投稿は「作成 HH:MM」形式で日付部分がない。`r'作成\s*(\d{1,2}):(\d{2})'`パターン追加でtoday()返却（7ふじHR検証）
- L011: 同一コミットでツール定義と参照先を同時変更すると旧セレクタが残存する。変更後にツール側定義を最終確認すべき（cmd_1058）

## §2 実行環境

Windows Python + WSL2の二重環境による制約。

- L002: Windows Python + `-X utf8`フラグ必須。WSLにPlaywright未インストール、cp932でUnicodeEncodeError（cmd_1055）
- L007: PowerShellインラインPythonでf-stringの`{dict["key"]}`はエスケープ破壊。一時スクリプトファイルに書いて実行（検証全般）

## §3 デプロイ/Docker

Render cronjob化に向けたDocker構成の注意点。

- L008: PlaywrightバージョンはDockerベースイメージとpipで一致させよ。不一致でブラウザ起動不可（007.md調査）
- L009: `browser_data/` git pushはキャッシュ除外必須。セッション維持に必要なのはcookie等~11MBのみ、キャッシュ295MB+111MBは自動再生成（007.md調査）
- L010: `server.py`のDATA_DIRデフォルト`/data`（Docker向け）と子スクリプトの`Path(__file__).parent.parent`が不一致。Docker内はenv伝搬で整合するがローカルで乖離（007.md調査）

## §4 配備/運用

マルチエージェント配備時の注意。

- L001: `auto_login.py`と`scrape_classroom.py`は密結合。並列配備で作業重複発生。密結合ファイルは同一忍者に配備 or ファイル境界を明示（cmd_1055）

<!-- last_synced_lesson: L011 -->
