# GA-237 context freshness root cause (dm-signal-ops.md)

- cmd: cmd_karo_hotfix_ga237_context_freshness_202607131156
- 記録者: kotaro
- 日付: 2026-07-13

## 結論(家老RC反映後の最終版)

- **直接原因**: `dm-signal-ops.md`のpathspecに含まれる`docs/research`配下へ単一commit
  `c84bcd93`(2026-07-13 11:54 JST、"docs: nondeterminism redesign v1.4.16 — P4 AC2..."、
  `docs/research/cmd_3840_nondeterminism_redesign.md`+`docs/research/cmd_3870_p4_ac2_evidence.md`
  を変更)が着地し、`min_source_commits`(既定1、GA-226で意図的に固定された下限)を満たしてALERT。
  直前のGA-237修正(`fdec9f2f4`、02:57 JST、境界を`bd1a1b10`へ更新)からわずか**8時間57分**後の再発火。
- **根本原因(2軸)**:
  1. `docs/research`はDM-Signalで現在最も活発に更新される共有ディレクトリ
     (07-13時点でcmd_3868/3869/3870/3872の非決定性precompute調査が並行進行中)であり、
     `context/dm-signal-ops.md`と`context/dm-signal-research.md`の**両方**のpathspecへ
     ディレクトリ丸ごと(ファイル単位ではなく)組み込まれている
     (`scripts/context_freshness_check.sh` `DM_SIGNAL_CONTEXT_PATHS`)。このため同一commitが
     複数context fileを**同時に**ALERTさせ続け、既存機構には重複を検出する手段がなかった
     (L1089が直前サイクルGA-236/GA-237・commit `bd1a1b10`で同一パターンを既に記録済み。
     本セッション中も`c84bcd93`で再現をライブ確認)。
  2. `docs/research`ディレクトリ丸ごとのpathspecは、内容の関連性を問わず**あらゆる**commitを
     ALERT対象に含める。過去のops.md向けGA-*系10回の大半が「refresh index」「keep alerts
     until context refresh」のような境界更新のみの一行修正だったのは、この無差別カウントが
     真因である可能性が高い。ただし`min_source_commits=1`はGA-226(L1056)で意図的に固定された
     下限であり("件数閾値を上げるとmerge/squash後にALERTが自然消滅する"ため)、閾値緩和による
     解決は禁止。

## 訂正: 初回分析の誤り(家老RC `msg_20260713_122655` で発覚)

初回提出時、`c84bcd93`は「`dm-signal-ops.md`記載内容と直接の重複なし、境界更新のみで解消」と
判定しGROUP機構(可視化のみ)だけを実装して報告した。家老のRCで「AC2/purposeが要求する
『次回発生前の共通防御』になっていない。min_source_commitsを緩めず、pathspec意味境界/commit
関連性判定/重複group単位判定のいずれかで同一fixtureの再発を0にし、真陽性は維持せよ」と
指摘され、再検証した結果、**この判定自体が誤りだった**ことが判明した:
`dm-signal-ops.md` §72(旧)は`docs/research/cmd_3840_nondeterminism_redesign.md`を
`v1.4.15`として明示的に版番号付きで引用しており、`c84bcd93`はまさにそのファイルを
`v1.4.16`へ更新した commit だった。§72はP4 AC2の実行結果(FAIL・原状回復)という運用上
重要な内容を欠いたまま「本番1run自体は未実行」という古い記述を残していた。
**GROUP機構だけでは(1)この種の真陽性を見逃す実害と(2)将来の真の偽陽性(未引用ファイルへの
無関係commit)によるALERT再発の両方を防げない**、という家老の指摘は的確だった。

## 最終対応(2段構成)

1. **§72の実質内容を修正**: `dm-signal-ops.md` §72をv1.4.16の実態(AC2実行→
   input_snapshot_id不一致でFAIL→restore-lockedで18/18表exact原状回復→次工程cmd_3872)へ
   書き換え、`source_commit`境界を`c84bcd93`へ更新。単なる境界bumpではなく実質反映。
