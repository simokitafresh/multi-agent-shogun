<!-- gist-master: 0c95806223c8ad666cfa13fec2eb226b gist-master-sync-asis-tobe-5w1h_20260801.md -->
# gist正本同期+スキル化+index再設計 AsIs/ToBe 5W1H v1.3 【⚙稼働中・実装完了・将軍検分済み】

作成: 2026-08-01 21:25 将軍 / 発端: 殿指示 21:20「gistとローカルの正本は常に同期していたほうがいいな」+ 21:22「gistに共有はスキル化」+ 21:24「gist indexのカテゴリも実際にフィットしていない」

> レビュー状態: 軍師=APPROVE条件付き(blt_024837: 因果一本・fail-open正当。条件=タグなし分類ルールの明確化) / 家老=REVISE(blt_024843: 一次計測3系+必須修正7点)→**本v1.1で全点反映**(独立性担保: 両者相互不可視で査読、将軍が2026-08-04 02:50に統合)

## §版履歴
- v1.3(2026-08-04 13:22): **軽微所見を解消** — 状態タグなしAsIs/ToBeをカテゴリ「設計書・状態未確認」へ分離し、`unknown_status`ログ件数とindexカテゴリ件数の一致を実データで検証。
- v1.2(2026-08-04 13:00): **実装完了反映(将軍コードレビュー済み)** — 依存DAG 1a/1b/2/3/4全実装。commit: 51ec2cd70(index pagination+再分類)、1b59eaa18+191b4115f(writer --master blob同期/flock/newer-skip/owner-secret検証/pending台帳/bounded timeout+reconcile fail-close)、650f72b31(post-commit fail-open trigger+sync_git_hooks)、0f14e3560(/gist-shareスキル+孤立gist防御)、2c0f6851c(稼働中3正本へメタ行backfill)。軍師事前・事後review全件LGTM+各GATE CLEAR。家老独立実測: focused 5/5・remote secret owner一致・commit blob byte一致3/3・pending 0。将軍検分所見: 家老RC1-RC7・軍師条件(unknown_status別計上)全て現物コードで充足。軽微所見1件=classify_gist()がタグなしAsIs/ToBeへカテゴリ「設計書・稼働中」を付与しつつstatus=unknown_statusで別計上する実装(設計意図の「昇格保留」はカウント可視化で担保、許容)。§詳細=§実装完了状態
- v1.1(2026-08-04 02:55): **覚醒更新(殿指示02:40)** — 実装状況の一次実測(ToBe 3項とも未実装: post_commit_files=0/gist_share_skills=0/index旧7カテゴリ現存。メタ行のみ2 docsに普及)+家老REVISE 7点+軍師条件1点を反映。gist総数185(list 100の85件欠落)判明によりAC全面二値化。実装分解を依存DAGへ再分割
- v1.0(2026-08-01 21:25): 初版

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | gist正本とローカル正本の同期が意志依存(手動3点セット規律のみ)で、素の`gh gist edit`+手動diff代用が実際に発生(2026-08-01将軍、MECE正本v3.3更新時)。同期漏れ=復帰点・正本の信頼喪失 |
| WHAT | (1)正本の自己記述メタ行+commit時自動同期(構造型) (2)/gist-shareスキル(入口の標準化) (3)index実態カテゴリ再設計 |
| WHO | 実装=忍者(家老配備)。利用=全ロール+全CLI(skills正本共有) |
| WHEN | 設計承認後、1道具1CMDで順次起票 |
| WHERE | scripts/gist_verified_write.sh(既存)+git hook+skills/gist-share/+scripts/gist_index_update.sh |
| HOW | 既存道具に乗せる(新規状態管理ゼロ)。下記§1-§3 |

## §AsIs追補(2026-08-04覚醒実測 — 将軍02:45+家老一次計測blt_024843)

