# Slop-Scan Don't-Fix — 修正すべきでないパターン集
<!-- GStack/GBrain takeaway #28 (CLAUDE.md Slop-scan don't-fix) -->
<!-- 出典: GStack CLAUDE.md §Slop-scan don't fix patterns (takeaway #28) -->

> 目的: 忍者の「ついで修正」「善意の過剰変更」を防ぐ。スコープ外変更は問題を隠す（自動消火禁止原則）。
> 使い方: 変更しようとしている箇所がこのリストに該当するなら **停止して lesson_candidate に記録し、家老に委ねよ。**

## 鉄則

「修正しなければ壊れ続けるか？」→ **NO** なら触れるな。
AC に書かれていない変更は全て Deviation Rule 4（停止→報告）扱い。

---

## 修正すべきでないパターン一覧

| # | パターン | 理由 | 代わりにすること |
|---|---------|------|----------------|
| SDF-01 | スタイル統一のみの変更（命名規則の不統一、インデント揃え等） | 動作変わらず。差分ノイズ。レビュー負荷増 | decision_candidate に「命名ルール制定」として記録 |
| SDF-02 | コメントの追加・削除・言い換えだけ | ロジックに影響しない。Slopのシグナル | 必要ならlesson_candidateに記録して家老に委ねる |
| SDF-03 | 証明なしの「dead code」削除 | 削除対象が本当に未使用か確認不能。実行パスが存在する可能性 | 「unused code detected」をknowledge_candidateに記録、偵察タスクとして確認を依頼 |
| SDF-04 | 計測なしのパフォーマンス最適化（micro-opt） | 効果未証明。回帰リスク。CoDD計測なしの変更は禁止 | gs-bench-gate/CoDD refactorでbeforeを先に計測 |
| SDF-05 | 意見が分かれるリファクタリング（AC参照なし） | 設計変更は将軍のcmd承認が必要 | decision_candidateに記録→家老→将軍→cmd起票 |
| SDF-06 | 空白行・改行コードの追加/削除のみ | 差分ノイズ。意図不明 | 触れるな |
| SDF-07 | ログメッセージの文言変更（動作変わらず） | モニタリング/アラートの正規表現が壊れる可能性 | 触れるな。改善提案はlesson_candidate |
| SDF-08 | スコープ外ファイルへの変更（ACに記載なし） | Deviation Rule 4: 設計変更=停止→報告 | 変更先ファイルをdecision_candidateに記録して停止 |
| SDF-09 | 警告を黙らせる変更（# noqa, # type: ignore, pass except等） | 問題の隠蔽。自動消火禁止原則違反。根本修正が必要 | 警告の原因を調査してlesson_candidateに記録。修正は別task |
| SDF-10 | 証明なしの「未使用変数・import」削除 | 動的参照（getattr, importlib等）で実際には使われている可能性 | knowledge_candidateに記録して偵察で確認 |
| SDF-11 | エラー握りつぶし（except: pass, catch() {}） | エラーを隠す最悪の消火。障害発生時に原因が特定できなくなる | FAIL報告してblocked状態で停止。家老に委ねよ |
| SDF-12 | テストの期待値を「通るように」書き換え | テストは番人。期待値改ざんは意味を失う | FAIL理由をlesson_candidateに記録して停止 |

---

## DM-Signal 固有の禁止パターン

| # | パターン | 理由 |
|---|---------|------|
| DM-SDF-01 | pipeline_config の fallback パス追加（ALM/SSS切替等） | 汚染データ混入リスク。PI-003/PI-009違反。別cmdで設計承認必須 |
| DM-SDF-02 | GS CSV列定義の黙示的変更 | downstream の型チェックが全て崩れる。explicit schema変更が必要 |
| DM-SDF-03 | recalculate_fast.py の「高速化ついで修正」 | Phase間の依存が複雑。CoDD計測+全Phase検証なしに触れるな |

---

## 判断フロー

```
変更しようとしている ─┬─ ACに明示的に書かれている? ──YES──→ 実装OK
                    │
                    └─ NO ──→ SDF-01〜12 に該当するか?
                                │
                                ├─ YES ──→ 停止。lesson_candidate/decision_candidate に記録
                                │
                                └─ NO ──→ Deviation Rule 1-3 に該当するか確認
                                            ├─ Rule 1-3: 実装して deviation 欄に事後記載
                                            └─ Rule 4: 停止して報告
```
