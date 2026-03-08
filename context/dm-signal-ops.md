# DM-signal 運用コンテキスト
<!-- last_updated: 2026-03-03 cmd_493 リンク整合+loader/API現行化 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
研究・検証結果(§19-24) → `context/dm-signal-research.md`

## §6-7 recalculate_fast.py + OPT-E

6Phase+OPT-E(Phase3.7)構成。signal_calc 1,724s→0.53s(3,786倍)。
112件消失バグ(L045)=Phase4 dict miss時continue→日次フォールバック追加(91c04a4)で修正済。
詳細アーキ資料(`cmd_286_recalculate-architecture.md`)は未復旧。再計算の一次情報は実コード(`backend/app/jobs/recalculate_fast.py`)を参照。
- L155: monthly_trade_calculatorのpending判定はtrigger固定monthlyで全PFに同一ロジック適用していた（cmd_524）
- L157: pending判定は『存在チェック』より先にrebalance月 gatingを入れないと非月次triggerで誤表示する（cmd_525）

## §9 性能ベースライン

| 段階 | 全体 | signal_calc |
|------|------|-------------|
| 初回 | 11,818s | — |
| OPT-A/D/F | 2,397s | 2,007s |
| OPT-E | 389s | 0.53s |

ボトルネック: trade_perf(58.7s) > L3 FoF(~89s) > signal_calc(0.53s)
補助参照: `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` AC1-2（scripts一覧）
- L177: 本番404切り分けはopenapi.json実測でデプロイ未反映を即時判定できる（cmd_553）
- L178: 本番404調査はopenapi実測で『ルート未登録』を先に確定すると切り分けが最短になる（cmd_553）
- L179: 新サービスのimport文とrequirements.txtの突合確認をデプロイ前チェックに含めるべき（cmd_554）
- L180: render.yaml cronジョブ追加時envVars sync:falseのシークレットはRenderダッシュボード手動設定が必要（cmd_554）
- L190: 集計要件でrole分離が必要ならイベント記録時点で識別子を保存しないと後段SQLでは復元不能（cmd_574）
- L202: Render Static Siteのheaders.pathはrootと配下階層を別globで覆わねば全txtを捕捉できぬ（cmd_643）

## §12 計算データ管理

命名: `{cmd番号}_{ブロック名}_{説明}.csv` + `.meta.yaml`。上書き禁止(`_v2`)。
テンプレ: `scripts/analysis/grid_search/template_gs_runner.py` は現treeに不在（再配置待ち）。
ローダ: `scripts/analysis/grid_search/gs_data_loader.py`（現行DBローダ） / `scripts/analysis/grid_search/gs_csv_loader.py`（CSV互換）
GS全6ブロック: `scripts/analysis/grid_search/run_077_{block}.py`
PD-028裁定: GS制約同期は仕組み化しない。BBカタログにPydantic制約明記+PARAM_GRID修正で運用。
補助参照: `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` AC1-2
- L175: 統合レビューでのパリティ検証は関数シグネチャ+定数+アルゴリズム3層で行う（cmd_550）

## §14 ドキュメントインデックス

docs/skills/(25件) + docs/rule/(25件)全一覧 + DB接続・パリティ検証・API使用法ルール抜粋。
補助参照: `docs/research/cmd_485_dm-signal-environment-catalog.md`（環境/Render/API） + `docs/research/cmd_488_dm-signal-claude-config-catalog.md`（運用設定）
- L169: 設計書補完はMECE表+仕様章リンクの二層化で抜け漏れを抑制できる（cmd_549）
- L170: 仕様レビューは章番号突合+commit差分限定の二段検証で誤判定を防げる（cmd_549）
- L184: Docsの新指標説明は判定条件をテーブル化すると実装定義との突合が速い（cmd_557）
- L194: テスト棚卸しcmd発行前にvenv/pytest環境確認を前提条件に含める（cmd_623）

## §16 知識基盤改善（穴1/2/3対策完了 — 2026-02-22）

| 穴 | 対策 | cmd |
|----|------|-----|
| 1 教訓登録ボトルネック | auto_draft_lesson.sh | cmd_232+242 |
| 2 知識鮮度管理 | context last_updated+鮮度警告 | cmd_239 |
| 3 裁定伝播遅延 | resolve時context未反映フラグ | cmd_239 |
| 補助 lesson sync上限不足 | sync上限を50に引き上げ | cmd_241 |