| 対象 | 実測 | 帰結 |
|---|---|---|
| ToBe実装状況 | post_commit_files=**0** / gist_share_skills=**0** / index=旧7カテゴリ現存(将軍がgist_index_update.sh現物確認) | **ToBe 3項とも未実装**。起票以来3日間、AsIsの意志依存は継続(本日将軍のCDP設計書v2.4同期も手動gh gist edit+sha検証=AsIsの実例) |
| メタ行普及 | `rg -l gist-master docs/research`=**2件**(research total 924 md) | メタ行仕様のみ自然普及が始まったが、hookなしでは検証されない片肺 |
| gist総数 | `gh api --paginate gists`=**185件** vs `gh gist list -L 100`=100件 | **現行indexは85件(46%)欠落**。全件ACはAPI paginationなしに成立しない(家老計測A) |
| index分類実態 | dry-run: 研究データ・分析レポート=82/note記事=13/インフラ他=4/週報=1/その他3カテゴリ=0 | 汎用bucket 82%=再設計WHYを一次データが支持(家老計測C) |

## §AsIs(2026-08-01実測)

| 対象 | 現状 | 問題 |
|---|---|---|
| dashboard.md | gist_sync.shデーモンが常時自動同期 | なし(唯一の自動) |
| docs/research正本群 | 手動3点セット規律(正本Edit→gist同期→commit)+gist_verified_write.sh(push型・手動) | **意志依存**。素のgh gist edit使用が実際に発生。正本↔gist対応はsemantic-mapに散在し機械可読でない |
| gist index | gist_index_update.shの固定7カテゴリ(note記事/週報/研究データ・分析レポート/deepdive・将軍記録/ユーザー向け/インフラ・確定申告・比較分析/前処理研究) | **実態と乖離**。gh gist list 100件実測: 大半が「AsIs/ToBe 5W1H設計書」(状態タグ【✅CLOSED/⚙稼働中/📋設計済】付き)であり、「週報」「確定申告」「前処理研究」はほぼ流量ゼロの陳腐化項目 |

## §ToBe

### §1 正本自己記述メタ行+commit時自動同期(構造型・意志依存ゼロ)

- 正本mdファイル冒頭に1行: `<!-- gist-master: <gist_id> [remote_filename] -->`
  - 対応表・registryは**新設しない**(殿原則: 新しい状態管理は避ける)。正本が自分のgist先を宣言する
- git post-commit hookが、commitに含まれる`docs/research/*.md`のうちメタ行を持つファイルを検知→`gist_verified_write.sh`で自動同期+remote raw bytes一致証明。不一致はWARN表示+ログ(logs/gist_sync_verified.jsonl)
  - pre-commitでなくpost-commit採用理由: 同期失敗でcommitを止めない(gist到達不能時にローカル作業を封鎖しない=fail-open。同期漏れは次commit時・startup gate表示で回収)
  - git hookはCLI非依存=multi-CLI大原則(実行機構の一本化禁止)に抵触しない共通境界
- **同期対象=当該commitのblob(家老RC1)**: 作業treeファイルの同期は複数worktree同時commitで旧内容が後勝ちするrace。`git show <commit>:<path>`のblobを同期し、**gist単位flock+commit/blob identityの記録+publish直前の最新性検証**(自分より新しいcommitのpublish済みなら自分をskip)を必須とする
- **fail-open回収経路(家老RC2)**: 次commitが失敗対象を含まないと再試行されない穴を塞ぐ — (a)失敗をdurable pending(logs/gist_sync_verified.jsonlのstatus=pending行)として記録 (b)reconcile=全meta正本走査でpending+hash不一致を検出し再同期(startup gate表示または定期) (c)全gh呼出しにbounded timeout必須(現gist_verified_write.shのtimeout指定0件=家老一次実測)
- **メタ行仕様の明確化(家老RC6)**: remote_filename省略時=ローカルbasename。rename時=メタ行を更新した側が正(旧filenameのgist fileはverified_writeが--filenameで置換)。複数file gist=remote_filename必須。同期前にowner=自分・visibility=secretを検証し、不一致は同期拒否+pending。初回create途中失敗(gist作成済み・メタ行未埋込)の孤立gistは、reconcileがtitle+content hash一致で検出し候補提示(自動削除はしない)
- 二値AC針: メタ行保持の全正本(N=`rg -l gist-master`の件数を明示)について `remote_hash == local_hash` がN/N一致+pending残0件(検証スクリプト1本で機械判定)