2. **共通防御層(2機構、いずれもmin_source_commits=1は不変)**:
   - **GROUP検出**: 同一source commitで複数context fileが同時ALERTする場合に
     `GROUP:`行で明示し、家老が1cmdで一括反映できるようにする(L1089対策)。
   - **cited pathspecフィルタ(今回のAC2本体)**: `DM_SIGNAL_CONTEXT_PATHS`のdocs/research
     エントリを`context/dm-signal-ops.md`に限り`"cited:docs/research"`へ変更。
     `docs/research`配下のcommitは、そのcontext file自身が本文で`docs/research/xxx.md`と
     **既に名指し引用しているファイル**を変更した場合のみ関連commitとして数える。
     `context/dm-signal-research.md`は`docs/research`全体を網羅追跡するのが本来の役割のため
     このフィルタは付けない(新規未引用ファイルを検知できなくなると本末転倒なため)。

     この設計により:
     - **真陽性は維持**: `c84bcd93`のように、context fileが既に引用しているファイルへの
       変更は引き続きALERTする(fixtureで確認)。
     - **偽陽性は0件化**: context fileが一度も引用していない`docs/research`配下ファイルへの
       単発commitは、今後ALERTを起こさない(fixtureで確認)。過去のops.md向けGA-*系の
       大半を占めていたと推定される「境界bumpのみで実質更新なし」のALERTパターンを、
       将来発生前に構造的に抑止する。

## 一次データ: dm-signal-ops.md last_updated以降のsource commit全件列挙

- 境界: `<!-- source_commit:bd1a1b10... -->`(GA-237前回修正 `fdec9f2f4` が設定)
- コマンド: `git -C /mnt/c/Python_app/DM-signal log bd1a1b10..HEAD -- backend/app/api backend/app/jobs backend/app/services backend/tests docs/rule docs/research render.yaml tasks/lessons.md`
- 該当commit: **1件のみ**

| commit | 日時(JST) | 件名 | 変更ファイル |
|---|---|---|---|
| `c84bcd93` | 2026-07-13 11:54 | docs: nondeterminism redesign v1.4.16 — P4 AC2 executed and FAILED on input_snapshot_id mismatch, exact restore complete, next=cmd_3872 input diff recon | `docs/research/cmd_3840_nondeterminism_redesign.md`(ops.mdが§72で版番号付き引用済み), `docs/research/cmd_3870_p4_ac2_evidence.md`(新規、証跡ファイル) |

## 未反映知識の判定(訂正版)

`c84bcd93`は`dm-signal-ops.md` §72が引用する正本ファイルのバージョンアップであり、
P4 AC2の実行結果(FAIL・restore-locked原状回復)という運用上重要な内容を含む。
`dm-signal-ops.md`へ実質反映が**必要**と判定し、§72を書き換えた(上記「最終対応」参照)。

## 同カテゴリ横展開候補

1. **`context/dm-signal-research.md`**: 同一commit `c84bcd93`で同時にALERT中(一次確認済み)。
   本cmd実装のGROUP機構により、家老は次回このペアを1cmdで一括反映できる。§57は本cmd時点で
   v1.4.15のまま未反映であり、別cmdでの反映対象として残る。
2. **`context/dm-signal-frontend.md` / `context/dm-signal-core.md`**: 現状は`docs/research`を
   ファイル単位でスコープしており本問題の直接対象外。
3. **infra root-fallback契約グループ**(例: `context/memory-db-queries.md`と
   `context/memory-db-schema.md`は`INFRA_CONTEXT_PATHS`で**完全に同一のpathspec**を持つ)。
   本cmdのGROUP機構・cited機構ともに`_root_fallback_commit_count_since()`が
   commitハッシュ・変更ファイル明細を返さない実装のため**この経路には未適用**
   (スコープ外、既知のギャップとしてlesson_candidateへ記録)。
4. **他context fileへのcited機構横展開**: `context/dm-signal-research.md`の`docs/research`
   (主目的スコープのため対象外)以外に、将来pathspecが広域ディレクトリを二次スコープとして
   持つcontext fileが増えた場合、同じ`"cited:"`パターンを再利用できる。

## 変更対象ファイル・波及先・関連テスト・エッジケース・依存順序(偵察5要件)

- **変更対象ファイル**: `scripts/context_freshness_check.sh`(`build_group_warnings()` +
  `load_cited_paths()` + `_commit_touches_relevant_path()`を追加。`source_commit_summary_since()`
  へ`abs_path`引数を追加し`cited:`pathspecフィルタを実装。`--dashboard-warnings`/
  `--cmd-warnings`両モードへ組み込み)、`context/dm-signal-ops.md`(§72実質更新+境界更新)
