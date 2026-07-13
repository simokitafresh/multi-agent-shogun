# GA-237 context freshness root cause (dm-signal-ops.md)

- cmd: cmd_karo_hotfix_ga237_context_freshness_202607131156
- 記録者: kotaro
- 日付: 2026-07-13

## 結論

- **直接原因**: `dm-signal-ops.md`のpathspecに含まれる`docs/research`配下へ単一commit
  `c84bcd93`(2026-07-13 11:54 JST、"docs: nondeterminism redesign v1.4.16 — P4 AC2..."、
  `docs/research/cmd_3840_nondeterminism_redesign.md`+`docs/research/cmd_3870_p4_ac2_evidence.md`
  を変更)が着地し、`min_source_commits`(既定1、GA-226で意図的に固定された下限)を満たしてALERT。
  直前のGA-237修正(`fdec9f2f4`、02:57 JST、境界を`bd1a1b10`へ更新)からわずか**8時間57分**後の再発火。
- **根本原因**: `docs/research`はDM-Signalで現在最も活発に更新される共有ディレクトリ
  (07-13時点でcmd_3868/3869/3870/3872の非決定性precompute調査が並行進行中)であり、
  `context/dm-signal-ops.md`と`context/dm-signal-research.md`の**両方**のpathspecへ
  ディレクトリ丸ごと(ファイル単位ではなく)組み込まれている
  (`scripts/context_freshness_check.sh:444-460` `DM_SIGNAL_CONTEXT_PATHS`)。
  対照的に`dm-signal-frontend.md`は`docs/research/frontend-*.md`のようにファイル単位で
  スコープされている。`min_source_commits=1`はGA-226(L1056)で意図的に固定された下限であり
  ("件数閾値を上げるとmerge/squash後にALERTが自然消滅する"ため引き上げ禁止)、緩和できない。
  結果として、この共有ディレクトリへの**あらゆる**単発commitが、内容の関連性を問わず
  複数のcontext fileを**同時に**ALERTさせ続け、かつ既存機構にはその重複を検出する手段が
  なかった。家老は同一commitを別々のcmdとして2忍者へ重複配備することになり
  (L1089が直前サイクルGA-236/GA-237・commit `bd1a1b10`で同一パターンを既に記録済み)、
  この現象は一過性ではなく**構造的に繰り返す**。
  - **一次データでの再現確認(本セッション、07-13 12:1x JST)**:
    `CFC_ARCHIVE_CACHE=/tmp/kotaro_cfc_test2 bash scripts/context_freshness_check.sh --dashboard-warnings`
    実行結果、`context/dm-signal-ops.md`と`context/dm-signal-research.md`が**全く同じcommit
    `c84bcd93`**を根拠にたった今同時ALERT中であることを確認した(本cmd実装後は`GROUP:`行で
    この重複が明示される)。

## 一次データ: dm-signal-ops.md last_updated以降のsource commit全件列挙

- 境界: `<!-- source_commit:bd1a1b10... -->`(GA-237前回修正 `fdec9f2f4` が設定)
- コマンド: `git -C /mnt/c/Python_app/DM-signal log bd1a1b10..HEAD -- backend/app/api backend/app/jobs backend/app/services backend/tests docs/rule docs/research render.yaml tasks/lessons.md`
- 該当commit: **1件のみ**

| commit | 日時(JST) | 件名 | 変更ファイル |
|---|---|---|---|
| `c84bcd93` | 2026-07-13 11:54 | docs: nondeterminism redesign v1.4.16 — P4 AC2 executed and FAILED on input_snapshot_id mismatch, exact restore complete, next=cmd_3872 input diff recon | `docs/research/cmd_3840_nondeterminism_redesign.md`, `docs/research/cmd_3870_p4_ac2_evidence.md`(新規) |

この1件は「P4 AC2本番1run実行→FAIL→原状回復完了」という非決定性precomputeパイプラインの
進捗更新であり、`dm-signal-ops.md`が記述するOPT-Eフェーズ構成/crash-safety/DB SSOT/deploy運用
とは直接の内容重複がない(≒未反映の実質知識はほぼ0)。しかし`docs/research`ディレクトリ全体が
pathspecに含まれるため機械的にALERTした。

## 未反映知識の判定

`c84bcd93`の内容(P4 AC2 FAIL+restore-locked原状回復+次工程=cmd_3872)は`dm-signal-ops.md`の
既存記述(OPT-E/recalculate_fast.py/deploy/crash-safety)と直接の技術的関連が薄く、`dm-signal-ops.md`
へ追記すべき実質的な未反映知識は**なし**と判定する(境界更新のみで足りる)。

## 同カテゴリ横展開候補

1. **`context/dm-signal-research.md`**: 同一commit `c84bcd93`で同時にALERT中(一次確認済み、上記)。
   本cmd実装のGROUP機構により、家老は次回このペアを1cmdで一括反映できる。
2. **`context/dm-signal-frontend.md` / `context/dm-signal-core.md`**: 現状は`docs/research`を
   ファイル単位でスコープしており本問題の直接対象外だが、`docs/research`配下のファイルが増える
   ほど将来的な重複リスクがある。定期的なpathspec棚卸しの対象候補。
