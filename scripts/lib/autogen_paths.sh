#!/usr/bin/env bash
# scripts/lib/autogen_paths.sh — 自動生成/運用ファイルパスの共有判定
#
# GA-PUSH1(.githooks/pre-push のdirty working tree guard)と
# cmd_complete_gate.sh(uncommitted変更検出)が、エージェントのターン終了ごとに
# 再生成される索引(context/lord-conversation-index.md等)を「実害のある未確定
# 変更」として誤検知する問題を同じ理由で持っていた。cmd_complete_gate.sh:3268
# の除外リストが先行して実測済みの正本であるため、これを共有化しGA-PUSH1側の
# 重複作成を避ける(車輪の再発明防止)。
#
# 対象はqueue/・logs/配下の運用YAML、dashboard.md、および
# conversation_retention.sh等が生成時刻のみで毎回差分を作るcontext索引。
# 除外根拠は「自動生成であること」であり、判定手段は現状パス列挙のみ
# (2026-07-26時点でパス以外の機械可読な自動生成マーカーは対象ファイル間で
# 不統一なため。将来ファイルが増えると個別追記が漏れる設計だが、殿の過剰対策
# 禁止原則によりこの粒度で維持する)。
#
# docs/semantic-index/index.md(cmd_karo_hotfix_prepush_semantic_index_autogen_20260730):
# ninja_monitor.shのreflux backlink自動配備がSSOTへ因果リンクを追加する非同期commitを
# 生成する。これがpush対象commitの変更pathと重なると、他の自動生成pathと同じ理由
# (再生成のたびに差分が出る)でGA-PUSH1が反復BLOCKする。exact pathのみ除外し、
# 通常source pathとの混在は従来どおりBLOCKを維持する。
# projects/*/lessons.yaml と tasks/lessons.md は lesson writer/sync のSSOT・cache
# 出力であり、同一lessonの公開と再同期が重なると同じ再生成差分になる。runtime-only
# publication の正規path契約と同じ exact pattern で除外し、通常sourceとの混在は
# 引き続きBLOCKする。

export AUTOGEN_PATH_EXCLUDE_REGEX='^queue/|^logs/|^dashboard\.md$|^context/lord-conversation-index\.md$|^context/senkyoku-log\.md$|^context/cmd-chronicle\.md$|^context/dm-signal-research\.md$|^docs/semantic-index/index\.md$|^projects/[^/]+/lessons\.ya?ml$|^tasks/lessons\.md$|\.log$'