### §2 /gist-shareスキル化 — 将軍見解: **賛成**

理由:
1. **§1のhookと相補**: hook=同期漏れの構造防止(無自覚)、スキル=「このdocをgistへ共有する」意図的行為の入口標準化。初回共有(gist作成→ID取得→メタ行埋込→verified_write→index更新)は判断を含みhook化できない。ここがスキルの領分
2. **今日の実証**: 将軍が素のgh gist edit+手動diffで代用した=道具があっても入口が標準化されていないと使われない(スキル不使用=バグの構造版)
3. **全ロール・全CLI共通**: skillsはプロジェクト正本をClaude/Codex共有済み。評価基準(一致証明)は共通、実行はスキル手順で統一

スキル仕様(skills/gist-share/SKILL.md):
- 入力: ローカル正本パス(+新規なら公開範囲secret固定)
- 手順: 新規=gh gist create→ID取得→メタ行埋込→gist_verified_write再同期→gist_index_update / 既存=メタ行のID読取→gist_verified_write(素のgh gist edit禁止を明記)
- 出力: gist URL+一致証明の生貼付

### §3 index実態カテゴリ再設計(一次データ駆動)

gh gist list 100件のタイトル実測に基づく新カテゴリ案:

| 新カテゴリ | 判定キー(タイトル) | 実態流量 |
|---|---|---|
| 設計書・稼働中 | AsIs/ToBe・5W1H含み+【⚙稼働中】【📋設計済】or 状態タグなし | 多(主流) |
| 設計書・CLOSED | 同上+【✅CLOSED/完了】 | 多 |
| 調査書・監査・レポート | 調査書/監査/レポート/進化量 | 中 |
| 正本・カタログ・パターン | MECE/カタログ/パターン/正本/チェックリスト | 中 |
| 記事・対外発信 | note記事/週報/投資知識辞書/ユーザー向け | 小 |
| その他・運用 | 上記以外(dashboard等) | 小 |

- **状態タグ【】はタイトル中の任意位置から機械抽出**(家老RC4: 末尾限定は現物不足。🔨実装進行中/✅レビュー反映済/✅完了・後継 等の現物語彙を正規化表で定義し、分類precedenceを固定: 明示除外→状態タグ→タイトルキー→fallback)
- **タグなしgistの分類ルール(軍師条件)**: タグなし+AsIs/ToBe含み→「稼働中」と即断せず**unknown_status**として別計上する。稼働中への昇格は鮮度(updated_at)または人手確認による(タグ未付与の古いgistを稼働中へ過剰推定しない)
- **全件取得=API pagination必須(家老RC3)**: `gh gist list -L 100`廃止→`gh api --paginate gists`。実測185件(list 100では85件欠落)
- 旧7カテゴリ(週報/確定申告/前処理研究等)は廃止。分類ロジックはgist_index_update.shのclassify_gist()を差替え(既存スクリプトを磨く、新設しない)
- **二値AC針(家老RC3で空虚AC是正)**: 「未分類0件」はfallback bucketがある限り常にPASSする空虚ACゆえ廃止。代わりに (a)全取得件数=分類件数+明示除外件数の完全一致 (b)unknown_status件数とfallback比率の明示報告 (c)fallback比率が現状82%から有意減(新カテゴリの実効性)の3点を二値化

## §実装分解(依存DAG — 家老RC7で再分割。1道具1CMD)

