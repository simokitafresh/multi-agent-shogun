# GA-238 context freshness root cause (dm-signal-core/ops/research 3件 + gate/dashboard判定経路不一致)

- cmd: cmd_karo_hotfix_ga238_context_freshness_202607131350
- 記録者: tobisaru
- 日付: 2026-07-13

## 結論(3問回答)

### Q1: なぜ発火したか(直接原因・根本原因)

3ファイルとも直接原因は同一パターン: DM-Signal repoの`docs/research`(複数context fileが
pathspecとして共有する高頻度更新ディレクトリ、07-13時点でcmd_3868/3869/3870/3872/3873の
非決定性precompute調査が並行進行中)へ着地した実commitが、各contextのpathspecに
一致し`min_source_commits=1`(GA-226固定下限)を満たしてALERTした。

| context file | 発火commit | 発火日時(JST) | 件名 |
|---|---|---|---|
| dm-signal-core.md | (cmd_3856関連commit) | 2026-07-12 | P3a共通executor統合 |
| dm-signal-ops.md | `c84bcd93` | 2026-07-13 11:54 | docs: nondeterminism redesign v1.4.16 |
| dm-signal-research.md | `bd1a1b10` | 2026-07-13 早朝 | docs: nondeterminism redesign v1.4.15 (P4 live deploy確定) |

根本原因(2軸、GA-237調査を継承):
1. `docs/research`はdm-signal-ops.md/dm-signal-research.mdの両方のpathspecへ
   ディレクトリ丸ごと組み込まれており、同一commitが複数context fileを同時ALERTさせる
   (GROUP機構で可視化済み、GA-237で実装)。
2. **source_commitマーカーを持たないcontext file(core.md/frontend.md/dm-signal.md)は
   date境界(`last_updated+1日`)でgit logするため、同日中に複数commitが着地する
   高頻度更新期間では反映が最大1日遅れる構造的ギャップが今も残る**(ops.md/research.mdは
   GA-236/237でsource_commitマーカー導入済みだが、core.md/frontend.md/dm-signal.mdは
   未導入 — AC2の横断確認で現物確認、詳細は下記「同型穴の現状」参照)。

### Q2: なぜ発火後に3件が現行0件へ遷移したか(分類)

3件とも**真の知識反映**であり、境界更新のみでの解消でも別task偶然解消でもない:

| context file | 対応task | 分類 | 備考 |
|---|---|---|---|
| dm-signal-core.md | cmd_karo_hotfix_dm_signal_core_freshness_202607120345(saizo) | 真の知識反映 | P3a共通executor統合の核心不変量変更を索引層へ還流 |
| dm-signal-ops.md | GA-237(kotaro) | 真の知識反映(訂正後) | **初回提出はGROUP可視化のみの境界更新寄り判定だったが、家老RCで「AC2要件未達」と指摘され、§72を実質書き換え(P4 AC2 FAIL・restore-locked原状回復)に訂正**。docs/research/ga237_context_freshness_root_cause.md参照 |
| dm-signal-research.md | GA-236(kotaro) | 真の知識反映 | GA-220 reflux guardのTOCTOUギャップ(git add+commit連結でstaged判定が無音skip)を修正し、§57へv1.4.15の内容を反映。source_commitマーカーを初採用 |

**ただし「現行0件」は本cmd起票時点のスナップショットに過ぎず、恒常状態ではない**。
DM-Signalの`docs/research`は cmd_3868→3869→3870→3872→3873 の非決定性調査で
数十分〜数時間単位の頻度で更新され続けている。本cmd実行時点(2026-07-13 13:53)で
git logを直接実行した実測値:

```
$ git -C /mnt/c/Python_app/DM-signal log --oneline bd1a1b10..HEAD -- docs/research analysis outputs tasks/lessons.md marketing-director
4a57a81f cmd_karo_hotfix_cmd3868_inventory_perf_202607131225: ...
68fc3d95 docs: nondeterminism redesign v1.4.17 ...
1ac02744 cmd_3872: input snapshot差分契約を記録
c84bcd93 docs: nondeterminism redesign v1.4.16 ...
→ 4件(dm-signal-research.mdのpathspec)
```

