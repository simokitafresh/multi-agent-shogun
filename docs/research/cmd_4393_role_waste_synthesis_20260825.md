# cmd_4393 ロール別覚醒調査 — 統合正本(AC4)

- 作成: 2026-08-25T00:20+09:00 将軍(doc lane)
- 発端: 殿指示2026-08-24 23:51『作業中のgate品質問題や同じ試行錯誤の繰り返しは無駄。各ロールに独自の問題がないか覚醒して調査しよう』
- 一次成果物: `logs/cmd_4393_karo-waste.json` / `logs/cmd_4393_gunshi-waste.json` / `logs/cmd_4393_ninja-waste.json`(全てreport format PASS・集計コマンド埋込済み)
- 将軍分の一次調査: 本文§1(将軍セッション内実測 2026-08-24 23:51-00:01)

## §1 ロール別の固有無駄(全て一次台帳の機械集計)

| ロール | 支配的無駄 | 実測 | 出典 |
|---|---|---|---|
| **家老** | **deploy再試行の反復** | issued 7,547件中blocked 4,529件(60.0%)。同一cmd再試行1,271件(728 cmd、issued比16.8%)。top: cmd_4200=20回 | karo-waste.json deploy_ledger |
| 家老(副) | 実workaroundは少ない | workaround_true 11/100(89件はauto_captured rework) | 同 workaround_ledger |
| **軍師** | **同一cmdのFAIL/再レビュー反復** | 42 entries中24 unique cmd・multi_entry 12 cmd・extra 18件。cmd_4387=FAIL×3→LGTM等 | gunshi-waste.json observed |
| 軍師(副) | review_bundle遅延 | 1,244 events中央値9.7秒・P95 52.6秒・10秒超612件・最大492秒 | 同 review_bundle_tail |
| **忍者** | WA自体は低率(0.3%) | 直近30窓でWA4件/assigned 1,332。支配=shared_yaml_concurrency 3/4 | ninja-waste.json |
| 忍者(副) | **モデル帰属欠測** | gate台帳772行中unknown 355/362 dedup cmd(98.1%)=モデル別比較が分母欠測で不能 | 同 model_tendency |
| **将軍** | 起票gate摩擦(歴史) | cmd_design_quality 200件中BLOCK 80件(40%)。直近20件は0件(改善済み) | logs/cmd_design_quality.yaml python集計 |
| 将軍(現行) | **cmd_save preflight遅延** | 単発cmdで120秒超timeout(cmd_4393実測)→INS-20260825-000142753 | セッション実測 |

## §2 共通構造(ロール横断)

1. **「blocked→再試行」ループが計測されずに常態化** — 家老deploy 60% block・軍師FAIL反復・将軍歴史BLOCK 40%は同型: **gateが後段で発火し、前段に契約が伝わっていない**(前倒し検査の欠如)。
2. **台帳の書込みはあるが読み手/帰属が欠ける** — モデル帰属unknown 98.1%、tmp残骸(cmd_design_quality系44+gunshi_review_log系16)。LS078(書き手と読み手の別ストア)の再現。
3. **検査自体の遅さ** — cmd_save 120秒超・review_bundle P95 52.6秒。gate_evaluation 86%減で実証済みのフェーズ分解の型が未適用の領域。

## §3 根治候補(優先順位・次弾cmd入力)

| P | 候補 | 根拠 | 型 |
|---|---|---|---|
| **P0** | 家老deploy blocked 60%の内訳分解→上位block理由の前倒し化(配備前チェックの契約を起票/report段へ) | repeat 1,271件=最大母数 | gap分解と同じ: 分布確定→支配段根治 |
| **P0** | 軍師レビューFAIL反復の前倒し(terminal/evidence契約を初回precheckへ集約=GUNSHI-WASTE-01) | multi_entry 12/24 cmd | 同上 |
| **P1** | cmd_save preflightフェーズ分解→支配段短縮 | 120秒超実測 | gate_evaluation 86%減の型 |
| **P1** | review_bundle P95 52.6秒の支配段短縮 | 10秒超612件 | 同上 |
| **P2** | gate_metricsへモデル帰属の記録欠測根治(unknown 98.1%) | モデル別修行(training-cycle)の分母復旧 | 台帳品質 |
| **P2** | 台帳tmp残骸のatomic書込み後始末(60個規模) | 並行書込み失敗痕跡の放置 | 掃除+再発防止 |

## §4 境界

- 本正本は抽出と序列のみ。根治実装は次弾cmd(P0から順次)。
- 忍者Trackのmodel別断定はunknown 98.1%のため保留(P2根治後に再集計)。
- kagemaru Track(cmd_4392ローカルテスト分解)は走行中。CI側確定分=テスト実行90.7%支配は`hayate_report_cmd_4392`参照。
