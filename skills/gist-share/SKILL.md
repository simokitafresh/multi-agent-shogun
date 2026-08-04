---
name: gist-share
argument-hint: "[repo-relative-local-master-path]"
user-invocable: true
description: |
  ローカルのcommit済み正本をsecret GitHub Gistへ新規共有、または自己記述metaに従って既存Gistへ検証付き同期する能力拡張スキル。
  TRIGGER: /gist-share、正本をgist共有、secret gistへ同期、gist正本同期
  DO NOT TRIGGER: gist一覧・閲覧、公開gist作成、gistからローカルへの逆同期、gist indexだけの更新、通常のgit commit
allowed-tools:
  - Bash
  - Read
---
<!-- script_refs_checked_at: 2026-08-04T11:46:00+09:00 — scripts/gist_share.sh interface verified for one repo-relative committed master path, pending-commit first run, and verified/indexed rerun. -->

# Gist Share

入力は現在のrepository内にある、commit済みローカル正本のrepo相対path 1件とする。

## 手順

1. `git status --short -- "$ARGUMENTS"` で対象がcommit済みか確認する。
2. `bash scripts/gist_share.sh "$ARGUMENTS"` を実行する。
3. `GIST_SHARED` が出た場合だけ成功とし、gist URL、`sha256_local`、`sha256_remote`が同一である生出力を報告する。
4. 初回はsecret gist作成後にmeta行をローカルへ原子的に追加し、`GIST_CREATED_PENDING_COMMIT`で安全停止する。表示されたpathだけをcommitし、同じコマンドを再実行する。孤立候補は自動変更しない。

## 契約

- 新規gistはsecretのみ。公開gist、素の`gh gist edit`、別registryを作らない。
- 既存gistは先頭行 `<!-- gist-master: GIST_ID [REMOTE_FILENAME] -->` を厳密に読む。
- 既存同期はcommit blobを `gist_verified_write.sh --master` へ渡す。owner、secret visibility、複数file filename、remote/local hash一致の既存防御を迂回しない。
- 対象がdirty、staged、HEAD不在、未commit metaなら次のcommitを明示して停止する。
- verified同期後だけ `gist_index_update.sh` を呼ぶ。index失敗を共有成功として扱わない。