3件とも既に**新たな真のALERTが再発火済み**(dm-signal-core.md 1件・dm-signal-ops.md 2件
・dm-signal-research.md 4件、いずれも`CFC_GIT_TIMEOUT`を緩めた状態で本cmd中に実測)。
これは検知不良の再発ではなく、DM-Signal側の更新頻度がcontext反映サイクルより速いという
運用上の事実であり、GA-236→GA-237→GA-238と同型の後続cmdが必要になる(follow-up候補として
decision_candidateへ記録)。

### Q3: なぜ「13:48通常gate=OK」と「直後のdashboard_update=dm-signal-research.md ALERT 4件」が
食い違ったか(判定経路/キャッシュ/pathspec不一致の根因)

**直接原因は`scripts/gates/gate_context_freshness.sh`のfail-open分類バグ**(本cmdで修正)。

再現手順:

```bash
# 1. gate経路と同条件(GIT_TIMEOUT=1s、gateのデフォルト)で直接check_scriptを実行
$ CFC_GIT_TIMEOUT=1 CFC_OUTPUT_CACHE_TTL=0 bash scripts/context_freshness_check.sh --dashboard-warnings
WARN: source_commit_count_since git failed: ... timed out after 1 seconds  (frontend.md/research.md/ops.md/他複数で発生)
WARN: context/dm-signal-research.md source commit check failed since last_updated=2026-07-13。timeout/returncodeを確認せよ
（実行時間: 約2.0秒。WSL2 DrvFs/9P上で複数pathspec(docs/research,analysis,outputs,tasks/lessons.md,marketing-director)を
  git log --name-onlyでスキャンする処理が、他エージェントの並行commit/checkout I/Oと直列化され1秒を超える。L307と同型)

# 2. dashboard_update経路と同条件(デフォルトtimeout=3s、CFC_GIT_TIMEOUT未指定)で実行
$ CFC_OUTPUT_CACHE_TTL=0 bash scripts/context_freshness_check.sh --dashboard-warnings
ALERT: context/dm-signal-research.md source commits 4件 since last_updated=2026-07-13。... latest: 4a57a81f | 68fc3d95 | 1ac02744
（3秒timeoutなら間に合い、真のALERTを検出）
```

`context_freshness_check.sh`自身は正しく設計されている: git subprocessが失敗/timeoutした
場合、`source_commit_summary_since()`は`-1`を返し、呼び出し元は
`WARN: <path> source commit check failed ... timeout/returncodeを確認せよ`という
**「未確定」を明示するWARN**を出力する(隠蔽していない)。

バグは**`gate_context_freshness.sh`側の消費ロジック**にあった。同スクリプトは
`context_freshness_check.sh`の出力行から`source_alerts[rel_path]`という連想配列に
「真のALERT行(`ALERT:...source commits...`)」だけを記録し、それ以外の行(check-failed
WARNも含む)は単に`target_rel_paths`へ積むだけで終わっていた。後段の分類ループは
`source_alerts`に該当エントリがなければ`days_ago`(last_updatedからの経過日数)だけを見て
OK/WARNを判定する。**「未確定(check failed)」と「確認済みでALERT該当なし」を区別する手段が
なかった**ため、`last_updated`が当日更新(0日前)のファイルはcheck-failedであっても
無条件で`OK: ...(0日前更新)`に分類されていた — fail-open。

`gate_context_freshness.sh`はデフォルトで`CONTEXT_FRESHNESS_GATE_GIT_TIMEOUT=1`(1秒)と
`dashboard_auto_section.sh`側の`context_freshness_check.sh`呼び出し(timeout未指定=
デフォルト3秒)より厳しいtimeoutを使う設計になっており、WSL2 9P環境下の並行I/O負荷
(L307)でtimeoutに引っかかる頻度がgate側で有意に高い。これが「gate=OK / dashboard=ALERT」
という経路間の不一致を生んだ直接メカニズムである。