- **波及先ファイル**(全てread-onlyで実挙動を確認し副作用なしと確認済み):
  - `scripts/gates/gate_context_freshness.sh` — `^(WARN|ALERT):`正規表現でrel_path抽出する
    ためGROUP行は素通り(マッチせずスキップ)。既存exit code(0/1/2)ロジックに影響なし。
  - `scripts/dashboard_auto_section.sh` — 出力を丸ごとdashboardへ転記するのみ(パース無し)。
  - `scripts/cmd_complete_gate.sh` — `--cmd-warnings`呼び出しは出力を完全破棄。影響なし。
  - `scripts/ninja_monitor.sh` — 出力全体のcksumで変化検知するのみ。GROUP/cited適用による
    出力変化もcksum変化として正しく検知される(意図した挙動)。
  - `context/dm-signal-research.md`/他のDM_SIGNAL_CONTEXT_PATHSエントリ — `cited:`prefixを
    付けていないため`cited_dirs`は空リストとなり、既存コードパスと完全に同一の挙動を維持
    (`source_commit_summary_since`内の`if cited_dirs and not ...`はcited_dirsが空なら
    常にFalseで従来通りカウント)。回帰なしをfixtureで確認。
- **関連テスト**: `tests/unit/test_context_freshness_check.bats`(34件→42件、新規8件追加:
  GROUP発火/GROUP非発火/linked worktree/並行呼出し/timeout誤検知なし/cited偽陽性0件化/
  cited真陽性維持/cited非対象pathspec真陽性維持)、`tests/unit/test_gate_context_freshness.bats`
  (8件、無変更で回帰確認)。詳細な二値結果はtaskの報告YAML参照。
- **エッジケース・副作用**: (1)GROUP対象はALERT確定エントリのみ、(2)cited判定は
  `cited_dirs`が空の全ての既存context fileに対し無効化(no-op)、(3)出力は既存通り
  `sorted(dict.fromkeys(...))`でソートされ順序に悪影響なし、(4)linked worktreeでも
  git log計上は影響を受けない、(5)並行呼び出し時もatomic mvキャッシュ書き込みは無傷、
  (6)commit subjectにquote/backtick/heredoc様の文字列が含まれても安全に処理される
  (手動fixtureで確認)。
- **依存関係・順序制約**: GROUP計算は各context fileのALERT/WARN判定確定後に実行。
  cited判定は`git log --name-only`で変更ファイル一覧を取得した後、AUTO_COMMIT_SUBJECT_RE
  フィルタ通過後・カウント確定前に適用する。`min_source_commits`(GA-226固定下限=1)には
  一切触れない。

## 実行証跡

```
$ CFC_ARCHIVE_CACHE=/tmp/kotaro_cfc_final bash scripts/context_freshness_check.sh --dashboard-warnings
(dm-signal-ops.md/GROUP行なし — §72実質更新+境界更新後、ALERT解消をライブ確認)
```

修正前(§72が古い状態、境界=`bd1a1b10`)の同コマンド出力は以下だった(本cmd冒頭で記録済み):
```
ALERT: context/dm-signal-ops.md source commits 1件 ... latest: c84bcd93 docs: nondeterminism redesign v1.4.16 ...
ALERT: context/dm-signal-research.md source commits 1件 ... latest: c84bcd93 docs: nondeterminism redesign v1.4.16 ...
GROUP: context/dm-signal-ops.md,context/dm-signal-research.md share source commit c84bcd93 ... — 家老は1cmdで一括反映を検討せよ(重複調査防止, L1089)
```

## 因果

`[[c84bcd93(docs/research進捗更新、ops.md引用ファイル更新)]] -> [[dm-signal-ops.mdとdm-signal-research.md共有pathspec]] -> [[min_source_commits=1(GA-226固定下限)]] -> [[両contextの同時ALERT]] -> [[初回誤判定:境界更新のみで解消と誤認]] -> [[家老RCで指摘:AC2要件未達]] -> [[§72実質更新+cited pathspecフィルタ実装(最終対応)]]`
