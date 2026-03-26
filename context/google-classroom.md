# Google Classroom Dashboard — Context Index

> Playwright headlessでGoogle Classroomをスクレイピング→ダッシュボード生成。Render cronjob化予定。
> PJ復帰: 2026-03-23殿裁定。CDP統合せず別PJ。
> repo: `github.com/simokitafresh/google_classroom` | path: `/mnt/c/Python_app/google_classroom`

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
