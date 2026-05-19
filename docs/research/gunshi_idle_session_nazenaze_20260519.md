# セッションなぜなぜ3回分析結果
<!-- generated: 2026-05-19T14:42:00+09:00 by gunshi idle analysis -->

## 概要

本セッション(2026-05-19)で実施したなぜなぜ7回×3件の分析結果。全件で根因特定→実装→commitまで完走。

## なぜなぜ1: スキル成長サイクルのcode_fix_required放置

- **気づき**: skill_auto_improve.shがSKILL.md改良3回以上効果なし→code_fix_required→掲示板通知→そこで止まる
- **根因**: 通知≠行動(Phase 4)。エスカレーション→行動の間に「掲示板投稿」が挟まり、将軍のcmd起票に繋がらない。LG030再発構造
- **行動**: gate_shogun_startup.sh Gate 20.7追加。code_fix_requiredパターンをstartup gateのWARNに接続(14日フィルタ付き)
- **commit**: b68f85eb
- **原理**: 既存の強制経路(startup gate)に乗せる(LG032)

## なぜなぜ2: review_log 0バイト破壊

- **気づき**: 本セッション中にgunshi_review_log.yamlが0バイトに。git show HEADから復元
- **根因**: gunshi_gate_sync.sh L95/L129のawk→tmp→mvパターンがflock未使用。並行cmd_complete_gate.sh(nohup+disown)と競合→TOCTOU
- **行動**: flock -w 10排他制御 + -sチェック(awk出力0バイト時mvスキップ)追加
- **commit**: da64d73e
- **波及**: cmd_complete_gate.sh L5821 dashboard.md書込みにも同根リスク→cmd_2872で一括修正(APPROVE済み)
- **原理**: background化スクリプトの全共有ファイル書込みにflock必須

## なぜなぜ3: 報告レビュー依頼の重複送信

- **気づき**: 本セッション全6報告で重複依頼(11-89秒差)。軍師が毎回「処理済み」と返す無駄サイクル
- **根因**: (1) notify_gunshi_for_report(自動: inbox_write.sh report_received hook) と (2) 家老LLMの手動inbox_write(karo.md手順)の二重経路。自動化導入時に旧手順を削除していない
- **行動**: 掲示板で将軍にcmd提案(blt_20260519_144020)。karo.mdから手動転送手順を削除し、notify_gunshi_for_report自動送信に統一
- **原理**: LG032逆パターン—自動化を入れたが旧手順を残した

## 共通パターン

3件とも「自動化が入ったが手動経路が残存」の構造:
1. Gate 20.7: 自動エスカレーション(skill_auto_improve)→手動cmd起票(将軍)の間に断絶
2. flock: 自動並行化(nohup+disown)→手動flock管理(なし)の間に断絶
3. 重複依頼: 自動通知(notify_gunshi_for_report)→手動通知(家老)の重複

**原理1行**: 自動化を入れたら手動経路を消せ。両方残すと二重実行か断絶が起きる。