原則: 検出+警告のみ。自動修正はしない（指示系統厳守）。
PD-042反映: DM-signal側24スキルの`allowed-tools`/`argument-hint`/`description`品質改善を一括実施済み（cmd_448）。

- L149: key_files成果物パターンは実在ファイル名規約と定期照合しないと再汚染する（cmd_493）
- L150: 復旧ドキュメントは『在庫あり証跡』と『在庫不足』を分離記述すると誤再構成を防げる（cmd_493）

## Ops教訓索引
<!-- lesson_sync: 2026-03-03 lesson-sortでL129-L146を反映 -->

| ID | 結論(1行) | 分類 | 出典 |
|---|---|---|---|
| L144 | context圧縮時は参照先存在確認を先に実施。リンク先なき圧縮は禁止 | 知識基盤 | cmd_492 |
| L143 | research層消失はリポジトリ側git操作起因の可能性を先に切り分ける | 知識基盤 | cmd_492 |
| L142 | CSV記述は入力ソースと成果物を分離しないと知識汚染が再発する | 知識基盤 | cmd_492 |
| L141 | docs実在性チェックをCI化しないと運用手順が陳腐化する | 知識基盤 | cmd_492 |
| L140 | registry統合など構造変更時は知識汚染が集中する | 知識基盤 | cmd_492 |
| L139 | 依存マップはgrepより先にAST循環解析を実行する | 運用手順 | cmd_478 |
| L138 | trade_perf調査はtiming実測→コード読解の順で進める | 運用手順 | cmd_475 |
| L137 | FoF計測はLayerTimer.substepではなくL3 metadata.profilingで確認 | 運用手順 | cmd_475 |
| L136 | 改善候補調査前に既存最適化履歴を照合する | 運用手順 | cmd_474 |
| L135 | 参照先scripts消滅時は教訓参照をdeprecatedとして明示する（旧L010） | 知識基盤 | cleanup |
| L134 | 参照先scripts消滅時は教訓参照をdeprecatedとして明示する（旧L025） | 知識基盤 | cleanup |
| L133 | セッション開始時にtodo.md/lessons.md必読 | 運用手順 | — |
| L132 | GS構成四神と本番FoF構成PFの不一致に注意 | PF登録 | — |
| L131 | gitignoreパターンとgit復元対象のクロスチェック必須 | 運用プロセス | cmd_430 |
| L130 | commit前にgit diff --cachedでステージ全体を確認する | 運用プロセス | cmd_427 |
| L129 | 注入教訓のreviewed確認を怠ると後続ゲートで詰まる | 運用プロセス | cmd_356 |
| L128 | experiments.dbはスナップショット、SSOTではない | DB | — |
| L127 | PowerShell -replace/Set-ContentでUTF-8文字化け | ツール | — |
| L126 | ブロック名はBlockType enum値で統一 | 設定規約 | — |
| L125 | pipeline_configパラメータ名はコードと1:1一致 | 設定規約 | — |
| L123 | WSL2 matplotlib日本語フォント: font_manager.addfont()でWindows側.ttc登録 | ツール | subtask_288 |
| L152 | レビュータスクのAC4は『対象テストPASS』と『静的検証ベースライン健全性』を分離して判定すべき | 運用プロセス | cmd_515 |
| L158 | WSL上のWindows venvでは .venv/Scripts/python.exe 経由でpytestを実行できる | ツール | cmd_525 |
| L167 | WSLでWindows venv Python分析タスクは端末ログ文字化けに備えてCSV実体検証を必須にする | ツール | cmd_539 |
| L122 | write後はGETキャッシュ明示無効化必須(TTL=3600s) | API/キャッシュ | cmd_283 |
| L121 | backend API実コード確認必須(YAML仕様と乖離あり) | API/FE | cmd_283 |
| L119 | DATA_CATALOGの86銘柄=本番DB、experiments.dbは14銘柄のみ | DB | cmd_282 |
| L118 | DTB3はdaily_pricesにticker='DTB3'格納(economic_indicatorsは空) | DB | cmd_282 |
| L109 | 分析スクリプトにtimeout必須(idle誤判定→clear事故) | 運用 | cmd_274 |
| L107 | DATA_CATALOG掲載+meta.output.file実在で二軸照合 | データ管理 | cmd_265 |
| L106 | deploy_task.sh報告上書き消失(L103再発、構造的対策未実装) | 運用プロセス | cmd_263 |
| L105 | BB config未拘束がGS無効パターン量産根因。build_grid直後に制約注入 | GS | cmd_264 |
| L103 | 報告YAML後続deploy上書き消失。統合タスクは偵察報告と同時deploy | 運用プロセス | cmd_253 |
| L099 | LIKE '%ReversalFilter%'→TrendReversal誤検知。jsonb_path_existsで解決 | DB | — |
| L085 | テストPF削除は16テーブルFK依存順(4テーブルでは不足) | DB | cmd_215 |
| L084 | recalculate-status is_running=None≠完了。DB行数カウントで判定 | 再計算 | cmd_215 |
| L104 | subtask間依存で.gitignoreが後続コミット計画をブロックしうる | 運用プロセス | cmd_259 |
| L082 | `monthly_returns.portfolio_id(varchar)` と `portfolios.id(uuid)` は比較前に `id::text` で型統一 | DB | cmd_214 |
| L081 | recalculate Phase0では`monthly_returns`が一時的に空になる前提で検証順序を組む | 再計算 | cmd_214 |
| L080 | save APIの`success=False`でもDB登録済みケースあり。削除確認はDB直接参照が確実 | API/DB | cmd_207 |
| L079 | sync-fof APIの409 conflictはリトライ+待機で吸収する | API | cmd_207 |
| L076 | Layer lockはプロセス内限定。再計算の終点保存はUPSERTで冪等化する | 再計算 | cmd_212 |
| L075 | 新規PFのrecalculateには`recalculate-sync`を使う | 再計算 | cmd_205 |
| L067 | 殿の個人PF(35体)は本番DBから削除・変更しない | DB運用 | cmd_198 |
| L066 | 殿裁定事項はMCP/projects/lessonsの3箇所に恒久化する | 運用手順 | cmd_196 |
| L064 | 本番データ取得は`DATABASE_URL`でPostgreSQL直結。API経由を避ける | DB/API | cmd_194 |
| L063 | `download_prod_data.py monthly-returns`は大量エラーでもexit 0になりうる | ツール | cmd_194 |
| L038 | `sync_lessons.sh`は`## N.`節末尾で`### L0xx`取りこぼしが起こりうる | ツール | cmd_137 |
| L036 | `recalculate-sync`の`start_date`パラメータは無視される | API/再計算 | cmd_128 |
| L035 | FoF参照L0 PFはDELETE不可。UPDATE方式を採用する | DB運用 | cmd_128 |
| L034 | Claude CodeはRead未実施ファイルへのWrite/Editを拒否する | 運用手順 | karo |
| L029 | `gs_metadata`でFoF鮮度情報を保持し追跡可能化する | データ管理 | — |
| L028 | ユーザー確認なしの設計変更を禁止し、裁定を先に取る | 運用手順 | — |
| L025 | GSスクリプト/データ同期スクリプトはパス規約を統一する | 運用手順 | — |
| L021 | 新規スクリプト作成前に既存スクリプトを必ず調査する | 運用手順 | — |
| L015 | 本番API呼び出しは`requests + HTTPBasicAuth`で実装する | API | — |
| L014 | `experiments.db`と本番DBのUUIDは別体系として扱う | DB | — |
| L011 | WindowsでのYAML/ファイル読込はエンコーディング明示を必須化する | ツール | — |
| L010 | `download_prod_data.py`実行時は`PYTHONPATH`設定を事前確認する | ツール | — |
| L009 | sync-fof APIはQuery Parameter方式（JSON Body不可） | API | — |
| L007 | 新FoF追加後の再計算は`sync-fof`（L3）を使う | 再計算 | — |
| L006 | 本番API呼び出しはPowerShell `Invoke-RestMethod`を使う | API | — |
| L004 | `experiments.db`はスナップショットでありSSOTではない | DB | — |
| L003 | PowerShell `-replace`/`Set-Content`でUTF-8文字化けが起こる | ツール | — |

## §17 現在の全体ステータス（2026-02-22）

| 項目 | 状態 |
|------|------|
| L0 GS生成PF | ~30体(本番登録済み) |
| L1 四神12体 | 本番登録済み+パリティPASS |
| L2 忍法12体 | 本番登録済み+全12体 0.00bp PASS(cmd_246) |
| 本番PF総数 | 未確認（cmd_477後の再集計待ち） |
| L3 堅牢性検証 | 未着手(cmd_176殿裁定待ち) |
| 新忍法偵察 | 逆風(cmd_249)/RelMom(cmd_250)/MultiView(cmd_251)偵察中 |
| SVMF/MVMFバグ | 修正完了(cmd_235+cmd_244) |
| 穴1/2/3 | 全対策完了 |