| # | cmd | 内容 | 依存 |
|---|---|---|---|
| 1a | メタ行schema+検証スクリプト(reconcile含む) | §1のschema/verifier層。blob同期・flock・identity・pending・bounded timeoutの契約をここで固定 | なし |
| 1b | post-commit hook(Claude/Codex共通のgit層trigger) | §1のtrigger層。1aのverifierを呼ぶだけの薄い層 | 1a |
| 2 | /gist-shareスキル新設 | §2。CLI別起動adapterは共有しない(家老RC5: 共有境界=meta schema・hash一致AC・ログschemaまで) | 1a |
| 3 | gist_index_update.sh カテゴリ差替え+API pagination化 | §3 | なし(並行可) |
| 4 | 既存正本へのメタ行backfill(稼働中gistのみ。CLOSEDは対象外) | §1適用。reconcileの初回実走を兼ねる | 1a・1b |

- **multi-CLI境界(家老RC5)**: 全CLIで共有するのは評価基準(meta schema・remote_hash==local_hash AC・ログschema)のみ。実行機構(hookの呼出し方・スキルの起動)はCLIごとに設計(multi-CLI大原則)

## §実装完了状態(2026-08-04 13:00 将軍検分)

| DAG# | 実体 | commit | 検証値(家老独立実測+将軍現物確認) |
|---|---|---|---|
| 1a | scripts/gist_verified_write.sh --master + scripts/gist_master_reconcile.sh | 1b59eaa18 + 191b4115f | commit blob同期(git show blob)・gist単位flock・newer-commit skip(merge-base ancestor判定)・owner=viewer+secret検証・複数file gist明示filename強制・全gh呼出しtimeout --foreground・pending台帳(logs/gist_sync_verified.jsonl)。reconcileはlog欠損/不正JSONLをfail-close BLOCK、latest-entry group化でpending算出 |
| 1b | .githooks/post-commit + scripts/gist_post_commit_sync.sh + sync_git_hooks.sh | 650f72b31 | fail-open(exit 0固定)・working tree不読(diff-tree+committed blobのみ)・総時間budget残量をGIST_TIMEOUT_SECONDSへ伝播・rename/NUL framing対応 |
| 2 | skills/gist-share/SKILL.md + scripts/gist_share.sh | 0f14e3560 | HEAD一致強制(dirty/staged BLOCK)・既存=writer経由+sha一致grep検証+index更新連鎖・新規=secret検証+孤立gist時orphan_candidate情報出力+メタ行atomic install→exit 2でcommit督促 |
| 3 | scripts/gist_index_update.sh再設計 | 51ec2cd70 | gh api --paginate(185件全量)・precedence固定(明示除外→状態タグ→タイトルキー→fallback)・完全一致AC(取得=分類+除外)・unknown_status/fallback_ratio明示出力 |
| 4 | 稼働中3正本メタ行backfill | 2c0f6851c | hot-script-speedup-round4/nxe-2d-robustness/throughput-bottleneck-part2へ1行ずつ。remote secret owner一致・commit blob byte一致3/3 |

- 軽微所見(将軍・解消済み): classify_gist()はタグなしAsIs/ToBeをカテゴリ「設計書・状態未確認」+status=unknown_statusへ分離。タグありは「設計書・稼働中」を維持し、分類ログのunknown_status件数とindexカテゴリ件数を一致させる。
- 本v1.2更新のcommit自体がpost-commit hook経由で本gist(メタ行先頭)へ自動同期される=§1の実走証明

## §スコープ外
- dashboard.mdのgist_sync.shデーモン(現行維持)
- CLOSED済みgistの遡及同期(正本が動かないため不要)
- gist側からローカルへの逆方向同期(正本=ローカルの一方向のみ。gist直編集禁止規律を維持)

## 因果リンク
[[殿指示_gist正本常時同期_20260801]] -> [[意志依存の手動3点セット]] -> [[自己記述メタ行+hook構造化+スキル入口+index実態化]]