なお、`gate_context_freshness.sh`には300秒の出力キャッシュ(`CONTEXT_FRESHNESS_GATE_CACHE_TTL`)
もあるが、そのキャッシュ署名(sig_parts)はcontext/*.mdファイル自身のmtimeと
`config/projects.yaml`/`context/cmd-chronicle.md`/`queue/archive/cmds`のみを対象とし、
**DM-Signal側リポジトリの新規commitはキャッシュ無効化条件に含まれない**。このため
fail-openで一度「OK」を記録すると、その後DM-Signal側で新たなsource commitが着地しても
最大5分間は古い「OK」が再利用され続ける — fail-openバグの影響時間を拡大する副次要因。
(この300秒キャッシュ自体は意図的なコスト最適化であり、閾値緩和ではないため本cmdでは
変更しない。fail-openを止めれば「未確定→OK」の誤りは根本的に無くなるため、この副次要因は
実害が閉じる)

## GA-239追加証拠の再現計測(家老指摘、本cmdスコープ内で対応)

家老から「codd.md/dm-signal-frontend.mdでもsource commit確認がtimeout/returncode。
GA-238と同カテゴリゆえ各論パッチ化せず、既存の更新トリガー/timeout設計の横展開対象として
原因・防御層・偽陽性率へ含めよ」と追加指摘(msg_20260713_140658)。2件を個別に再現計測した:

| context file | 対象repo | pathspec | 実測git log所要時間 | 実件数(timeout=10sで確定) | 1s/3s timeoutでの帰結 |
|---|---|---|---|---|---|
| codd.md | 自リポジトリ(multi-agent-shogun) | scripts/codd, scripts/codd_, skills/codd, skills/codd-refactor | **6.32秒** | 0件(真陽性なし) | 1s/3sとも失敗(WARN化) — 自リポジトリでもWSL2 9P並行I/O下では低速。real=0件のため見逃してもALERT実害はないが、**「未確認」を「OK」と誤表示していた点はcore/ops/researchと同じfail-openバグ** |
| dm-signal-frontend.md | DM-Signal repo | frontend, docs/research/frontend-components.md, docs/research/frontend-api-spec.md, docs/research/frontend-deploy.md, docs/research/fe-speed-improvement-design.md | **3.89秒** | **2件**(d80a8b03 cmd_3839 visibility folder-hide、bbd546b8 cmd_3787 monthly trade missing tickers) | 1s timeoutで確実に失敗。**3s(dashboard_update側のデフォルト)も僅差(3.89s>3s)で失敗しうる** — dashboard側も無条件に安全ではない |

結論: この2件は`min_source_commits`やpathspec設計固有の問題ではなく、**gate/dashboard共通の
git subprocess timeout値がWSL2 9P環境の実測所要時間(3.9〜6.3秒)を下回っている**という
同一カテゴリの根因であり、本cmdのAC3修正(check-failedのfail-closed化)がそのまま両ファイルに
適用される(コード変更は`gate_context_freshness.sh`1箇所のみで、ファイル固有の個別パッチは
不要)。dm-signal-frontend.mdは実際に2件の真ALERTを抱えており、修正後は正しくWARN
(「ALERT見逃しの可能性あり」)として可視化される — 個別パッチではなく横展開対象として
本cmdのAC2/AC4に統合済み。

## 修正(AC3: 再発を作れない防御層)

`scripts/gates/gate_context_freshness.sh`:
- `check_failed_paths`連想配列を新設し、`context_freshness_check.sh`の出力行のうち
  `WARN:...source commit check failed...`にマッチする行のrel_pathを記録する。
- 後段の分類ループで、`source_alerts`に該当なしでも`check_failed_paths`に該当する
  rel_pathは**必ずWARN**として扱う(days_agoベースのOK分類より優先、ALERTより劣後)。
  メッセージは「source commit確認失敗: timeout/returncode...ALERT見逃しの可能性あり」と
  明示し、`CONTEXT_FRESHNESS_GATE_GIT_TIMEOUT`を緩めた再実行 or 一次情報(git log)での
  手動確認を促す。
- `min_source_commits`(GA-226固定下限=1)・ALERT発火条件・timeout値そのものは一切変更
  していない(閾値緩和禁止/timeout隠蔽禁止の制約を遵守。「隠蔽」の逆 — 未確定を
  積極的に可視化する)。

波及先確認(read-onlyで実挙動確認済み):
- `scripts/cmd_complete_gate.sh` — `context_freshness_check.sh --cmd-warnings`を
  直接呼び出し出力を`/dev/null`へ破棄するのみ。`gate_context_freshness.sh`は呼ばず、
  本修正の影響なし。
- `scripts/gate_auto_respond.sh` / `scripts/gate_improvement_trigger.sh` /
  `scripts/clear_prep_check.sh` — いずれも`gate_context_freshness.sh`をexit code
  (0=OK/1=ALERT/2=WARN)で消費する既存契約のみに依存。新規exit codeは導入していない
  (check-failedは既存のexit=2 WARN契約に自然に合流するだけ)。
- `scripts/dashboard_auto_section.sh` — `gate_context_freshness.sh`を呼ばず
  `context_freshness_check.sh`を直接呼ぶ別経路のため無関係。
- `scripts/ninja_monitor.sh` — 出力全体のcksumで変化検知するのみ。新規WARN行の追加は
  cksum変化として正しく検知される(意図した挙動)。

## 同型穴の現状(AC2: dm-signal/frontendを含む横断確認、本cmdでは未修正・follow-up候補)

`context/*.md`のうち、`source_commit:`マーカーを持つファイルと持たないファイルの現状:

| context file | source_commitマーカー | 現状(2026-07-13 13:5x実測) |
|---|---|---|
| dm-signal-ops.md | あり(`c84bcd93`) | GA-237で導入済み。ただし境界以降2件が既に未反映(再ALERT中) |
| dm-signal-research.md | あり(`bd1a1b10`) | GA-236で導入済み。ただし境界以降4件が既に未反映(再ALERT中) |
| dm-signal-core.md | **なし** | date境界(last_updated+1日)方式のまま。GA-236/237以前と同型の同日複数commit見逃しリスクを保持 |
| dm-signal-frontend.md | **なし** | 同上。pathspecが`frontend`ディレクトリ全体を含み、git logがWSL2 9P上で1秒timeoutに頻繁に抵触することを本cmdで実測確認(fail-open修正後は正しくWARN化) |
| dm-signal.md(索引) | **なし** | 同上。pathspecは狭い(terminology/disambiguation/db-operations-runbookのみ)ためtimeoutリスクは相対的に低い |

`source_commit`マーカー未導入の3ファイルへ同マーカーを追加する対応は、現時点で
dm-signal-core.md/dm-signal-frontend.mdに**未反映の実ALERTが存在する**ため、
「既存context本文を読まずにlast_updated/source_commitだけ更新して解消扱いにしない」
という制約に抵触せずに実施するには各ファイルの実内容レビューが必要であり、本cmdの
スコープ(検知メカニズムの修正)を超える。decision_candidateとしてfollow-up cmd
(GA-239相当)への引き継ぎを推奨する。

## AC1: 数値化サマリ

| context file | pathspec hit件数(境界〜HEAD) | root_fallback | cache有無 | 通常gate timeout(1s)での実測 |
|---|---|---|---|---|
| dm-signal-core.md | 1件(0568b016) | 無(dm-signal project専用pathspec) | context_freshness_check.sh内2秒cache + gate側300秒cache | 実行毎に成否が揺れる(本cmd中1回成功・1回timeout WARN化を観測) |
| dm-signal-ops.md | 2件(68fc3d95, 0568b016) | 無(cited:pathspecフィルタ適用) | 同上 | 同上 |
| dm-signal-research.md | 4件(4a57a81f, 68fc3d95, 1ac02744, c84bcd93) | 無(docs/research全体スコープ、cited化なし) | 同上 | **timeout=1sでは高確率で失敗**(5pathspec同時git log --name-only) |

## 因果

`[[docs/research高頻度更新(cmd_3868-3873非決定性調査)]] -> [[dm-signal-core/ops/research.mdのpathspec重複]] -> [[真の知識反映で個別に0件化(saizo/GA-236/GA-237)]] -> [[しかしdocs/research更新が継続し3件とも再ALERT]] -> [[gate_context_freshness.shの1秒timeoutがWSL2 9P並行I/O(L307)で頻発]] -> [[check-failed WARNをsource_alertsが拾わずdays_agoベースのOK分類へfail-open]] -> [[13:48通常gate=OK/直後dashboard_update(3秒timeout,raw出力)=ALERT 4件の不一致として観測]] -> [[GA-238でcheck_failed_pathsを追加しfail-closedへ修正、防御層として恒久化]]`