3. **infra root-fallback契約グループ**(例: `context/memory-db-queries.md`と
   `context/memory-db-schema.md`は`INFRA_CONTEXT_PATHS`で**完全に同一のpathspec**
   (`scripts/memory_db_,scripts/lord_conversation_,data`)を持つ)。本cmdのGROUP機構は
   `_root_fallback_commit_count_since()`がcommitハッシュ明細(`details`)を返さない実装のため
   **この経路には未適用**(スコープ外、既知のギャップとしてlesson_candidateへ記録)。
4. **pathspec全体の棚卸し**: `docs/research`のようなディレクトリ丸ごとのpathspecを、
   `dm-signal-frontend.md`のようなファイル単位スコープへ narrowing する対応は、
   個別context file単位の変更になるため本cmdでは実装しない(「個別context追記で閉じるな」
   の指示に反するため)。将来のGA-*サイクルで頻度が収束しない場合の次善候補として記録する。

## 変更対象ファイル・波及先・関連テスト・エッジケース・依存順序(偵察5要件)

- **変更対象ファイル**: `scripts/context_freshness_check.sh`(`build_group_warnings()`追加、
  `--dashboard-warnings`/`--cmd-warnings`両モードへ組み込み)
- **波及先ファイル**(全てread-onlyで実挙動を確認し副作用なしと確認済み):
  - `scripts/gates/gate_context_freshness.sh` — `^(WARN|ALERT):`正規表現でrel_path抽出する
    ためGROUP行は素通り(マッチせずスキップ)。既存exit code(0/1/2)ロジックに影響なし。
  - `scripts/dashboard_auto_section.sh` — `context_freshness_check.sh`の出力を丸ごと
    dashboardへ転記するのみ(パース無し)。GROUP行は情報として追加表示されるだけ。
  - `scripts/cmd_complete_gate.sh` — `--cmd-warnings`呼び出しは`>/dev/null 2>&1`で出力を
    完全破棄。影響なし。
  - `scripts/ninja_monitor.sh` — 出力全体のcksumで変化検知しdashboard再生成のトリガーに
    使うのみ。GROUP行の出現/消失もcksum変化として正しく検知される(意図した挙動)。
- **関連テスト**: `tests/unit/test_context_freshness_check.bats`(34件→39件、新規5件追加)、
  `tests/unit/test_gate_context_freshness.bats`(8件、無変更で回帰確認)。詳細な二値結果は
  taskの報告YAML参照。
- **エッジケース・副作用**: (1)GROUP対象はALERT確定エントリのみ(WARN/check-failedは対象外、
  異常系での誤グルーピングなし)、(2)同一commitでも参照context fileが1件のみならGROUP行は
  出力しない(閾値2件以上)、(3)出力全体は既存通り`sorted(dict.fromkeys(...))`でソートされる
  ためGROUP行が既存WARN/ALERT行の順序へ悪影響を与えない、(4)linked worktreeが存在する
  source repoでもgit log計上は影響を受けない(fixtureで確認)、(5)並行呼び出し時も
  一時ファイル→atomic mv方式のキャッシュ書き込みは既存のまま変更しておらず破損しない
  (fixtureで確認)。
- **依存関係・順序制約**: GROUP計算は各context fileのALERT/WARN判定が確定した**後**に
  実行する(`alerted_for_group`へALERT確定分のみ蓄積→ループ終了後に`build_group_warnings()`
  を1回呼ぶ)。`min_source_commits`(GA-226が固定した下限=1)には一切触れない
  — ALERTの発火条件・タイミングを変更しない設計を厳守した。

## 実行証跡

```
$ CFC_ARCHIVE_CACHE=/tmp/kotaro_cfc_test2 bash scripts/context_freshness_check.sh --dashboard-warnings
ALERT: context/dm-signal-ops.md source commits 1件 since last_updated=2026-07-13。更新要否を確認せよ latest: c84bcd93 docs: nondeterminism redesign v1.4.16 — P4 AC2 executed and FAILED on input_snapshot_id mismatch, exact restore complete, next=cmd_3872 input diff recon
ALERT: context/dm-signal-research.md source commits 1件 since last_updated=2026-07-13。更新要否を確認せよ latest: c84bcd93 docs: nondeterminism redesign v1.4.16 — P4 AC2 executed and FAILED on input_snapshot_id mismatch, exact restore complete, next=cmd_3872 input diff recon
GROUP: context/dm-signal-ops.md,context/dm-signal-research.md share source commit c84bcd93 docs: nondeterminism redesign v1.4.16 — P4 AC2 executed and FAILED on input_snapshot_id mismatch, exact restore complete, next=cmd_3872 input diff recon — 家老は1cmdで一括反映を検討せよ(重複調査防止, L1089)
```

## 因果

`[[c84bcd93(docs/research進捗更新)]] -> [[dm-signal-ops.mdとdm-signal-research.md共有pathspec]] -> [[min_source_commits=1(GA-226固定下限)]] -> [[両contextの同時ALERT]] -> [[家老による重複cmd起票リスク(L1089再発)]] -> [[GROUP検出による可視化(本cmd)]]`
