# DM-signal 運用コンテキスト
<!-- last_updated: 2026-02-24 lesson_sync IDシフト修正(+2)+L103/L106/L123追加(24件) -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
研究・検証結果(§19-24) → `context/dm-signal-research.md`

## §6-7 recalculate_fast.py + OPT-E

6Phase+OPT-E(Phase3.7)構成。signal_calc 1,724s→0.53s(3,786倍)。
112件消失バグ(L045)=Phase4 dict miss時continue→日次フォールバック追加(91c04a4)で修正済。
→ `docs/research/cmd_286_recalculate-architecture.md`

## §9 性能ベースライン

| 段階 | 全体 | signal_calc |
|------|------|-------------|
| 初回 | 11,818s | — |
| OPT-A/D/F | 2,397s | 2,007s |
| OPT-E | 389s | 0.53s |

ボトルネック: trade_perf(58.7s) > L3 FoF(~89s) > signal_calc(0.53s)
→ `docs/research/cmd_286_recalculate-architecture.md` §9

## §12 計算データ管理

命名: `{cmd番号}_{ブロック名}_{説明}.csv` + `.meta.yaml`。上書き禁止(`_v2`)。
テンプレ: `scripts/analysis/grid_search/template_gs_runner.py`
CSVローダ: `scripts/analysis/grid_search/gs_csv_loader.py`(cmd_160)
GS全6ブロック: `scripts/analysis/grid_search/run_077_{block}.py`
PD-028裁定: GS制約同期は仕組み化しない。BBカタログにPydantic制約明記+PARAM_GRID修正で運用。
→ `docs/research/ops-procedures.md`

## §14 ドキュメントインデックス

docs/skills/(25件) + docs/rule/(25件)全一覧 + DB接続・パリティ検証・API使用法ルール抜粋。
→ `docs/research/ops-db-rules.md`

## §16 知識基盤改善（穴1/2/3対策完了 — 2026-02-22）

| 穴 | 対策 | cmd |
|----|------|-----|
| 1 教訓登録ボトルネック | auto_draft_lesson.sh | cmd_232+242 |
| 2 知識鮮度管理 | context last_updated+鮮度警告 | cmd_239 |
| 3 裁定伝播遅延 | resolve時context未反映フラグ | cmd_239 |
| 補助 lesson sync上限不足 | sync上限を50に引き上げ | cmd_241 |

原則: 検出+警告のみ。自動修正はしない（指示系統厳守）。

## Ops教訓索引
<!-- lesson_sync: lessons.yaml照合+IDシフト修正(L123/L124新規追加で+2) + L103/L106/L123追加 = 24件 -->

| ID | 結論(1行) | 分類 | 出典 |
|---|---|---|---|
| L135 | 忍法FoF作成12ステップ省略不可(ステップ2-4省略→四神不一致) | PF登録 | — |
| L134 | GS結果利用時DATA_CATALOG+meta.yaml必参照 | データ管理 | — |
| L133 | セッション開始時にtodo.md/lessons.md必読 | 運用手順 | — |
| L132 | GS構成四神と本番FoF構成PFの不一致に注意 | PF登録 | — |
| L131 | 新FoF追加後の再計算はsync-fof(L3)を使う | 再計算 | — |
| L130 | 本番API呼出はPowerShell Invoke-RestMethod | API | — |
| L129 | FoFパリティは本番現行パラメータを先に確認 | パリティ | — |
| L128 | experiments.dbはスナップショット、SSOTではない | DB | — |
| L127 | PowerShell -replace/Set-ContentでUTF-8文字化け | ツール | — |
| L126 | ブロック名はBlockType enum値で統一 | 設定規約 | — |
| L125 | pipeline_configパラメータ名はコードと1:1一致 | 設定規約 | — |
| L123 | WSL2 matplotlib日本語フォント: font_manager.addfont()でWindows側.ttc登録 | ツール | subtask_288 |
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
| 本番PF総数 | 89体(上限100) |
| L3 堅牢性検証 | 未着手(cmd_176殿裁定待ち) |
| 新忍法偵察 | 逆風(cmd_249)/RelMom(cmd_250)/MultiView(cmd_251)偵察中 |
| SVMF/MVMFバグ | 修正完了(cmd_235+cmd_244) |
| 穴1/2/3 | 全対策完了 |
